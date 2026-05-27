#!/usr/bin/env bash
# install-orchestrator.sh
# One-shot installer for the DAFt orchestrator (coordinator + reaper) on this
# host. Designed for: curl -fsSL <url> | bash
#
# All flags have defaults; the bare invocation works. Flags can also be passed
# as environment variables (uppercased with DAFT_ prefix):
#
#   --ctrl-repo=<url>      DAFT_CTRL_REPO     git@github.com:daftci/daftci.git
#   --install-dir=<path>   DAFT_INSTALL_DIR   $HOME/daftci
#   --repos-file=<path>    DAFT_REPOS_FILE    ./repos.txt (skipped if absent)
#
# Argument form (when piping):
#   curl -fsSL <url> | bash -s -- --ctrl-repo=... --install-dir=... --repos-file=...

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_install.log'
declare -r DEFAULT_CTRL_REPO='git@github.com:daftci/daftci.git'
declare -r DEFAULT_REPOS_FILE='./repos.txt'
declare DEFAULT_INSTALL_DIR
DEFAULT_INSTALL_DIR="${HOME:-/tmp}/daftci"

declare DAFT_CTRL_REPO="${DAFT_CTRL_REPO:-}"
declare DAFT_INSTALL_DIR="${DAFT_INSTALL_DIR:-}"
declare DAFT_REPOS_FILE="${DAFT_REPOS_FILE:-}"

declare FAILURES_FILE
FAILURES_FILE="$(mktemp /tmp/daft_install_preflight.XXXXXX)"

function main() {
  exec 5>&1
  parse_args "${@:-}"
  apply_defaults
  log '🚀 DAFt orchestrator installer'
  log_settings
  preflight_all
  do_install
  print_cheatsheet
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function parse_args() {
  local arg
  for arg in "${@:-}"; do
    parse_one "${arg}"
  done
}

function parse_one() {
  case "${1}" in
    --ctrl-repo=*)    DAFT_CTRL_REPO="${1#*=}" ;;
    --install-dir=*)  DAFT_INSTALL_DIR="${1#*=}" ;;
    --repos-file=*)   DAFT_REPOS_FILE="${1#*=}" ;;
    '') ;;
    *) log "❌ Unknown arg: ${1}"; exit 1 ;;
  esac
}

function apply_defaults() {
  DAFT_CTRL_REPO="${DAFT_CTRL_REPO:-${DEFAULT_CTRL_REPO}}"
  DAFT_INSTALL_DIR="${DAFT_INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
  DAFT_REPOS_FILE="${DAFT_REPOS_FILE:-${DEFAULT_REPOS_FILE}}"
}

function log_settings() {
  log "  ctrl-repo   : ${DAFT_CTRL_REPO}"
  log "  install-dir : ${DAFT_INSTALL_DIR}"
  log "  repos-file  : ${DAFT_REPOS_FILE}"
}

function pass() {
  log "  ✅ ${1}"
}

function warn() {
  log "  ⚠️  ${1}"
}

function fail() {
  log "  ❌ ${1}"
  printf '%s\n' "${1}" >> "${FAILURES_FILE}"
}

function preflight_all() {
  log ''
  log '── Pre-flight ──────────────────────────────────'
  run_hard_checks
  run_soft_checks
  finalize_preflight
}

function run_hard_checks() {
  check_not_root
  check_bash_version
  check_git_present
  check_yq_present
  check_install_dir
  check_ctrl_repo_reachable
}

function run_soft_checks() {
  check_process_manager
  check_one_dev 'shellcheck' 'committing from this host (lint)'
  check_one_dev 'node'       'committing from this host (markdownlint via npx)'
}

function check_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    fail 'running as root — install as a normal user'
  else
    pass 'not running as root'
  fi
}

function check_bash_version() {
  local maj
  maj="${BASH_VERSINFO[0]}"
  if [ "${maj}" -lt 3 ]; then
    fail "bash too old (${BASH_VERSION}) — need ≥ 3.2"
  else
    pass "bash ${BASH_VERSION}"
  fi
}

function check_git_present() {
  if command -v git >/dev/null 2>&1; then
    pass "git ($(git --version | awk '{print $3}'))"
  else
    fail 'git not installed'
  fi
}

function check_yq_present() {
  if command -v yq >/dev/null 2>&1; then
    pass 'yq present'
  else
    fail 'yq not installed (needed for .daft/repos/registry.yaml)'
  fi
}

function check_install_dir() {
  if [ ! -e "${DAFT_INSTALL_DIR}" ]; then
    pass "install dir ${DAFT_INSTALL_DIR} (will be created)"
    return 0
  fi
  if [ -z "$(ls -A "${DAFT_INSTALL_DIR}" 2>/dev/null)" ]; then
    pass "install dir ${DAFT_INSTALL_DIR} (empty)"
  else
    fail "install dir ${DAFT_INSTALL_DIR} exists and is not empty"
  fi
}

