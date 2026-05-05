#!/usr/bin/env bash
# runner_init.sh
# Generate a runner identity, write .daft/runners/<id>/identity.json, and
# pin the host-local pointer .daft/.current_runner_id (gitignored).

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_init.log'

# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  init_runner
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

function write_identity() {
  local -r id="${1}"
  local -r host="${2}"
  local -r created="${3}"
  mkdir -p ".daft/runners/${id}"
  printf '{"id":"%s","hostname":"%s","isa":"x86_64","created_at":"%s"}\n' \
    "${id}" "${host}" "${created}" > ".daft/runners/${id}/identity.json"
}

function pin_local() {
  local -r id="${1}"
  printf '%s\n' "${id}" > .daft/.current_runner_id
}

function init_runner() {
  local id host created
  id="$(generate_runner_id)"
  host="$(hostname -s 2>/dev/null || hostname)"
  created="$(utc_rfc3339_ns)"
  log "🪪 Initializing runner: ${id}"
  write_identity "${id}" "${host}" "${created}"
  pin_local "${id}"
  commit_local_or_push "runner_init: ${id}" 3
  log "✅ Runner ${id} ready (pinned in .daft/.current_runner_id)"
  printf '%s\n' "${id}"
}

main "${@:-}"
