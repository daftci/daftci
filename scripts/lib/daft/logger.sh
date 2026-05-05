#!/usr/bin/env bash
# logger.sh
# Structured-JSON logging helpers for DAFt. Source this file; do not execute directly.
# Caller must source scripts/lib/daft/time.sh before this file.

function log_json() {
  local -r service="${1}"
  local -r level="${2}"
  local -r message="${3}"
  local -r extra="${4:-}"
  log_json_emit "${service}" "${level}" "${message}" "${extra}"
}

function log_json_emit() {
  local -r service="${1}"
  local -r level="${2}"
  local -r message="${3}"
  local -r extra="${4}"
  local timestamp version
  timestamp="$(utc_rfc3339_ns)"
  version="$(log_json_version)"
  mkdir -p .daft/workspace
  log_json_render "${timestamp}" "${level}" "${service}" "${version}" "${message}" "${extra}" >> ".daft/workspace/${service}.jsonl"
}

function log_json_version() {
  if [ -f VERSION ]; then
    cat VERSION
    return 0
  fi
  printf 'unknown'
}

function log_json_render() {
  local -r timestamp="${1}"
  local -r level="${2}"
  local -r service="${3}"
  local -r version="${4}"
  local -r message="${5}"
  local -r extra="${6}"
  if [ -n "${extra}" ]; then
    printf '{"timestamp":"%s","level":"%s","service":"%s","version":"%s","trace_id":"0","span_id":"0","message":"%s",%s}\n' "${timestamp}" "${level}" "${service}" "${version}" "${message}" "${extra}"
    return 0
  fi
  printf '{"timestamp":"%s","level":"%s","service":"%s","version":"%s","trace_id":"0","span_id":"0","message":"%s"}\n' "${timestamp}" "${level}" "${service}" "${version}" "${message}"
}
