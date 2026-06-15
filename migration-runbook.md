# Migration runbook — WSL2 → devpod (pre-cutover prep)

Run BEFORE deploying the pod. Goal: get `~/code` + `~/.claude` into a clean,
consolidated state on the PVCs so the cutover is smooth and `claude --resume`
keeps working. Driven by the reality found 2026-06-14: **81 git repos** scattered
across `$HOME`, with large *regenerable* gitignored content.

## Why this is triage, not a blind copy

`find ~ -name .git` returns 81 repos, but they are not all "work to migrate":
- **Tool installs** (git-cloned): `.nvm` (3 GB), `.oh-my-zsh`, `.myth-prompt-themes`
  → rebuilt by the image / chezmoi. **Exclude.**
- **Vendored / reference copies**: `bjw-s-helm`, `bjw-s-labs-*`, `cluster-template`,
  `helm-charts`, `Forked-Repos/*`, `cloned-repos/*` → re-clone on demand. **Archive, don't migrate.**
- **Regenerable gitignored bulk**: node_modules, `.venv`, `__pycache__`, build/dist,
  downloaded datasets (p4k/SC data, model caches). e.g. `scbridge/tools` 7 GB,
  `datap4k-mcp` 6 GB, `lootgoblin` 2.6 GB, `fleet-manager` 3.2 GB. **Regenerate in-pod, don't copy.**
- **Active work repos**: the ones you actually develop in. **Migrate to `~/code`.**

The migration is the moment to shed dead weight, not carry it forward.

## Phase 0 — Triage (decide what moves)

Produce three lists (a helper can rank by last-commit + last-`cd` from atuin):
- **MIGRATE** → consolidate under `~/code/<name>`
- **ARCHIVE** → backed up, not placed in `~/code` (re-clone if needed later)
- **EXCLUDE** → tool/vendored installs (image/dotfiles rebuild them)

Decisions needed from Gavin: confirm the three buckets, and the consolidation
root (`~/code` proposed).

## Phase 1 — Backup (safety net, BEFORE any move)

Repos hold **gitignored things not in any remote** — a `git clone` alone loses
them. Back up the MIGRATE + ARCHIVE sets *including* gitignored, to durable
off-box storage first:

```bash
# full snapshot incl gitignored (excludes only the truly disposable)
rsync -aHAX --info=progress2 \
  --exclude='node_modules/' --exclude='.venv/' --exclude='__pycache__/' \
  --exclude='.git/' \
  <repo>/ truenas:/mnt/backups/wsl2-migration/<repo>/
# (a parallel git-bundle of each repo captures full history compactly)
```

Separately, capture **precious gitignored** (the stuff that's NOT regenerable and
NOT in git): `.env`, `.envrc`, `*.local`, local SQLite DBs, `data/`, credentials.
Per repo: `git ls-files --others --ignored --exclude-standard` minus the
regenerable patterns = the files that MUST survive. (Phase-2 helper surfaces these.)

## Phase 2 — Consolidate folders + migrate Claude data (CCM)

Two distinct steps — **CCM does NOT move repo files**, only the Claude data:

```bash
# 2a. move the repo files (the actual folder)
mkdir -p ~/code && mv ~/my_other_repos/lighthouse ~/code/lighthouse

# 2b. repoint Claude conversations + memory + history.jsonl to the new path
cd ~/scratch/ccm
python3 ccm.py migrate ~/my_other_repos/lighthouse ~/code/lighthouse --dry-run   # preview
python3 ccm.py migrate ~/my_other_repos/lighthouse ~/code/lighthouse             # apply
```

CCM (`~/scratch/ccm/ccm.py`) migrates `~/.claude/projects/<encoded>/` — the
`.jsonl` transcripts, `memory/` dir, session metadata — and rewrites the
`project` field in `~/.claude/history.jsonl` so the session shows up under the
new path in `claude --resume`. It handles the path-encoding (`[^a-z0-9]→-`,
underscore↔hyphen). Do this for **every** MIGRATE repo. `--dry-run` first.

> The original repo paths must match exactly what `~/.claude` recorded. If a repo
> was already moved once, use `ccm inspect <path>` / `ccm list --filter <name>`
> to find where its data currently lives.

## Phase 3 — Seed the PVCs

Per the design (`devpod-design.md`): repos PVC + home/config PVC + cache.

```bash
# repos PVC  <- consolidated ~/code, WITHOUT regenerable bulk (regenerate in-pod)
rsync -aHAX --exclude='node_modules/' --exclude='.venv/' --exclude='__pycache__/' \
  --exclude='dist/' --exclude='build/' --exclude='.cache/' \
  ~/code/  <repos-pvc-mount>/code/

# home/config PVC  <- the migrated Claude data + dotfiles + secrets
rsync -aHAX ~/.claude  ~/.config  ~/.ssh  ~/.secrets  ~/.zshrc  ~/.oh-my-zsh \
  <home-pvc-mount>/
```

Keep gitignored **precious** files (Phase 1) — they're inside the repos and not
matched by the regenerable excludes, so they ride along. Verify a couple by hand.

## Phase 4 — Verify (before decommissioning WSL2)

- [ ] `claude --resume` from `~/code/<repo>` lists that repo's past sessions.
- [ ] `ccm list` shows project data under the new `~/code/*` paths.
- [ ] Memories present: `~/.claude/projects/<new-encoded>/memory/` populated.
- [ ] Spot-check precious gitignored survived (e.g. `.env`, local DBs) in a repo.
- [ ] Git status clean / expected in a few migrated repos (no lost uncommitted work).
- [ ] Toolchain present in-pod (the image), repos build/run.

Only after this passes: retire the WSL2 distro.

## Open decisions

- [ ] Confirm consolidation root = `~/code`.
- [ ] Triage the 81 repos into MIGRATE / ARCHIVE / EXCLUDE.
- [ ] Backup target (TrueNAS dataset? B2? both — there's already a B2 books pattern).
- [ ] Define the "regenerable" exclude list (node_modules, .venv, … — confirm).
