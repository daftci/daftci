# shellcheck shell=bash
# setup.bash
# Shared bats helpers for DAFt integration tests.
# Provides:
#   daft_test_setup    — create an isolated tmpdir with .daft/ scaffolded and scripts/ symlinked
#   daft_test_teardown — clean up tmpdir
#   make_local_bare    — create a local bare git repo at $1
#   commit_to_workdir  — commit-and-push from $1 (workdir clone) into the matching bare
#   build_workdir_with_job_script — populate workdir at $1 with .daft/jobs/build that exits $2

daft_test_setup() {
  TMPDIR_TEST="$(mktemp -d)"
  REPO_ROOT="${BATS_TEST_DIRNAME%/scripts/test/integration*}"
  if [ ! -d "${REPO_ROOT}/scripts" ]; then
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../../.." && pwd)"
  fi
  export TMPDIR_TEST REPO_ROOT
  mkdir -p "${TMPDIR_TEST}/scripts"
  ln -s "${REPO_ROOT}/scripts/lib"         "${TMPDIR_TEST}/scripts/lib"
  ln -s "${REPO_ROOT}/scripts/coordinator" "${TMPDIR_TEST}/scripts/coordinator"
  ln -s "${REPO_ROOT}/scripts/reaper"      "${TMPDIR_TEST}/scripts/reaper"
  ln -s "${REPO_ROOT}/scripts/runner"      "${TMPDIR_TEST}/scripts/runner"
  ln -s "${REPO_ROOT}/scripts/daft"        "${TMPDIR_TEST}/scripts/daft"
  cp "${REPO_ROOT}/VERSION" "${TMPDIR_TEST}/VERSION"
  cd "${TMPDIR_TEST}"
  git init --quiet
  git config user.email 'test@example.com'
  git config user.name 'test'
  git config commit.gpgsign false
  bash scripts/daft/init.sh >/dev/null
  git add -A
  git commit --quiet -m 'init'
}

daft_test_teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "${TMPDIR_TEST}" ]; then
    cd /
    rm -rf "${TMPDIR_TEST}"
  fi
}

make_local_bare() {
  local -r path="${1}"
  git init --quiet --bare "${path}"
}

build_workdir_with_job_script() {
  local -r workdir="${1}"
  local -r exit_code="${2:-0}"
  local -r bare="${3}"
  mkdir -p "${workdir}/.daft/jobs"
  printf '#!/usr/bin/env bash\nset -o errexit\necho "hello from build"\nexit %s\n' "${exit_code}" \
    > "${workdir}/.daft/jobs/build"
  chmod +x "${workdir}/.daft/jobs/build"
  ( cd "${workdir}" && git init --quiet \
    && git config user.email 'test@example.com' && git config user.name 'test' \
    && git config commit.gpgsign false \
    && git remote add origin "${bare}" \
    && git add -A && git commit --quiet -m 'add build script' \
    && git branch -M main \
    && git push --quiet origin main ) >/dev/null 2>&1
}

commit_empty_to_workdir() {
  local -r workdir="${1}"
  ( cd "${workdir}" && git commit --quiet --allow-empty -m 'tick' \
    && git push --quiet origin main ) >/dev/null 2>&1
}

count_queue_jobs() {
  find .daft/queue/x86_64 -type f -name '*.json' -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
}
