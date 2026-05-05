#!/usr/bin/env bash
# bootstrap.sh
# Runs INSIDE the test-driver container. Initializes /git bare repos (central
# daft + upstreams), seeds the central daft repo from the host bind-mount at
# /repo, configures MinIO bucket, and writes runner identities. Idempotent.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_compose_bootstrap.log'
declare -r CONFIG='/repo/scripts/test/compose/config.yaml'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  init_central_daft
  init_upstream_repos
  init_minio_bucket
  populate_daft_state
  log '✅ bootstrap complete'
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -gt 1 ] || [ -n "${1:-}" ]; then
    log '❌ Error: Unexpected argument'
    exit 1
  fi
}

function init_central_daft() {
  if [ -d /git/daft.git ]; then
    log 'ℹ️  /git/daft.git already exists'
    return 0
  fi
  log '🛠️  initializing central daft bare repo'
  git init --bare --initial-branch=main /git/daft.git >/dev/null
  seed_central_daft
}

function seed_central_daft() {
  local tmp
  tmp="$(mktemp -d)"
  cp -a /repo/. "${tmp}/"
  ( cd "${tmp}" && rm -rf .git \
    && git init -q --initial-branch=main \
    && git add -A \
    && git commit -q -m 'bootstrap: daft scaffolding' \
    && git remote add origin /git/daft.git \
    && git push -q origin main )
  rm -rf "${tmp}"
}

function init_upstream_repos() {
  local n
  while IFS= read -r n; do
    [ -z "${n}" ] && continue
    init_one_upstream "${n}"
  done < <(yq -r '.upstreams[].name' "${CONFIG}")
}

function init_one_upstream() {
  local -r n="${1}"
  if [ -d "/git/${n}.git" ]; then return 0; fi
  log "🛠️  initializing upstream ${n}"
  git init --bare --initial-branch=main "/git/${n}.git" >/dev/null
  seed_upstream "${n}"
}

function seed_upstream() {
  local -r n="${1}"
  local tmp
  tmp="$(mktemp -d)"
  ( cd "${tmp}" && git init -q --initial-branch=main \
    && mkdir -p .daft/jobs \
    && build_script_for "${n}" > .daft/jobs/build \
    && chmod +x .daft/jobs/build \
    && git add -A \
    && git commit -q -m "${n}: initial commit" \
    && git remote add origin "/git/${n}.git" \
    && git push -q origin main )
  rm -rf "${tmp}"
}

function build_script_for() {
  local -r n="${1}"
  cat <<EOF
#!/usr/bin/env bash
set -o errexit
echo "build ${n} sha=\${DAFT_SHA:-unknown}"
mkdir -p "\${DAFT_ARTIFACTS_DIR}"
printf 'job=%s\nsha=%s\nrunner=%s\n' "\${DAFT_JOB_ID}" "\${DAFT_SHA}" "\${DAFT_RUNNER_ID}" \
    > "\${DAFT_ARTIFACTS_DIR}/manifest.txt"
exit 0
EOF
}

function init_minio_bucket() {
  log '🛠️  configuring MinIO bucket'
  local endpoint bucket access secret
  endpoint="$(yq -r '.minio.endpoint_internal' "${CONFIG}")"
  bucket="$(yq -r '.minio.bucket' "${CONFIG}")"
  access="$(yq -r '.minio.access_key' "${CONFIG}")"
  secret="$(yq -r '.minio.secret_key' "${CONFIG}")"
  mc alias set local "${endpoint}" "${access}" "${secret}" >/dev/null
  mc mb --ignore-existing "local/${bucket}" >/dev/null
}

function populate_daft_state() {
  log '🌱 populating daft state (registry + runner identities)'
  local tmp
  tmp="$(mktemp -d)"
  ( cd "${tmp}" && git clone -q /git/daft.git . \
    && bash scripts/daft/init.sh >/dev/null \
    && add_upstreams \
    && write_runner_identities \
    && git push -q origin main )
  rm -rf "${tmp}"
}

function add_upstreams() {
  local n
  while IFS= read -r n; do
    [ -z "${n}" ] && continue
    bash scripts/daft/repo_add.sh "${n}" "/git/${n}.git" 'refs/heads/main' >/dev/null \
      || true
  done < <(yq -r '.upstreams[].name' "${CONFIG}")
}

function write_runner_identities() {
  local i
  for i in runner-a runner-b runner-c; do
    mkdir -p ".daft/runners/${i}"
    printf '{"id":"%s","hostname":"%s","isa":"x86_64","created_at":"bootstrap"}\n' \
      "${i}" "${i}" > ".daft/runners/${i}/identity.json"
  done
  git add -A .daft/
  if ! git diff --cached --quiet; then
    git commit -q -m 'bootstrap: runner identities'
  fi
}

main "${@:-}"
