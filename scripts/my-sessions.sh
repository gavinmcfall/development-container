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

open devcontainer  /home/gavin/code/scratch                                 "Dev Container"
open lighthouse    /home/gavin/code/Projects/lighthouse                      "lighthouse-main"
open nerdz-reading /home/gavin/code/Projects/nerdz-reading                   "Nerdz Reading"
open mempalace     /home/gavin/code/Projects/mempalace                       "Mempalace"
open spyglass      /home/gavin/code/Projects/spyglass                        "Spyglass"
open manga-stack   /home/gavin/code/home-ops                                 "Manga Stack"
open otel-life     /home/gavin/code/home-ops/.claude/worktrees/otel-life     "Otel Life"
open realmstack    /home/gavin/code/Realmstack/Realmstack                    "Realmstack"

tmux select-window -t :1 2>/dev/null || true
echo "done — switch windows with the top bar (click), Ctrl+b <number>, or Ctrl+b w"
