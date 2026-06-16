#!/usr/bin/env bash
# add-secret NAME [VALUE] — store a secret in 1Password (Dev Container vault) and
# wire it into ~/.secrets via the chezmoi template (op:// ref → render → push).
#
#   add-secret STRIPE_KEY sk_live_xxx     # value as arg
#   add-secret STRIPE_KEY                 # prompts (hidden) for the value
#
# Activates after the ~/.secrets cutover (when dot_secrets.tmpl is chezmoi-managed).
set -euo pipefail
VAULT="Dev Container"
NAME="${1:?usage: add-secret NAME [VALUE]}"

SRC="$(chezmoi source-path ~/.secrets 2>/dev/null || true)"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "✗ ~/.secrets isn't a chezmoi template yet (cutover pending)"; exit 1; }

VALUE="${2:-}"
if [ -z "$VALUE" ]; then read -rsp "value for $NAME: " VALUE; echo; fi
[ -n "$VALUE" ] || { echo "✗ empty value"; exit 1; }

# 1) store/update in 1Password
if op item get "$NAME" --vault "$VAULT" >/dev/null 2>&1; then
  op item edit "$NAME" --vault "$VAULT" "password=$VALUE" >/dev/null && echo "↻ updated $NAME in 1Password"
else
  op item create --category=password --title "$NAME" --vault "$VAULT" "password=$VALUE" >/dev/null && echo "＋ created $NAME in 1Password"
fi

# 2) add the op:// pointer to the template (idempotent)
if ! grep -qF "op://$VAULT/$NAME/password" "$SRC"; then
  printf "export %s='{{ onepasswordRead \"op://%s/%s/password\" }}'\n" "$NAME" "$VAULT" "$NAME" >> "$SRC"
  echo "＋ added pointer to dot_secrets.tmpl"
fi

# 3) render ~/.secrets + commit/push the template (op:// only)
chezmoi apply ~/.secrets
( cd "$(chezmoi source-path)" && git add -A && git commit -q -m "secrets: add $NAME" && git push -q ) 2>/dev/null \
  && echo "↑ template pushed" || echo "(nothing to push / push skipped)"
echo "✓ done — run:  source ~/.secrets"
