#!/usr/bin/env bash
# reload.sh
# Helpers for the orchestrator reload signal. Source this file; do not execute directly.
#
# Signal mechanism: `.daft/repos/reload.tick` holds a single integer that is
# incremented whenever upstream-registry state changes (or whenever an operator
# wants to force a cache drop in watching daemons). The file lives in
# `.daft/repos/` so the bump is part of the same git commit as the registry
# mutation that triggered it, which means hosts see the bump on pull.
#
# Watchers persist their last-seen value in `.daft/workspace/` (gitignored,
# per-host) and compare on each tick.

declare -r RELOAD_TICK_FILE='.daft/repos/reload.tick'

function reload_current_tick() {
  if [ ! -f "${RELOAD_TICK_FILE}" ]; then
    printf '0'
    return 0
  fi
  cat "${RELOAD_TICK_FILE}"
}

function reload_bump_pending() {
  local cur next
  cur="$(reload_current_tick)"
  next=$(( cur + 1 ))
  mkdir -p .daft/repos
  printf '%s\n' "${next}" > "${RELOAD_TICK_FILE}"
}

function reload_last_seen_path() {
  local -r service="${1}"
  printf '.daft/workspace/%s-reload-seen.txt' "${service}"
}

function reload_read_last_seen() {
  local -r service="${1}"
  local -r path="$(reload_last_seen_path "${service}")"
  if [ ! -f "${path}" ]; then
    printf '0'
    return 0
  fi
  cat "${path}"
}

function reload_write_last_seen() {
  local -r service="${1}"
  local -r value="${2}"
  mkdir -p .daft/workspace
  printf '%s\n' "${value}" > "$(reload_last_seen_path "${service}")"
}

function reload_changed_for() {
  local -r service="${1}"
  local cur last
  cur="$(reload_current_tick)"
  last="$(reload_read_last_seen "${service}")"
  [ "${cur}" != "${last}" ]
}
