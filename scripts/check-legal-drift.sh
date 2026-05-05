#!/usr/bin/env bash
# scripts/check-legal-drift.sh
# Verifies that copied legal files are consistent with their source of truth.
# Project-specific implementation — extend PAIRS below as legal files are added.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# PAIRS format: 'source:copy' — add pairs as legal files are duplicated in this repo.
readonly PAIRS=()

function main() {
  exec 5>&1
  if [ "${#PAIRS[@]}" -eq 0 ]; then
    log '✅ No legal file pairs configured; nothing to check'
    exit 0
  fi
  local failed=0
  for pair in "${PAIRS[@]}"; do
    local src copy
    src="${pair%%:*}"
    copy="${pair##*:}"
    if ! diff -q "${src}" "${copy}" > /dev/null 2>&1; then
      log "❌ Drift detected: ${src} ≠ ${copy}"
      if [ "${CI:-}" = 'true' ]; then
        log "   Run: cp ${src} ${copy}"
      else
        log "   Fixing: cp ${src} ${copy}"
        cp "${src}" "${copy}"
      fi
      failed=1
    fi
  done
  if [ "${failed}" -ne 0 ]; then
    exit 1
  fi
  log '✅ Legal file drift check passed'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/check-legal-drift.log' >&5
}

main "${@:-}"
