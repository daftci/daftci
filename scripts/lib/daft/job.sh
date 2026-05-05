#!/usr/bin/env bash
# job.sh
# Job-id and job.json helpers for DAFt. Source this file; do not execute directly.

function job_id_for() {
  local -r repo_name="${1}"
  local -r sha="${2}"
  printf '%s-%s\n' "${repo_name}" "${sha:0:7}"
}

function job_short_sha() {
  local -r sha="${1}"
  printf '%s\n' "${sha:0:7}"
}

function write_job_json() {
  local -r path="${1}"
  local -r json="${2}"
  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "${json}" > "${path}.tmp"
  mv -f "${path}.tmp" "${path}"
}

function job_in_queue() {
  local -r job_id="${1}"
  [ -f ".daft/queue/x86_64/${job_id}.json" ]
}

function job_in_active() {
  local -r job_id="${1}"
  find .daft/active -mindepth 2 -maxdepth 3 -type d -name "${job_id}" 2>/dev/null \
    | head -1 | grep -q .
}

function job_in_archive() {
  local -r job_id="${1}"
  find .daft/archive -mindepth 2 -maxdepth 3 -type d -name "${job_id}" 2>/dev/null \
    | head -1 | grep -q .
}

function job_exists_anywhere() {
  local -r job_id="${1}"
  job_in_queue "${job_id}" || job_in_active "${job_id}" || job_in_archive "${job_id}"
}
