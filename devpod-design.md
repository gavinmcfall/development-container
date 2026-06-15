# Devpod design — WSL2 → Kubernetes dev environment

Design for moving Gavin's daily Claude Code dev environment off WSL2 onto a
single persistent pod in the home-ops cluster. Companion to
`HANDOFF-devpod-migration.md` (original plan) and the profiling kit (sizing).

## Sizing (from 3.6 days of live profiling, Jun 10–13)

Measured, not guessed. Per-session PSS mean **1.6 GB** (p95 2.2, max 5.0).
Whole workload (≈8 concurrent sessions): mean **12.9 GB**, p95 **15.5 GB**,
peak **20.9 GB**. The handoff's 4.5 GB/session guess was ~3× inflated
(vmmem/RSS double-counting). **repoql is ~60% of memory** — the dominant
driver (per-session, un-pooled).

| | Original placeholder | **Profiled** |
|---|---|---|
| Request | 24–32 GB | **16 GB** (covers p95) |
| Limit | 48–64 GB | **24–28 GB** (absorbs 21 GB peak, evict-last) |

CPU not yet measured (profiler tracks RAM only). Optional profiler extension
before finalizing CPU limits; RAM is ready to act on.

## a) OS — Ubuntu 24.04 (match exactly)

WSL2 is **Ubuntu 24.04.4 LTS (Noble)**. Base image: `ubuntu:24.04`. A dev pod
is not where to chase a slim image — apt parity and muscle memory win.

## b) Migration model — image (declarative) vs PVC (data)

Rule: **toolchain is rebuilt from the Dockerfile; data is copied once to the
PVC.** Never migrate apt installs by copying — re-declare them.

The toolchain is larger than the handoff assumed (it is NOT mise-based):

| Layer | Reality | Count |
|---|---|---|
| apt manual | `inventory/apt-manual.txt` | 216 |
| Homebrew (linuxbrew) | `inventory/brew-list.txt` / `Brewfile` | 126 |
| Languages | node 22 (nvm), go 1.22, rust 1.93 (cargo), python 3.14 (brew), uv, pipx | — |
| Shell | zsh + oh-my-zsh + starship 1.22 + tmux | — |
| Dotfiles | **chezmoi** (already in use → clean migration path) | — |

**Build (image):** curated apt set + nvm/go/rust/uv + standalone CLIs.
WSL/host-only packages are dropped (wsl-setup, linux-realtime, snapd,
update-manager-core, motd-*, console-setup, udev, docker-ce → rootless podman).
**Seed (PVC, one-time):** `rsync` `~/code`/repos, `~/.claude`, `~/.ssh`,
`~/.config`, `~/.secrets`, and `chezmoi apply` for the rest of the dotfiles.

## c) zsh / omz / starship / secrets

Binaries (`zsh tmux`, starship installer, chezmoi) in the image; **config rides
the PVC home** (`~/.zshrc`, `~/.oh-my-zsh`, starship config). Because `$HOME`
is persistent, the shell is identical on first login. Default shell set to zsh
for the gavin user in the image.

Secrets — **two-phase**:
- **Now:** `~/.secrets` lives on the PVC (encrypted at rest via Ceph), sourced
  from `.zshrc` exactly as today. Zero behaviour change.
- **Later (upgrade):** graduate `~/.secrets` to an **ExternalSecret** pulling
  from 1Password (the existing cluster pattern), projected into the pod as a
  mounted file or env. Removes the long-lived plaintext from `$HOME`; rotation
  flows through 1Password. Tracked as a follow-up, not a blocker. See
  `## Secrets upgrade (1Password)` below.

## d) User identity — gavin, uid 1000

WSL2: `uid=1000(gavin) gid=1000`. The image creates `gavin` (uid 1000, home
`/home/gavin`, shell zsh); the pod `securityContext` sets `runAsUser: 1000`,
`runAsGroup: 1000`, `fsGroup: 1000` so the PVC mounts owned by gavin and every
hardcoded `/home/gavin/...` path works. (Drop the host `docker` group →
rootless podman in-cluster.)

## e) tmux — one SSH, windows not tabs

Persistent tmux server in the pod; **one window per Claude session**, switch
with the prefix key — one terminal tab total. Auto-attach on SSH:

