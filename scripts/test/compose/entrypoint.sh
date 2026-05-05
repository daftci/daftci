#!/usr/bin/env bash
# entrypoint.sh
# Container entrypoint for coordinator/reaper/runner containers.
# On first start, clone /git/daft.git into /work/daft. On subsequent starts
# (volume already populated), git pull --rebase to sync state. Then exec the
# command passed to the container.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_compose_entrypoint.log'
declare -r BARE='/git/daft.git'
declare -r WORK='/work/daft'

function main() {
  exec 5>&1
  wait_for_bare
  ensure_clone
  exec "$@"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function wait_for_bare() {
  local attempt=0
  while [ ! -d "${BARE}/objects" ] || [ -z "$(git -C "${BARE}" rev-parse HEAD 2>/dev/null || true)" ]; do
    if [ "${attempt}" -ge 60 ]; then
      log '❌ /git/daft.git never became ready'
      exit 1
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done
}

function ensure_clone() {
  if [ -d "${WORK}/.git" ]; then
    log '🔄 syncing existing /work/daft from /git/daft.git'
    git -C "${WORK}" pull --rebase --autostash >/dev/null 2>&1 || true
    return 0
  fi
  log '📥 cloning /git/daft.git into /work/daft'
  git clone --quiet "${BARE}" "${WORK}"
}

main "${@:-}"
