#!/usr/bin/env bash
# time.sh
# Time helpers for DAFt. Source this file; do not execute directly.

function utc_rfc3339_ns() {
  if command -v gdate >/dev/null 2>&1; then
    gdate -u '+%Y-%m-%dT%H:%M:%S.%NZ'
    return 0
  fi
  if date -u '+%N' 2>/dev/null | grep -q '^[0-9]\{1,\}$'; then
    date -u '+%Y-%m-%dT%H:%M:%S.%NZ'
    return 0
  fi
  date -u '+%Y-%m-%dT%H:%M:%S.000000000Z'
}

function epoch_seconds() {
  date -u '+%s'
}

function seconds_since() {
  local -r since="${1}"
  local now
  now="$(epoch_seconds)"
  printf '%s\n' "$(( now - since ))"
}
