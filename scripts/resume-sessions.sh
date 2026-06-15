#!/usr/bin/env bash
# Open each Claude session id in its own tmux window, resumed in its own repo.
# Run INSIDE tmux (ssh into the pod, then: tmux new -A -s main).
#
# Usage:
#   resume-sessions.sh <id> [<id> ...]     # open the given sessions
#   resume-sessions.sh --list              # just list recent sessions + ids
set -euo pipefail
proj="$HOME/.claude/projects"

if [ "${1:-}" = "--list" ]; then
  python3 - <<'PY'
import os, json, glob, datetime
base=os.path.expanduser('~/.claude/projects')
items=sorted(((os.path.getmtime(f), f) for f in glob.glob(base+'/*/*.jsonl')), reverse=True)
for mt,f in items[:15]:
    cwd=msg=None
    try:
        for line in open(f, errors='ignore'):
            try: o=json.loads(line)
            except: continue
            if not isinstance(o,dict): continue
            if cwd is None and o.get('cwd'): cwd=o['cwd']
            if msg is None and o.get('type')=='user':
                c=(o.get('message') or {}).get('content')
                msg=c if isinstance(c,str) else next((p.get('text') for p in c if isinstance(p,dict) and p.get('type')=='text'),None) if isinstance(c,list) else None
            if cwd and msg: break
    except: pass
    ts=datetime.datetime.fromtimestamp(mt).strftime('%m-%d %H:%M')
    print(f"{ts}  {os.path.basename(f)[:-6]}  {cwd or '?'}  | {(msg or '').strip()[:50]}")
PY
  exit 0
fi

[ -n "${TMUX:-}" ] || { echo "Run this INSIDE tmux first:  tmux new -A -s main"; exit 1; }
[ "$#" -gt 0 ] || { echo "usage: $0 <session-id> [<id> ...]   (or --list)"; exit 1; }

cur="${CLAUDE_SESSION_ID:-}"
for id in "$@"; do
  f=$(find "$proj" -name "$id.jsonl" -print -quit 2>/dev/null || true)
  [ -n "$f" ] || { echo "skip $id (not found)"; continue; }
  [ "$id" = "$cur" ] && { echo "skip $id (this session)"; continue; }
  cwd=$(grep -m1 -o '"cwd":"[^"]*"' "$f" | sed 's/"cwd":"//;s/"$//')
  [ -d "${cwd:-}" ] || cwd="$HOME"
  tmux new-window -n "$(basename "$cwd")" -c "$cwd" "claude --resume $id; exec zsh"
  echo "opened '$(basename "$cwd")'  ->  resume $id"
done
