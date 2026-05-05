#!/usr/bin/env bash
# metrics.sh
# Filesystem-counter RED metrics for DAFt. Source this file; do not execute directly.

function metric_inc() {
  local -r metric="${1}"
  local -r path=".daft/metrics/${metric}"
  mkdir -p .daft/metrics
  local current
  current="$(metric_read "${path}")"
  printf '%s\n' "$(( current + 1 ))" > "${path}.tmp"
  mv -f "${path}.tmp" "${path}"
}

function metric_read() {
  local -r path="${1}"
  if [ -f "${path}" ]; then
    cat "${path}"
    return 0
  fi
  printf '0'
}

function metric_observe() {
  local -r metric="${1}"
  local -r value="${2}"
  local -r path=".daft/metrics/${metric}"
  mkdir -p .daft/metrics
  printf '%s\n' "${value}" >> "${path}"
  metric_observe_truncate "${path}"
}

function metric_observe_truncate() {
  local -r path="${1}"
  local lines
  lines="$(wc -l < "${path}" 2>/dev/null | tr -d ' ')"
  if [ "${lines:-0}" -gt 10000 ]; then
    tail -n 10000 "${path}" > "${path}.tmp"
    mv -f "${path}.tmp" "${path}"
  fi
}
