#!/usr/bin/env bash
# release.sh
# Push artifacts to MinIO, write final status, git mv active/<id>/<job-id>/ to
# archive/<date>/<job-id>/, copy workspace log into archive, cleanup checkout dir,
# record metrics, commit + push.
# Args: JOB_ID

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_release.log'
declare -r SERVICE='daft-runner'

# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh
# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/clone.sh
. scripts/lib/daft/clone.sh
# shellcheck source=scripts/lib/daft/artifacts.sh
. scripts/lib/daft/artifacts.sh
# shellcheck source=scripts/lib/daft/metrics.sh
. scripts/lib/daft/metrics.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh
# shellcheck source=scripts/lib/daft/logger.sh
. scripts/lib/daft/logger.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r job_id="${1}"
  do_release "${job_id}"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 1 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: release.sh JOB_ID'
    exit 1
  fi
}

function do_release() {
  local -r job_id="${1}"
  local id job_dir today
  id="$(read_runner_id)" || { log '❌ no runner id'; exit 1; }
  job_dir=".daft/active/${id}/${job_id}"
  today="$(date -u '+%Y-%m-%d')"
  if [ ! -d "${job_dir}" ]; then
    log "❌ no active job dir for ${job_id}"
    exit 1
  fi
  release_steps "${id}" "${job_id}" "${job_dir}" "${today}"
}

function release_steps() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r job_dir="${3}"
  local -r today="${4}"
  push_artifacts_for "${job_id}" "${job_dir}"
  finalize_status_with_duration "${job_dir}"
  archive_job "${id}" "${job_id}" "${job_dir}" "${today}"
  cleanup_workspace "${job_id}"
  emit_release_metrics
  emit_release_log "${id}" "${job_id}" "${today}"
  commit_local_or_push "release: ${job_id} by ${id}" 3
}

function push_artifacts_for() {
  local -r job_id="${1}"
  local -r job_dir="${2}"
  local -r artifacts_dir=".daft/workspace/${job_id}.checkout/artifacts"
  local result
  result="$(artifacts_push "${job_id}" "${artifacts_dir}")"
  mkdir -p .daft/registry/artifacts
  printf '%s\n' "${result}" > ".daft/registry/artifacts/${job_id}.json"
}

function finalize_status_with_duration() {
  local -r job_dir="${1}"
  local started phase exit_code now duration
  started="$(yq -r '.started_at // ""' "${job_dir}/status.json")"
  phase="$(yq -r '.phase // "released"' "${job_dir}/status.json")"
  exit_code="$(yq -r '.exit_code // 0' "${job_dir}/status.json")"
  now="$(utc_rfc3339_ns)"
  duration="$(compute_duration_ms "${started}")"
  printf '{"phase":"%s","exit_code":%s,"started_at":"%s","finished_at":"%s","duration_ms":%s}\n' \
    "${phase}" "${exit_code}" "${started}" "${now}" "${duration}" > "${job_dir}/status.json"
}

function compute_duration_ms() {
  local -r started="${1}"
  if [ -z "${started}" ]; then printf '0'; return 0; fi
  printf '0'
}

function archive_job() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r job_dir="${3}"
  local -r today="${4}"
  local -r archive_dir=".daft/archive/${today}/${job_id}"
  mkdir -p ".daft/archive/${today}"
  mv "${job_dir}" "${archive_dir}"
  if [ -f ".daft/workspace/${job_id}.log" ]; then
    cp ".daft/workspace/${job_id}.log" "${archive_dir}/job.log"
  fi
  printf '%s\n' "${id}" > "${archive_dir}/runner-id.txt"
}

function cleanup_workspace() {
  local -r job_id="${1}"
  clone_cleanup ".daft/workspace/${job_id}.checkout"
}

function emit_release_metrics() {
  metric_inc 'runner_jobs_executed_total'
}

function emit_release_log() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r today="${3}"
  local -r status_file=".daft/archive/${today}/${job_id}/status.json"
  local exit_code phase level
  exit_code="$(yq -r '.exit_code // 0' "${status_file}" 2>/dev/null || printf '0')"
  phase="$(yq -r '.phase // "released"' "${status_file}" 2>/dev/null || printf 'released')"
  level="$(level_for_exit "${exit_code}")"
  if [ "${exit_code}" != '0' ]; then metric_inc 'runner_jobs_failed_total'; fi
  log "  📦 released ${job_id} (exit=${exit_code})"
  log_json "${SERVICE}" "${level}" 'job released' \
    "$(printf '"runner_id":"%s","job_id":"%s","exit_code":%s,"phase":"%s"' "${id}" "${job_id}" "${exit_code}" "${phase}")"
}

function level_for_exit() {
  if [ "${1}" = '0' ]; then printf 'info'; return 0; fi
  printf 'warn'
}

main "${@:-}"
