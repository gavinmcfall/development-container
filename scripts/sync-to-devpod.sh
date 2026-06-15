#!/usr/bin/env bash
# Sync latest local state -> the 'development' dev pod.
#
# Pushes ~/.claude (all conversation transcripts + memory) and ~/code (repos)
# from THIS machine into the running pod, so a `claude --resume` over there
# picks up the very latest state.
#
# - Transport is rsync-over-`kubectl exec` (LAN-fast to the API server), NOT
#   Tailscale SSH — so it is unaffected by the DERP relay latency.
# - Incremental + safe to re-run. Uses --update (never clobbers a file that is
#   NEWER on the pod) and never deletes on the pod.
#
# Usage:
#   ./sync-to-devpod.sh              # sync conversations + memory + repos
#   ./sync-to-devpod.sh --claude     # sync conversations + memory ONLY (faster)
#   ./sync-to-devpod.sh --code       # sync repos ONLY
set -euo pipefail

# Pin to the cluster's kubeconfig (ignore a possibly-stale KUBECONFIG in the env).
KUBECONFIG="$HOME/code/home-ops/kubeconfig"; export KUBECONFIG
NS=home
SELECTOR='app.kubernetes.io/name=development-container'
EXC="$HOME/code/Tools/development-container/config/seed-excludes.txt"

DO_CLAUDE=1; DO_CODE=1
case "${1:-}" in
  --claude) DO_CODE=0 ;;
  --code)   DO_CLAUDE=0 ;;
  "" )      ;;
  * ) echo "usage: $0 [--claude|--code]"; exit 2 ;;
esac

grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
red(){ printf '\033[31m%s\033[0m\n' "$*"; }
cyn(){ printf '\033[36m%s\033[0m\n' "$*"; }

# 1. Find the running pod
cyn "→ locating dev pod ..."
POD=$(kubectl -n "$NS" get pod -l "$SELECTOR" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[ -n "${POD:-}" ] || { red "✗ no Running dev pod found. Check: kubectl -n $NS get pods -l $SELECTOR"; exit 1; }
kubectl -n "$NS" exec "$POD" -- id gavin >/dev/null 2>&1 || { red "✗ cannot exec into $POD"; exit 1; }
grn "✓ pod: $POD"

# 2. rsh wrapper — runs the remote rsync inside the pod as gavin (uid 1000)
RSH=$(mktemp /tmp/krsh.XXXXXX.sh)
trap 'rm -f "$RSH"' EXIT
cat > "$RSH" <<EOF
#!/bin/sh
shift   # drop the dummy hostname rsync passes as \$1
exec kubectl --kubeconfig="$KUBECONFIG" exec -i -n $NS $POD -- runuser -u gavin -- "\$@"
EOF
chmod +x "$RSH"

sync_one(){ # $1=label  $2=src  $3=dst  [extra rsync args...]
  local label="$1" src="$2" dst="$3"; shift 3
  cyn "→ syncing $label ..."
  local out rc
  # --omit-dir-times: the PVC mount-point dirs are root-owned, so trying to set
  # their mtime always errors (harmless) and would otherwise force exit 23.
  out=$(rsync -aHAX --update --omit-dir-times --blocking-io --info=stats2 "$@" \
          --rsh="$RSH" "$src" "kpod:$dst" 2>&1) && rc=0 || rc=$?
  printf '%s\n' "$out" | grep -iE 'Number of (regular )?files transferred|Total transferred file size|sent [0-9]' || true
  # rc 23/24 = partial (unreadable/vanished files) — report but don't abort
  if [ "$rc" = 0 ]; then grn "✓ $label up to date"
  elif [ "$rc" = 23 ] || [ "$rc" = 24 ]; then grn "✓ $label synced (some files skipped — see below)"; \
       printf '%s\n' "$out" | grep -iE 'failed|denied|vanished' | head -5
  else red "✗ $label sync failed (rsync exit $rc)"; printf '%s\n' "$out" | tail -5; fi
}

[ "$DO_CLAUDE" = 1 ] && sync_one ".claude (conversations + memory)" "$HOME/.claude/" "/home/gavin/.claude/"
[ "$DO_CODE"   = 1 ] && sync_one "~/code (repos)"                     "$HOME/code/"    "/home/gavin/code/" --exclude-from="$EXC"

echo
grn "ALL DONE."
echo "Resume on the pod:"
echo "  ssh gavin@development → tmux new -A -s main → cd ~/code/<repo> && claude --resume"
