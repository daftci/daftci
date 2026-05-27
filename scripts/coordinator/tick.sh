#!/usr/bin/env bash
# tick.sh
# One coordinator iteration: pull_rebase, fan-out check_repo across all registered
# repos with parallelism, apply edge-triggered state transitions, enqueue new jobs,
# then commit + push (or commit-only if no remote).

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_coordinator_tick.log'
declare -rx COORDINATOR_PARALLELISM="${COORDINATOR_PARALLELISM:-8}"
declare -r SERVICE='daft-coordinator'

# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/repos_yaml.sh
. scripts/lib/daft/repos_yaml.sh
# shellcheck source=scripts/lib/daft/state.sh
. scripts/lib/daft/state.sh
# shellcheck source=scripts/lib/daft/job.sh
. scripts/lib/daft/job.sh
# shellcheck source=scripts/lib/daft/metrics.sh
. scripts/lib/daft/metrics.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh
# shellcheck source=scripts/lib/daft/logger.sh
. scripts/lib/daft/logger.sh
# shellcheck source=scripts/lib/daft/reload.sh
. scripts/lib/daft/reload.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  run_tick
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

function run_tick() {
  log '🔄 coordinator tick start'
  metric_inc 'coordinator_ticks_total'
  if has_origin_remote; then
    pull_rebase >/dev/null 2>&1 || log '⚠️  pull_rebase warning'
  fi
  maybe_handle_reload
  if ! registry_exists; then
    log '   (no registry yet; nothing to poll)'
    return 0
  fi
  process_results
  commit_local_or_push 'coordinator: tick' 3 || log '⚠️  push failed; will retry next tick'
  log '✅ coordinator tick end'
}

function maybe_handle_reload() {
  if ! reload_changed_for 'coordinator'; then return 0; fi
  local cur
  cur="$(reload_current_tick)"
  log "🔔 reload signal seen (tick=${cur}); dropping caches"
  reload_caches
  reload_write_last_seen 'coordinator' "${cur}"
}

function reload_caches() {
  :
}

function fan_out_checks() {
  registry_repos_tsv | awk -F'\t' '{print $1}' \
    | xargs -n 1 -P "${COORDINATOR_PARALLELISM}" \
        bash scripts/coordinator/check_repo.sh
}

function process_results() {
  fan_out_checks | while IFS= read -r line; do
    [ -z "${line}" ] && continue
    process_one "${line}"
    metric_inc 'coordinator_repos_polled_total'
  done
}

function process_one() {
  local -r line="${1}"
  local name ok sha err
  name="$(printf '%s' "${line}" | yq -r '.name')"
  ok="$(printf '%s' "${line}" | yq -r '.ok')"
  sha="$(printf '%s' "${line}" | yq -r '.sha // ""')"
  err="$(printf '%s' "${line}" | yq -r '.error // ""')"
  apply_repo_result "${name}" "${ok}" "${sha}" "${err}"
}

function apply_repo_result() {
  local -r name="${1}"
  local -r ok="${2}"
  local -r sha="${3}"
  local -r err="${4}"
  local new_reach prior
  new_reach="$(compute_reachability "${ok}" "${sha}")"
  prior="$(state_field "${name}" 'reachability')"
  emit_and_persist "${name}" "${prior:-unknown}" "${new_reach}" "${sha}" "${err}"
}

function compute_reachability() {
  local -r ok="${1}"
  local -r sha="${2}"
  if [ "${ok}" != 'true' ]; then printf 'unreachable'; return 0; fi
  if [ -z "${sha}" ]; then printf 'missing'; return 0; fi
  printf 'reachable'
}

function emit_and_persist() {
  local -r name="${1}"
  local -r prior="${2}"
  local -r new="${3}"
  local -r sha="${4}"
  local -r err="${5}"
  local prev_sha
  prev_sha="$(state_field "${name}" 'last_seen_sha')"
  log_if_edge "${name}" "${prior}" "${new}" "${err}"
  write_repo_state "${name}" "${new}" "${sha}" "${err}" "${prior}"
  conditional_enqueue "${name}" "${new}" "${sha}" "${prev_sha}"
}

function log_if_edge() {
  local -r name="${1}"
  local -r prior="${2}"
  local -r new="${3}"
  local -r err="${4}"
  if [ "${prior}" = "${new}" ]; then return 0; fi
  log_json "${SERVICE}" "$(edge_level "${new}")" "$(edge_message "${new}")" \
    "$(edge_extra_json "${name}" "${prior}" "${new}" "${err}")"
}

