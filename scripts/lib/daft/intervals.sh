#!/usr/bin/env bash
# intervals.sh
# Helpers for the orchestrator / runner tick-interval knobs. Source this file;
# do not execute directly.
#
# Persistence: .daft/workspace/intervals.env (host-local, gitignored). Each
# line is KEY=SECONDS. Lines that do not match `^[A-Z_]+=[0-9]+$` are ignored,
# so hand-edits cannot accidentally execute code via `source`.
#
# Precedence (highest wins): pre-existing env var > intervals.env file > built-in default.

declare -r INTERVALS_FILE='.daft/workspace/intervals.env'

declare -r DEFAULT_COORDINATOR_INTERVAL_SECONDS=60
declare -r DEFAULT_REAPER_INTERVAL_SECONDS=30
declare -r DEFAULT_RUNNER_INTERVAL_SECONDS=5

function intervals_load() {
  intervals_parse_file
  intervals_apply_defaults
  intervals_export
}

function intervals_parse_file() {
  if [ ! -f "${INTERVALS_FILE}" ]; then return 0; fi
  local key val
  while IFS='=' read -r key val; do
    intervals_apply_pair "${key}" "${val}"
  done < <(grep -E '^[A-Z_]+=[0-9]+$' "${INTERVALS_FILE}" || true)
}

function intervals_apply_pair() {
  local -r key="${1}"
  local -r val="${2}"
  case "${key}" in
    COORDINATOR_INTERVAL_SECONDS) COORDINATOR_INTERVAL_SECONDS="${COORDINATOR_INTERVAL_SECONDS:-${val}}" ;;
    REAPER_INTERVAL_SECONDS)      REAPER_INTERVAL_SECONDS="${REAPER_INTERVAL_SECONDS:-${val}}" ;;
    RUNNER_INTERVAL_SECONDS)      RUNNER_INTERVAL_SECONDS="${RUNNER_INTERVAL_SECONDS:-${val}}" ;;
  esac
}

function intervals_apply_defaults() {
  COORDINATOR_INTERVAL_SECONDS="${COORDINATOR_INTERVAL_SECONDS:-${DEFAULT_COORDINATOR_INTERVAL_SECONDS}}"
  REAPER_INTERVAL_SECONDS="${REAPER_INTERVAL_SECONDS:-${DEFAULT_REAPER_INTERVAL_SECONDS}}"
  RUNNER_INTERVAL_SECONDS="${RUNNER_INTERVAL_SECONDS:-${DEFAULT_RUNNER_INTERVAL_SECONDS}}"
}

function intervals_export() {
  export COORDINATOR_INTERVAL_SECONDS REAPER_INTERVAL_SECONDS RUNNER_INTERVAL_SECONDS
}

function intervals_value_for() {
  local -r key="${1}"
  case "${key}" in
    COORDINATOR_INTERVAL_SECONDS) printf '%s' "${COORDINATOR_INTERVAL_SECONDS:-${DEFAULT_COORDINATOR_INTERVAL_SECONDS}}" ;;
    REAPER_INTERVAL_SECONDS)      printf '%s' "${REAPER_INTERVAL_SECONDS:-${DEFAULT_REAPER_INTERVAL_SECONDS}}" ;;
    RUNNER_INTERVAL_SECONDS)      printf '%s' "${RUNNER_INTERVAL_SECONDS:-${DEFAULT_RUNNER_INTERVAL_SECONDS}}" ;;
  esac
}

function intervals_default_for() {
  local -r key="${1}"
  case "${key}" in
    COORDINATOR_INTERVAL_SECONDS) printf '%s' "${DEFAULT_COORDINATOR_INTERVAL_SECONDS}" ;;
    REAPER_INTERVAL_SECONDS)      printf '%s' "${DEFAULT_REAPER_INTERVAL_SECONDS}" ;;
    RUNNER_INTERVAL_SECONDS)      printf '%s' "${DEFAULT_RUNNER_INTERVAL_SECONDS}" ;;
  esac
}

function intervals_file_value_for() {
  local -r key="${1}"
  if [ ! -f "${INTERVALS_FILE}" ]; then return 0; fi
  local line
  line="$(grep -E "^${key}=[0-9]+$" "${INTERVALS_FILE}" 2>/dev/null | tail -n 1)" || true
  if [ -z "${line}" ]; then return 0; fi
  printf '%s' "${line#*=}"
}

function intervals_set() {
  local -r key="${1}"
  local -r value="${2}"
  mkdir -p .daft/workspace
  touch "${INTERVALS_FILE}"
  intervals_remove_key "${key}"
  printf '%s=%s\n' "${key}" "${value}" >> "${INTERVALS_FILE}"
}

function intervals_remove_key() {
  local -r key="${1}"
  local tmp
  tmp="$(mktemp "${INTERVALS_FILE}.XXXXXX")"
  grep -v "^${key}=" "${INTERVALS_FILE}" > "${tmp}" || true
  mv -f "${tmp}" "${INTERVALS_FILE}"
}
