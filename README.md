# development-container

The image + build pipeline for Gavin's persistent Kubernetes dev environment
("**development**") — the WSL2 replacement. One pod in the home-ops cluster runs
all Claude Code sessions; reachable from anywhere via Tailscale SSH.

## What's here

| Path | Purpose |
|------|---------|
| `Dockerfile` | Ubuntu 24.04 image, thin driver over `config/` |
| `config/` | One YAML per install type (`apt`, `apt-repos`, `binaries`, `scripts`, `npm`, `languages`) — **edit + rebuild to add/remove a tool** |
| `install/` | yq-driven POSIX drivers the Dockerfile runs to consume `config/*.yaml` |
| `inventory/` | Toolchain audit (`tool-usage-report.md`) — the evidence behind the package choices |
| `devpod-design.md` | Build design: OS, PVC model, user, tmux, Tailscale/SSH, VSCode, secrets, sizing |
| `migration-runbook.md` | WSL2 → cluster cutover prep |
| `repo-move-map.txt` | Record of the `~/code` repo consolidation |

## Add or remove a tool

Edit the relevant `config/*.yaml` and rebuild — no Dockerfile surgery:
- apt package → `config/apt.yaml`
- third-party apt repo → `config/apt-repos.yaml`
- release-binary tool → `config/binaries.yaml`
- install-script tool → `config/scripts.yaml`
- global npm → `config/npm.yaml`
- language version → `config/languages.yaml`

Package choices are evidence-driven (atuin + Claude-transcript usage) — see
`inventory/tool-usage-report.md`. Excluded from base (re-add in `apt.yaml` if
needed): PHP stack, dotnet, python3.11, redis-tools.

## Build

CI (`.github/workflows/build.yaml`) builds and pushes
`ghcr.io/gavinmcfall/development-container:latest` + a `:sha-<short>` tag. Local smoke test:

```bash
docker build -t development-container:test .
docker run --rm -it development-container:test zsh
```

## Sizing (measured, 3.6 days of profiling)

Per-session ~1.6 GB PSS; peak workload ~21 GB. Pod: **request 16 GB / limit
24–28 GB**. repoql is ~60% of memory.

## Deploy

Kubernetes manifests (HelmRelease, PVCs, Tailscale exposure) live in **home-ops**
under `kubernetes/apps/home/development-container/` — GitOps, not here. This repo is the image
source only.
