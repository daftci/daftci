#!/usr/bin/env bash
# lifecycle.sh
# Colima lifecycle for compose tests on macOS. On Linux this is a no-op (assumes
# native Docker daemon is already running).
# Args (one of): up | down | status | purge

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_compose_lifecycle.log'
declare -r CONFIG_PATH='scripts/test/compose/config.yaml'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r action="${1}"
  case "${action}" in
    up)     do_up ;;
    down)   do_down ;;
    status) do_status ;;
    purge)  do_purge ;;
    *) log "❌ unknown action: ${action}"; exit 1 ;;
  esac
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 1 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: lifecycle.sh up|down|status|purge'
    exit 1
  fi
}

function is_macos() {
  [ "$(uname -s)" = 'Darwin' ]
}

function require_colima() {
  if ! command -v colima >/dev/null 2>&1; then
    log '❌ colima not found (brew install colima)'
    exit 1
  fi
}

function profile() {
  yq -r '.colima.profile // "daft-test"' "${CONFIG_PATH}"
}

function cpu()    { yq -r '.colima.cpu // 2'    "${CONFIG_PATH}"; }
function memory() { yq -r '.colima.memory // 4' "${CONFIG_PATH}"; }
function disk()   { yq -r '.colima.disk // 20'  "${CONFIG_PATH}"; }

function do_up() {
  if ! is_macos; then
    log 'ℹ️  not macOS; assuming Docker is already running'
    return 0
  fi
  require_colima
  if colima_running; then
    ensure_mount
    return 0
  fi
  start_colima
}

function start_colima() {
  local mount_root
  mount_root="$(git rev-parse --show-toplevel)"
  log "🚀 starting colima '$(profile)' cpu=$(cpu) mem=$(memory)G disk=$(disk)G mount=${mount_root}"
  colima start -p "$(profile)" --cpu "$(cpu)" --memory "$(memory)" --disk "$(disk)" \
    --mount "${mount_root}:w"
  log '✅ colima up'
}

function ensure_mount() {
  local mount_root
  mount_root="$(git rev-parse --show-toplevel)"
  if colima ssh -p "$(profile)" -- ls "${mount_root}" >/dev/null 2>&1; then
    log "✅ colima profile '$(profile)' running with mount ${mount_root}"
    return 0
  fi
  log "🔄 colima '$(profile)' running but missing mount ${mount_root}; restarting"
  colima stop -p "$(profile)"
  start_colima
}

function colima_running() {
  colima status -p "$(profile)" >/dev/null 2>&1
}

function do_down() {
  if ! is_macos; then return 0; fi
  require_colima
  if ! colima_running; then
    log "ℹ️  colima profile '$(profile)' not running"
    return 0
  fi
  log "🛑 stopping colima profile '$(profile)'"
  colima stop -p "$(profile)"
}

function do_purge() {
  if ! is_macos; then return 0; fi
  require_colima
  log "🧨 deleting colima profile '$(profile)' (data will be lost)"
  colima delete -p "$(profile)" --force || true
}

function do_status() {
  if ! is_macos; then
    log 'ℹ️  not macOS; colima not used'
    return 0
  fi
  require_colima
  colima status -p "$(profile)" || log "❌ colima profile '$(profile)' not running"
}

main "${@:-}"
