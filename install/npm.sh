#!/bin/sh
# Install global npm packages from config/npm.yaml (.packages[]).
# Run as the target user with the nvm-managed node on PATH.
set -eu
. "$(dirname -- "$0")/lib.sh"
# shellcheck disable=SC2046
yq '.packages[]' "$CFG/npm.yaml" | xargs npm install -g
echo "npm.sh: installed globals"
