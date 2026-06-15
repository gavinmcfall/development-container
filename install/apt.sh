#!/bin/sh
# Install all apt packages listed in config/apt.yaml (.packages[]).
set -eu
. "$(dirname -- "$0")/lib.sh"
export DEBIAN_FRONTEND=noninteractive

apt-get update
# shellcheck disable=SC2046
yq '.packages[]' "$CFG/apt.yaml" | xargs apt-get install -y --no-install-recommends
rm -rf /var/lib/apt/lists/*

# en_US.UTF-8 locale
sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen
locale-gen
echo "apt.sh: installed $(yq '.packages | length' "$CFG/apt.yaml") packages"
