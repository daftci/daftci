#!/usr/bin/env bash
# runner_id.sh
# Runner identity helpers for DAFt. Source this file; do not execute directly.

function read_runner_id() {
  if [ -n "${DAFT_RUNNER_ID:-}" ]; then
    printf '%s\n' "${DAFT_RUNNER_ID}"
    return 0
  fi
  if [ -f ".daft/.current_runner_id" ]; then
    cat .daft/.current_runner_id
    return 0
  fi
  return 1
}

function validate_runner_id() {
  local -r id="${1:-}"
  if [ -z "${id}" ]; then
    return 1
  fi
  if ! printf '%s' "${id}" | grep -Eq '^[a-z0-9-]+$'; then
    return 1
  fi
  return 0
}

function generate_runner_id() {
  local host suffix
  host="$(hostname -s 2>/dev/null || hostname)"
  suffix="$(generate_runner_id_suffix)"
  printf '%s-%s\n' "${host}" "${suffix}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-\n' '-'
}

function generate_runner_id_suffix() {
  if [ -r /dev/urandom ]; then
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 8
    return 0
  fi
  printf '%08x' "${RANDOM}${RANDOM}"
}
