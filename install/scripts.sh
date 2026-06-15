#!/bin/sh
# Run each official install script from config/scripts.yaml (.installers[].cmd).
set -eu
. "$(dirname -- "$0")/lib.sh"
F="$CFG/scripts.yaml"

n="$(yq '.installers | length' "$F")"
i=0
while [ "$i" -lt "$n" ]; do
  name="$(yq ".installers[$i].name" "$F")"
  cmd="$(yq ".installers[$i].cmd" "$F")"
  echo ">> scripts.sh: installing $name"
  sh -c "$cmd"
  i=$((i + 1))
done
