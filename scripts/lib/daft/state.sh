#!/usr/bin/env bash
# state.sh
# Per-repo reachability state read/write helpers for DAFt. Source this file; do not execute.

function state_path() {
  local -r name="${1}"
  printf '.daft/repos/state/%s.json\n' "${name}"
}

function read_state() {
  local -r name="${1}"
  local -r path="$(state_path "${name}")"
  if [ -f "${path}" ]; then
    cat "${path}"
    return 0
  fi
  printf '{}'
}

function write_state_atomic() {
  local -r name="${1}"
  local -r json="${2}"
  local -r path="$(state_path "${name}")"
  mkdir -p .daft/repos/state
  printf '%s\n' "${json}" > "${path}.tmp"
  mv -f "${path}.tmp" "${path}"
}

function state_field() {
  local -r name="${1}"
  local -r field="${2}"
  read_state "${name}" | yq -r ".${field} // \"\""
}
