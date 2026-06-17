#!/usr/bin/env bash
# devpod doctor — proactive gap-finder for the development-container pod.
#
# Migrating a dev environment off WSL2 left gaps that file-presence diffs can't
# see: lost exec bits, missing deps, tools that work now but vanish on a pod roll.
# This *exercises* the conditional-automation surface (hooks, statusline, cron
# scripts) and audits the fragile spots, so gaps surface HERE — on demand or on a
# schedule — instead of mid-task.
#
# Run:  devpod-doctor        (or: scripts/doctor.sh)
# Exit: 0 = clean · 1 = at least one FAIL (so a CronJob can alert)
#
# Design note: LOCAL hook scripts are fired with a benign event (catches perms,
# syntax, missing deps like uuidgen). EXTERNAL tool hooks (e.g. `mempalace …`,
# `rclone …`) are only *resolved*, never executed — firing them would cause real
# side effects (network syncs) and a minimal-PATH false "not found".

set -uo pipefail

# --notify: on FAIL, POST the failures to $DISCORD_DOCTOR_WEBHOOK (used by the cron).
NOTIFY=0; [ "${1:-}" = "--notify" ] && NOTIFY=1

FAILS=0 WARNS=0 OKS=0 FAILBUF=""
fail(){ echo "  [FAIL] $*"; FAILS=$((FAILS+1)); FAILBUF="$FAILBUF
[FAIL] $*"; }
warn(){ echo "  [WARN] $*"; WARNS=$((WARNS+1)); }
ok(){   echo "  [ ok ] $*"; OKS=$((OKS+1)); }

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
BREAK_RE='permission denied|command not found|: not found|no such file|cannot execute|syntax error|is not recognized'
EVENT='{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/_doctor"},"cwd":"'"$HOME"'"}'

echo "==== devpod doctor — $(date -Iseconds) — $(hostname) ===="

# ── 1. Hooks (fire local scripts, resolve external tools) ────────────────────
echo "[1] hooks"
# Tools that do network/heavy work — resolve them, never run them in a drill.
SKIP_RE='\bmempalace\b|\brclone\b|\bcurl\b|\bwget\b|git[[:space:]]+push'
if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    if printf '%s' "$cmd" | grep -qE "$SKIP_RE"; then
      # side-effecting tool(s): resolve only
      for t in mempalace rclone curl wget; do
        printf '%s' "$cmd" | grep -qE "\b$t\b" || continue
        command -v "$t" >/dev/null 2>&1 && ok "$t (resolves; not run)" || fail "missing command: $t"
      done
    else
      # safe shell snippet or local script: FIRE it with a benign event. Running
      # catches the lot — missing exec bit (Permission denied), syntax errors,
      # and missing deps (e.g. uuidgen) that a static grep can't see.
      err=$(printf '%s' "$EVENT" | timeout 15 bash -c "$cmd" 2>&1 >/dev/null)
      label=$(printf '%s' "$cmd" | awk '{print $1}'); label=$(basename "$label" 2>/dev/null || printf '%s' "$label")
      if printf '%s' "$err" | grep -qiE "$BREAK_RE"; then
        fail "$label → $(printf '%s' "$err" | grep -iE "$BREAK_RE" | head -1)"
      else
        ok "$label"
      fi
    fi
  done < <(jq -r '.hooks // {} | to_entries[] | .value[].hooks[]?.command' "$SETTINGS" 2>/dev/null | sort -u)
else
  warn "no settings.json or jq — skipped hook fire-drill"
fi

# ── 2. statusline ────────────────────────────────────────────────────────────
echo "[2] statusline"
SL=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
if [ -n "$SL" ]; then
  err=$(printf '{"model":{"display_name":"x"},"workspace":{"current_dir":"%s"}}' "$HOME" | timeout 15 bash -c "$SL" 2>&1 >/dev/null)
  printf '%s' "$err" | grep -qiE "$BREAK_RE" && fail "statusline → $(printf '%s' "$err" | head -1)" || ok "statusline runs"
else ok "no statusline configured"; fi

# ── 3. exec bits on the automation surface ───────────────────────────────────
echo "[3] exec bits"
EXECFAIL=0
for d in "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/rules-engine"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -x "$f" ] || { fail "not executable: ${f/#$HOME/\~}"; EXECFAIL=$((EXECFAIL+1)); }
  done < <(find -L "$d" -type f -name '*.sh' 2>/dev/null)
done
if [ -e "$CLAUDE_DIR/statusline.sh" ] && [ ! -x "$CLAUDE_DIR/statusline.sh" ]; then
  fail "not executable: ~/.claude/statusline.sh"; EXECFAIL=$((EXECFAIL+1))
fi
[ "$EXECFAIL" -eq 0 ] && ok "all automation scripts executable"

# ── 4. critical tools present + correct (the ones that have bitten us) ───────
echo "[4] critical tools"
need(){ command -v "$1" >/dev/null 2>&1 && ok "$1 ($(command -v "$1"))" || fail "missing: $1 — $2"; }
need git-crypt "needed to commit the encrypted claude-config repo"
need uuidgen   "needed by the worklog hook (uuid-runtime)"
need mempalace "transcript sync hook + cron"
need chezmoi   "dotfiles"
need op        "1Password secret rendering"
need rclone    "Backblaze B2 backup"
if command -v rclone >/dev/null; then
  rv=$(rclone version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+' | tr -d v)
  awk -v v="$rv" 'BEGIN{split(v,a,"."); if (a[1]<1 || (a[1]==1 && a[2]<74)) exit 1}' \
    && ok "rclone $rv (B2-compatible)" || fail "rclone $rv too old — Backblaze B2 needs >=1.74"
fi

# ── 5. stale references + dangling symlinks (WSL2 residue) ────────────────────
echo "[5] stale refs / dangling links"
dangling=$(find -L "$CLAUDE_DIR" -maxdepth 2 -type l 2>/dev/null | wc -l)
[ "$dangling" -eq 0 ] && ok "no dangling symlinks under ~/.claude" || fail "$dangling dangling symlink(s) under ~/.claude"
mntc=$(grep -rIl '/mnt/c\|wsl.localhost\|/mnt/wsl' "$CLAUDE_DIR/settings.json" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.gitconfig" 2>/dev/null | grep -v '\.bak$')
[ -z "$mntc" ] && ok "no /mnt/c or WSL refs in core config" || warn "WSL path refs remain in: $(echo "$mntc" | tr '\n' ' ')"

# ── summary ──────────────────────────────────────────────────────────────────
echo "==== summary: $OKS ok · $WARNS warn · $FAILS fail ===="

# ── optional Discord alert (only on failure) ─────────────────────────────────
if [ "$NOTIFY" = "1" ] && [ "$FAILS" -gt 0 ] && [ -n "${DISCORD_DOCTOR_WEBHOOK:-}" ] \
   && command -v curl >/dev/null && command -v jq >/dev/null; then
  body=$(printf '%s' "$FAILBUF" | head -c 1500)
  payload=$(jq -Rn --arg c ":rotating_light: **devpod-doctor: $FAILS failure(s)** on $(hostname)
\`\`\`$body
\`\`\`" '{content:$c}')
  curl -fsS -m 15 -X POST -H "Content-Type: application/json" -d "$payload" "$DISCORD_DOCTOR_WEBHOOK" >/dev/null 2>&1 \
    && echo "(posted to Discord)" || echo "(Discord post failed)"
fi

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
