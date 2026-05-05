#!/usr/bin/env bash
# repo_list.sh
# Print the DAFt repo registry as a TSV-friendly table to stdout.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_repo_list.log'

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
  printf '%-24s %-60s %-30s %-12s %s\n' 'NAME' 'CLONE_URL' 'REF' 'REACH' 'LAST_SEEN_SHA'
}

function print_rows() {
  if ! registry_exists; then
    return 0
  fi
  local name url ref reach sha
  while IFS=$'\t' read -r name url ref; do
    [ -z "${name}" ] && continue
    reach="$(state_field "${name}" 'reachability')"
    sha="$(state_field "${name}" 'last_seen_sha')"
    printf '%-24s %-60s %-30s %-12s %s\n' "${name}" "${url}" "${ref}" "${reach:-unknown}" "${sha:-—}"
  done < <(registry_repos_tsv)
}

main "${@:-}"