function edge_level() {
  case "${1}" in
    reachable) printf 'info' ;;
    *)         printf 'warn' ;;
  esac
}

function edge_message() {
  case "${1}" in
    reachable)   printf 'repo recovered' ;;
    unreachable) printf 'repo unreachable' ;;
    missing)     printf 'repo ref missing' ;;
    *)           printf 'repo state' ;;
  esac
}

function edge_extra_json() {
  local -r name="${1}"
  local -r prior="${2}"
  local -r new="${3}"
  local -r err="${4}"
  printf '"new_reachability":"%s","prior_reachability":"%s","repo_name":"%s","error":"%s"' \
    "${new}" "${prior}" "${name}" "${err//\"/\\\"}"
}

function write_repo_state() {
  local -r name="${1}"
  local -r new="${2}"
  local -r sha="${3}"
  local -r err="${4}"
  local -r prior="${5}"
  write_state_atomic "${name}" "$(build_state_json "${name}" "${new}" "${sha}" "${err}" "${prior}")"
}

function build_state_json() {
  local -r name="${1}"
  local -r new="${2}"
  local -r sha="${3}"
  local -r err="${4}"
  local -r prior="${5}"
  local now last_seen last_transition
  now="$(utc_rfc3339_ns)"
  last_seen="$(pick_last_seen "${new}" "${sha}" "${name}")"
  last_transition="$(pick_last_transition "${prior}" "${new}" "${now}" "${name}")"
  render_state_json "${name}" "${new}" "${last_seen}" "${now}" "${last_transition}" "${err}"
}

function pick_last_seen() {
  local -r new="${1}"
  local -r sha="${2}"
  local -r name="${3}"
  if [ "${new}" = 'reachable' ] && [ -n "${sha}" ]; then
    printf '%s' "${sha}"
    return 0
  fi
  state_field "${name}" 'last_seen_sha'
}

function pick_last_transition() {
  local -r prior="${1}"
  local -r new="${2}"
  local -r now="${3}"
  local -r name="${4}"
  if [ "${prior}" != "${new}" ]; then
    printf '%s' "${now}"
    return 0
  fi
  state_field "${name}" 'last_transition_at'
}

function render_state_json() {
  local -r name="${1}"
  local -r reach="${2}"
  local -r sha="${3}"
  local -r checked="${4}"
  local -r transitioned="${5}"
  local -r err="${6}"
  printf '{"name":"%s","reachability":"%s","last_seen_sha":"%s","last_check_at":"%s","last_transition_at":"%s","last_error":"%s"}\n' \
    "${name}" "${reach}" "${sha}" "${checked}" "${transitioned}" "${err//\"/\\\"}"
}

function conditional_enqueue() {
  local -r name="${1}"
  local -r new="${2}"
  local -r sha="${3}"
  local -r prev_sha="${4}"
  if [ "${new}" = 'reachable' ] && [ -n "${sha}" ] && [ "${sha}" != "${prev_sha}" ]; then
    enqueue_job "${name}" "${sha}"
  fi
}

function enqueue_job() {
  local -r name="${1}"
  local -r sha="${2}"
  local jid
  jid="$(job_id_for "${name}" "${sha}")"
  if job_exists_anywhere "${jid}"; then return 0; fi
  do_enqueue "${name}" "${sha}" "${jid}"
}

function do_enqueue() {
  local -r name="${1}"
  local -r sha="${2}"
  local -r jid="${3}"
  local -r path=".daft/queue/x86_64/${jid}.json"
  mkdir -p .daft/queue/x86_64
  build_job_json "${name}" "${sha}" "${jid}" > "${path}.tmp"
  mv -f "${path}.tmp" "${path}"
  log "  ➕ enqueued ${jid}"
  log_json "${SERVICE}" 'info' 'job enqueued' \
    "$(printf '"job_id":"%s","repo_name":"%s","sha":"%s"' "${jid}" "${name}" "${sha}")"
}

function build_job_json() {
  local -r name="${1}"
  local -r sha="${2}"
  local -r jid="${3}"
  local clone_url ref now
  clone_url="$(registry_repo_field "${name}" 'clone_url')"
  ref="$(registry_repo_field "${name}" 'ref')"
  now="$(utc_rfc3339_ns)"
  printf '{"job_id":"%s","repo_name":"%s","clone_url":"%s","ref":"%s","sha":"%s","isa":"x86_64","enqueued_at":"%s","job_script_path":".daft/jobs/build"}\n' \
    "${jid}" "${name}" "${clone_url}" "${ref}" "${sha}" "${now}"
}

main "${@:-}"