function check_ctrl_repo_reachable() {
  if git ls-remote "${DAFT_CTRL_REPO}" HEAD >/dev/null 2>&1; then
    pass "ctrl repo reachable: ${DAFT_CTRL_REPO}"
  else
    fail "cannot reach ctrl repo (auth or network): ${DAFT_CTRL_REPO}"
  fi
}

function check_process_manager() {
  if command -v systemctl >/dev/null 2>&1; then
    warn 'systemd present — PID-file mode in use; convert to unit for restart-on-boot'
  elif command -v launchctl >/dev/null 2>&1; then
    warn 'launchd present — PID-file mode in use; convert to plist for restart-on-boot'
  else
    warn 'no service manager detected — PID-file mode only'
  fi
}

function check_one_dev() {
  local -r tool="${1}"
  local -r purpose="${2}"
  if command -v "${tool}" >/dev/null 2>&1; then
    pass "${tool} present (dev: ${purpose})"
  else
    warn "${tool} missing — only needed for ${purpose}"
  fi
}

function finalize_preflight() {
  local count
  count="$(wc -l < "${FAILURES_FILE}" | tr -d ' ')"
  if [ "${count}" -gt 0 ]; then
    log ''
    log "❌ ${count} pre-flight failure(s); aborting"
    exit 1
  fi
  log '✅ pre-flight clean'
}

function do_install() {
  log ''
  log '── Install ─────────────────────────────────────'
  clone_repo
  init_submodule
  bootstrap_standards
  init_daft_layout
  seed_repos
  start_orchestrator
}

function clone_repo() {
  log "📥 cloning ${DAFT_CTRL_REPO} → ${DAFT_INSTALL_DIR}"
  mkdir -p "$(dirname "${DAFT_INSTALL_DIR}")"
  git clone "${DAFT_CTRL_REPO}" "${DAFT_INSTALL_DIR}"
}

function init_submodule() {
  log '📦 initializing .standards submodule'
  ( cd "${DAFT_INSTALL_DIR}" && git submodule update --init --recursive )
}

function bootstrap_standards() {
  log '🔧 bootstrapping standards'
  ( cd "${DAFT_INSTALL_DIR}" && make bootstrap-standards )
}

function init_daft_layout() {
  log '🛠️  initializing .daft/ layout'
  ( cd "${DAFT_INSTALL_DIR}" && make daft-init )
}

function seed_repos() {
  if [ ! -f "${DAFT_REPOS_FILE}" ]; then
    log "  ℹ️  no ${DAFT_REPOS_FILE} found; skipping seed (use 'make daft-repo-add' later)"
    return 0
  fi
  log "📥 seeding upstream repos from ${DAFT_REPOS_FILE}"
  iterate_repos_file
}

function iterate_repos_file() {
  local line
  while IFS= read -r line || [ -n "${line}" ]; do
    seed_one "${line}"
  done < "${DAFT_REPOS_FILE}"
}

function seed_one() {
  local -r line="${1}"
  case "${line}" in '' | '#'*) return 0 ;; esac
  local name url ref
  read -r name url ref <<< "${line}"
  if [ -z "${name}" ] || [ -z "${url}" ] || [ -z "${ref}" ]; then
    log "  ⚠️  malformed line skipped: ${line}"
    return 0
  fi
  ( cd "${DAFT_INSTALL_DIR}" && make daft-repo-add NAME="${name}" URL="${url}" REF="${ref}" )
}

function start_orchestrator() {
  log '🚀 starting orchestrator'
  ( cd "${DAFT_INSTALL_DIR}" && make daft-orchestrator-up )
}

function print_cheatsheet() {
  log ''
  log '── Operator cheatsheet ─────────────────────────'
  cheatsheet_status
  cheatsheet_repos
  log ''
  log '✅ install complete'
}

function cheatsheet_status() {
  log "  cd ${DAFT_INSTALL_DIR}"
  log '  make daft-status                # queue / active / runners snapshot'
  log '  make daft-orchestrator-status   # coordinator + reaper pids'
  log '  make daft-orchestrator-down     # graceful stop (drains after current tick)'
}

function cheatsheet_repos() {
  log '  make daft-repo-add NAME=foo URL=git@github.com:you/foo.git REF=refs/heads/main'
  log '  make daft-repo-remove NAME=foo'
  log '  make daft-repo-list'
  log '  make daft-repo-reload           # manual cache-drop signal to watchers'
}

main "${@:-}"
