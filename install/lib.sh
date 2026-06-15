#!/bin/sh
# Shared helpers for install/*.sh. Sourced, not executed.
# Requires: yq (mikefarah) on PATH, bootstrapped before any of these run.
set -eu

ARCH="$(dpkg --print-architecture)"
# config dir resolved relative to the install/ scripts (../config)
CFG="${CFG:-$(unset CDPATH; cd -- "$(dirname -- "$0")/../config" && pwd)}"

# substitute {ARCH} (and any extra k=v pairs passed as args: sub "$str" KVER="$v")
sub() {
  _s="$1"; shift || true
  _s="$(printf '%s' "$_s" | sed -e "s|{ARCH}|$ARCH|g")"
  for _kv in "$@"; do
    _k="${_kv%%=*}"; _v="${_kv#*=}"
    _s="$(printf '%s' "$_s" | sed -e "s|{$_k}|$_v|g")"
  done
  printf '%s' "$_s"
}
