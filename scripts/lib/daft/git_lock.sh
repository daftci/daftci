#!/usr/bin/env bash
# git_lock.sh
# Git push/pull/rebase helpers for the central daft repo lock primitive.
# Source this file; do not execute directly.

function pull_rebase() {
  git pull --rebase --autostash 2>&1
}

function commit_and_push_with_retry() {
  local -r message="${1}"
  local -r max_retries="${2:-3}"
  git add -A .daft/
  if git diff --cached --quiet; then
    return 0
  fi
  git commit -m "${message}" >/dev/null
  push_with_rebase_retry "${max_retries}"
}

function push_with_rebase_retry() {
  local -r max_retries="${1}"
  local attempt=0
  while [ "${attempt}" -lt "${max_retries}" ]; do
    if git push 2>&1; then
      return 0
    fi
    attempt=$(( attempt + 1 ))
    git pull --rebase --autostash 2>&1 || return 1
  done
  return 1
}

function reset_to_origin() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git fetch origin "${branch}" 2>&1
  git reset --hard "origin/${branch}"
}

function has_origin_remote() {
  git remote get-url origin >/dev/null 2>&1
}

function commit_local_only() {
  local -r message="${1}"
  git add -A .daft/
  if git diff --cached --quiet; then
    return 0
  fi
  git commit -m "${message}" >/dev/null
}

function commit_local_or_push() {
  local -r message="${1}"
  local -r max_retries="${2:-3}"
  if has_origin_remote; then
    pull_rebase >/dev/null
    commit_and_push_with_retry "${message}" "${max_retries}"
    return 0
  fi
  commit_local_only "${message}"
}