```
ssh devpod -t 'tmux new -A -s main'
```

Add **tmux-resurrect + tmux-continuum** to snapshot layout to the PVC; after a
pod restart (node drain) the windows rebuild, then `claude --resume` per window
restores context. This is the accepted recovery path for the rare interruption.

## f) SSH + Tailscale — and LAN stays on LAN

The cluster already runs the **Tailscale operator** (`network/tailscale`).
Expose the devpod as a tailnet node with **Tailscale SSH** enabled — no sshd,
no key management; auth via tailnet identity + ACLs. Then `ssh gavin@devpod`
from any device.

**LAN vs WAN:** Tailscale **automatically uses a direct LAN path** when both
ends are on the same network (it discovers local endpoints and connects
peer-to-peer). It only relays via a DERP server (the WAN hop) when it can't
punch a direct route. So at home on the cluster's subnet you are already direct
over LAN — nothing to configure. Verify with `tailscale ping devpod` (`direct`
+ LAN IP vs `via DERP`).

## VS Code over Tailscale (instead of hand-rolled Remote-SSH)

The **Tailscale VS Code extension** (`tailscale-dev/vscode-tailscale`) adds a
Machine Explorer: browse tailnet machines, open terminals, edit remote files,
and **Attach VS Code** — all powered by Tailscale SSH. So VS Code connects over
the tailnet without manually maintaining `~/.ssh/config` Remote-SSH entries.

Requirements (all cheap to enable): **Tailscale SSH** on the devpod,
**MagicDNS**, **HTTPS certificates** enabled in the tailnet, and `tailscale` on
PATH. Caveat: a known "Attach VS Code times out" issue exists
([#9297](https://github.com/tailscale/tailscale/issues/9297)) — fallback is
plain **Remote-SSH to the MagicDNS hostname `devpod`**, which works regardless
since Tailscale SSH backs both. Plan: install Remote-SSH **and** the Tailscale
extension; prefer the extension's Attach, keep Remote-SSH as the reliable
fallback.

Docs: [Tailscale VS Code extension](https://tailscale.com/docs/integrations/vscode-extension),
[Machine Explorer](https://tailscale.com/blog/machine-explorer-vscode-extension).

## Secrets upgrade (1Password) — later

Phase-2 task, deliberately deferred so the initial cutover is low-risk:

1. Inventory `~/.secrets` keys → corresponding 1Password items (Kubernetes vault).
2. ExternalSecret templates them into a k8s Secret.
3. Project into the pod as `/run/secrets/devpod.env` (or individual env), and
   `source` that from `.zshrc` instead of the plaintext `~/.secrets`.
4. Remove plaintext `~/.secrets` from the PVC once parity is confirmed.

Benefit: no long-lived plaintext secret in `$HOME`; rotation via 1Password;
matches the cluster norm (ESO + onepassword-connect).

## Deployment shape (to finalize)

- **Image:** built in CI (`Dockerfile`), pushed to `zot.nerdz.cloud`.
- **Workload:** BJW-S `app-template` HelmRelease, single replica, high
  `priorityClassName`, request 16 GB / limit 24–28 GB (from sizing).
- **Home PVC:** Rook-Ceph RBD (repos, `~/.claude`, keys, dotfiles, `~/.secrets`).
- **Tailscale:** operator-exposed node, Tailscale SSH.
- **Per-project isolation inside:** direnv + per-language managers; rootless
  podman for projects needing containers; git worktrees on the PVC for
  multi-session-same-repo.

## Open items

- [x] Curate apt/brew into the image — done via usage audit
      (`inventory/tool-usage-report.md`); Dockerfile reconciled.
- [x] Brew tools converted to binary installs (no linuxbrew needed for the
      common path); codex + gemini CLIs added.
- [ ] Decide the VERIFY-set: PHP stack, python3.11, nmap, redis-tools, dotnet,
      apt python libs (nltk/numpy/tqdm) — currently excluded from base.
- [ ] CPU profiling (optional) before setting CPU limits.
- [ ] Confirm Tailscale operator exposure method (Ingress vs sidecar) + ACLs.
- [ ] Node-affinity: does 16 GB request schedule comfortably on the MS-01s
      after Ceph/CNPG, or label a "fat" node?
