#!/usr/bin/env bash
# clone.sh
# Work-repo clone helpers for DAFt runners. Source this file; do not execute directly.

function clone_at_sha() {
  local -r url="${1}"
  local -r sha="${2}"
  local -r dest="${3}"
  rm -rf "${dest}"
  mkdir -p "$(dirname "${dest}")"
  git clone --no-tags --quiet "${url}" "${dest}"
  ( cd "${dest}" && git checkout --quiet --detach "${sha}" )
}

function clone_cleanup() {
  local -r dest="${1}"
  if [ -d "${dest}" ]; then
    rm -rf "${dest}"
  fi
}
