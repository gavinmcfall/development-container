#!/usr/bin/env bash
# Open my standing workspace: each named Claude chat in its own tmux window,
# resumed at its current ~/code path. Run INSIDE tmux (ssh in -> tmux new -A -s main).
# Edit the list below as your active set changes.
set -euo pipefail

# `my-sessions edit` -> open this script (the session list) in your editor
[ "${1:-}" = "edit" ] && exec "${EDITOR:-nano}" "$(readlink -f "$0")"

[ -n "${TMUX:-}" ] || { echo "Run inside tmux first:  tmux new -A -s main"; exit 1; }

# the session we're currently in (so we don't reopen it as a duplicate)
CUR="${CLAUDE_SESSION_ID:-}"

open(){  # name  cwd  session-name
  if [ -d "$2" ]; then
    tmux new-window -n "$1" -c "$2" "claude --resume \"$3\" || claude --resume; exec zsh"
    echo "opened  $1  ($3)"
  else
    echo "skip    $1  (missing $2)"
  fi
}

# Snapshot of the windows open on 2026-06-18 (resume by session UUID — the jsonl
# survives pod rolls on the PVC, so this reopens the exact conversations).
open home-ops     /home/gavin/code/scratch                     "daac4f81-49aa-4e53-be7a-bedff62c9a61"
open bootible     /home/gavin/code/Projects/handheld-gaming    "dfef9ac9-4bb9-405f-a726-8fe78ac3c3a8"
open sc-bridge    "/home/gavin/code/SC Bridge"                 "150b6ba5-7ecf-4bb2-b9e1-d14fe48b53f3"
open manga-stack  /home/gavin/code/home-ops                    "5b987018-24dd-4b8b-8a81-cc5bfac1e338"
open nerdz        /home/gavin/code/nerdz                       "4744a6b3-541a-46fc-8f20-8073f3080965"
open sc-bridge-2  "/home/gavin/code/SC Bridge"                 "1a9dd937-9b7e-421a-9400-73554423d70c"

tmux select-window -t :1 2>/dev/null || true
echo "done — switch windows with the top bar (click), Ctrl+b <number>, or Ctrl+b w"
