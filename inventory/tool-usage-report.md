# Tool-usage audit — evidence base for image curation

Answers "what do I actually use" by merging **two** invocation sources, because
neither alone is complete:

1. **atuin** (`~/.local/share/atuin/history.db`) — commands *Gavin* typed
   interactively (11.5k commands).
2. **Claude transcripts** (`~/.claude/projects/**/*.jsonl`, 1,274 files / 1.2 GB)
   — every `Bash` tool invocation *Claude* ran. **This is the dominant source**
   and is invisible to shell history.

Scripts: `mine-transcripts.py` (extracts tool-heads from Bash calls, incl. inside
pipes/`&&`/`;`/`$()`), `merge-usage.py` (merges + classifies). Re-runnable.

## Critical gotchas this surfaced

- **Claude is the main invoker.** e.g. `kubectl` 4,028 · `grep` 15,793 ·
  `git` 8,434 · `jq` 316. Auditing by what Gavin types alone is wrong.
- **Binary name ≠ package name.** Usage must be mapped through an alias table or
  you cut things you need:
  `go-task`→`task` (210 uses), `cilium-cli`→`cilium`, `kubernetes-cli`→`kubectl`,
  `ripgrep`→`rg`, `fd-find`→`fd`, `python@3.14`→`python3`, `openjdk`→`java`.
- **Libraries aren't "invoked."** 83 of 126 brew formulae are dependency libs
  (cairo, freetype, openssl@3, zlib…) — keep by dependency, never by usage.

## Brew (126) — classification

**KEEP — used by Gavin or Claude (count = combined, last-used):**
kubectl 4028 · python 3153 · flux 731 · talosctl 425 · jq 316 · **task 210** ·
k9s 141 · kustomize 127 · **kubeconform 79** · yq 76 · chezmoi 57 · helm 49 ·
cloudflared 32 · hugo 32 · talhelper 30 · **codex 26** · rclone 17 · **age 16** ·
**shellcheck 14** · cilium 9 · sops 3 · direnv 3 · flux-operator-mcp 2 · croc 1 ·
glab 1 · krew 1 · tesseract 1.

**DROP — zero invocations either side (13):**
`b2-tools`, `dive`, `git-crypt`, `helmfile`, `hub-tool`, `jadx`, `moreutils`,
`pv-migrate`, `stern` — safe to drop.
⚠️ **Verify before cutting (likely build/runtime deps, not directly invoked):**
`cmake`, `libarchive`, `lzo`, `openjdk` — keep if anything compiles against them.

**LIBRARIES — keep by dependency (83):** alsa-lib, cairo, freetype, glib,
openssl@3, readline, sqlite, zlib, harfbuzz, pango, … (full set in merge-usage.py).

## Notable discoveries

- **`codex` 26 invocations** — Gavin actively uses Codex CLI (relevant to the
  multi-tool telemetry plan). `flux-operator-mcp`, `talhelper`, `kubeconform`,
  `yq`, `kustomize` all real and used.
- Backups: `restic` 0 both sides (uses kopia/volsync instead) → drop.

## apt (216) — classification (`apt-pass.py`)

Split: **53 base/essential** (Priority required/important — always keep) ·
**92 lib/no-bin** (no executable → keep by dependency) · **34 KEEP** (binary
invoked) · **37 raw drop-candidates** — but apt cross-ref is NOISIER than brew,
so the 37 needs human judgement (do NOT auto-cut).

**KEEP — binary invoked (top):** git 8946 · gh 2209 · curl 1562 · binutils 651 ·
sqlite3 442 · jq 316 · 1password-cli 226 · helm 98 · python3-pip 46 · wget 28 ·
unzip 26 · rclone 17 · tree 16 · google-cloud-cli 15 · zsh 15 · pipx 14 ·
mkdocs 12 · tailscale 10 · llvm 9 · skopeo 7 · ffmpeg 6 · sops 3.

**Three false-drop traps in the 37 (KEEP these despite 0 direct invocations):**
- **Subcommand binaries:** `git-lfs` is run as `git lfs …` → head-parser sees
  `git`, not `git-lfs`. Keep.
- **`*-dev` build deps:** `python3-dev`, `libxml2-dev`, `libxmlsec1-dev`,
  `libsdl2-dev` expose only `*-config` helpers; needed to *compile* (lxml/xmlsec).
- **Indirect/system + browser deps:** `nfs-common`, `cifs-utils` (mount helpers,
  kernel-invoked — Gavin mounts TrueNAS), `xvfb`, `dbus-x11`, `xclip`, `x11-utils`
  (Playwright/headless-browser MCP + clipboard), `xz-utils`, `bash-completion`,
  `htop`.

**GENUINE drops (apps, unused by both, safe):** `docker-ce` (→ rootless podman),
`k8sgpt`, `packer`, `terraform`, `mame-tools`, `gddrescue`, `testdisk`, `restic`
(uses kopia), `transmission-cli`, `update-manager-core`, `snapd`, `xterm`.

**WSL-only — drop for a pod (won't work anyway):** `adb`, `scrcpy` (USB/Android,
last used Jan).

**VERIFY before cutting (whole stacks unused in the capture window):** the **PHP
stack** (`php-cli`, `php8.2-cli`, `php8.4-cli` + php8.x-* libs) — zero PHP
invocations; `python3.11` (secondary; noble ships 3.12 + brew 3.14);
`redis-tools`, `nmap`, `python3-nltk/numpy/tqdm` (used via import, not CLI →
better per-project via uv than baked into base).

**Action:** reconcile the `Dockerfile` apt list against the KEEP set — it should
*add* what was missed (sqlite3, 1password-cli, binutils, skopeo, google-cloud-cli,
mkdocs, llvm, tailscale) and *omit* the genuine-drop apps.

## How to check "last time invoked" (the original question)

- **atuin** (precise, interactive): `SELECT COUNT(*), datetime(MAX(timestamp)/1e9,'unixepoch') FROM history WHERE command LIKE 'X %'`
- **Claude transcripts** (precise, agent): `mine-transcripts.py`
- **atime** (coarse, binaries): `find /usr/bin -atime +90` — caveat: `/` is `relatime`.
- **Going forward** (exact): process accounting — `apt install acct` → `lastcomm`.
