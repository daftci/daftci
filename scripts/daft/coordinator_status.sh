#!/usr/bin/env bash
# coordinator_status.sh
# Print last_check_at, reachability, and last_transition_at for every registered repo.
# Sorted by staleness (most-stale first).

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_coordinator_status.log'

# shellcheck source=scripts/lib/daft/repos_yaml.sh
. scripts/lib/daft/repos_yaml.sh
# shellcheck source=scripts/lib/daft/state.sh
. scripts/lib/daft/state.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  print_header
  print_rows
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

function print_header() {
  printf '%-24s %-12s %-32s %-32s\n' 'NAME' 'REACH' 'LAST_CHECK_AT' 'LAST_TRANSITION_AT'
}

function print_rows() {
  if ! registry_exists; then
    return 0
  fi
  local name _url _ref reach checked transition
  while IFS=$'\t' read -r name _url _ref; do
    [ -z "${name}" ] && continue
    reach="$(state_field "${name}" 'reachability')"
    checked="$(state_field "${name}" 'last_check_at')"
    transition="$(state_field "${name}" 'last_transition_at')"
    printf '%-24s %-12s %-32s %-32s\n' "${name}" "${reach:-unknown}" "${checked:-—}" "${transition:-—}"
  done < <(registry_repos_tsv)
}

main "${@:-}"
