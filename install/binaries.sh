#!/bin/sh
# Download standalone binaries from config/binaries.yaml into /usr/local/bin.
set -eu
. "$(dirname -- "$0")/lib.sh"
F="$CFG/binaries.yaml"
KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"

n="$(yq '.tools | length' "$F")"
i=0
while [ "$i" -lt "$n" ]; do
  name="$(yq ".tools[$i].name" "$F")"
  kind="$(yq ".tools[$i].kind // \"raw\"" "$F")"
  url="$(sub "$(yq ".tools[$i].url" "$F")" "KVER=$KVER")"

  if [ "$kind" = "raw" ]; then
    curl -fsSL "$url" -o "/usr/local/bin/$name"
    chmod +x "/usr/local/bin/$name"
  else
    tmp="$(mktemp -d)"
    curl -fsSL "$url" | tar -xz -C "$tmp"
    yq ".tools[$i].extract[]" "$F" | while read -r p; do
      install -m 0755 "$tmp/$p" "/usr/local/bin/$(basename "$p")"
    done
    rm -rf "$tmp"
  fi
  echo "binaries.sh: installed $name"
  i=$((i + 1))
done
