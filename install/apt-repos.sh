#!/bin/sh
# Add third-party apt repos from config/apt-repos.yaml, then install their packages.
set -eu
. "$(dirname -- "$0")/lib.sh"
export DEBIAN_FRONTEND=noninteractive
F="$CFG/apt-repos.yaml"

install -d -m 0755 /etc/apt/keyrings
pkgs=""
n="$(yq '.repos | length' "$F")"
i=0
while [ "$i" -lt "$n" ]; do
  name="$(yq ".repos[$i].name" "$F")"
  key_url="$(yq ".repos[$i].key_url // \"\"" "$F")"
  keyring_url="$(yq ".repos[$i].keyring_url // \"\"" "$F")"
  keyring="$(yq ".repos[$i].keyring" "$F")"
  source="$(yq ".repos[$i].source // \"\"" "$F")"
  source_url="$(yq ".repos[$i].source_url // \"\"" "$F")"
  source_path="$(yq ".repos[$i].source_path // \"\"" "$F")"

  # signing key: armored (dearmor) or already-binary (download)
  if [ -n "$key_url" ]; then
    curl -fsSL "$key_url" | gpg --dearmor -o "$keyring"
  elif [ -n "$keyring_url" ]; then
    curl -fsSL "$keyring_url" -o "$keyring"
  fi

  # source list: literal line (ARCH-substituted) or downloaded .list file
  if [ -n "$source" ]; then
    sub "$source" > "/etc/apt/sources.list.d/$name.list"
  elif [ -n "$source_url" ]; then
    curl -fsSL "$source_url" -o "$source_path"
  fi

  pkgs="$pkgs $(yq ".repos[$i].packages[]" "$F" | tr '\n' ' ')"
  echo "apt-repos.sh: added repo $name"
  i=$((i + 1))
done

apt-get update
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $pkgs
rm -rf /var/lib/apt/lists/*
