#!/usr/bin/env bash
# init.sh
# Initialize DAFt MVP-only directories under .daft/ and create VERSION at repo root.
# Idempotent — safe to re-run.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_init.log'
declare -r VERSION_TAG='0.1.337-mvp'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  log '🛠️  Initializing DAFt MVP layout...'
  ensure_dirs
  ensure_keeps
  ensure_version
  log '✅ DAFt init complete'
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -gt 1 ] || [ -n "${1:-}" ]; then
    log '❌ Error: Unexpected argument'
    exit 1
  fi
}

function ensure_dirs() {
  local d
  for d in .daft/repos .daft/repos/state .daft/archive .daft/metrics .daft/workspace .daft/runners .daft/active; do
    mkdir -p "${d}"
  done
}

function ensure_keeps() {
  local d
  for d in .daft/repos .daft/repos/state .daft/archive .daft/metrics; do
    [ -f "${d}/.keep" ] || touch "${d}/.keep"
  done
}

function ensure_version() {
  if [ ! -f VERSION ]; then
    printf '%s\n' "${VERSION_TAG}" > VERSION
    log '  ✅ Created VERSION'
  fi
}

main "${@:-}"
