#!/usr/bin/env bash
# status.sh
# List jobs in queue/, active/<*>/, and archive/<today>/ with phase and age. Read-only.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_status.log'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  print_section_queue
  print_section_active
  print_section_archive_today
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

function print_section_queue() {
  printf '\n=== queue (x86_64) ===\n'
  if [ ! -d .daft/queue/x86_64 ]; then
    printf '(no queue dir)\n'
    return 0
  fi
  find .daft/queue/x86_64 -type f -name '*.json' -maxdepth 1 -print 2>/dev/null \
    | sort \
    || printf '(empty)\n'
}

function print_section_active() {
  printf '\n=== active ===\n'
  if [ ! -d .daft/active ]; then
    printf '(no active dir)\n'
    return 0
  fi
  find .daft/active -mindepth 2 -maxdepth 3 -type d -print 2>/dev/null \
    | sort \
    || printf '(empty)\n'
}

function print_section_archive_today() {
  local today
  today="$(date -u '+%Y-%m-%d')"
  printf '\n=== archive/%s ===\n' "${today}"
  if [ ! -d ".daft/archive/${today}" ]; then
    printf '(no archive dir for today)\n'
    return 0
  fi
  find ".daft/archive/${today}" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
    | sort \
    || printf '(empty)\n'
}

main "${@:-}"
