# shellcheck shell=bash
# lib.bash — helpers for compose-stack bats scenarios.

COMPOSE_ENV='scripts/test/compose/.env'
COMPOSE_FILE='scripts/test/compose/docker-compose.yaml'

dc() {
  docker compose --env-file "${COMPOSE_ENV}" -f "${COMPOSE_FILE}" "$@"
}

dx() {
  dc exec -T "$@"
}

dx_driver() {
  dx test-driver "$@"
}

# Push an empty commit to upstream <name>; emit the new short-sha (7 chars) on
# stdout so the caller can build an exact job-id and assert against THAT.
push_empty_to_upstream() {
  local -r name="${1}"
  dx_driver bash -c "
    tmp=\$(mktemp -d)
    git clone -q /git/${name}.git \"\${tmp}\" >/dev/null 2>&1
    cd \"\${tmp}\"
    git commit -q --allow-empty -m 'tick' >/dev/null 2>&1
    sha=\$(git rev-parse --short=7 HEAD)
    git push -q origin main >/dev/null 2>&1
    rm -rf \"\${tmp}\"
    printf '%s\n' \"\${sha}\"
  "
}

# Wait for an exact job-id directory to appear in archive. Times out after N seconds.
wait_for_archive_job() {
  local -r job_id="${1}"
  local -r seconds="${2:-60}"
  local i=0
  while [ "${i}" -lt "${seconds}" ]; do
    if dx_driver bash -c "
      cd /tmp && rm -rf check && git clone -q /git/daft.git check >/dev/null
      find check/.daft/archive -type d -name '${job_id}' 2>/dev/null | grep -q .
    "; then
      return 0
    fi
    sleep 1
    i=$(( i + 1 ))
  done
  return 1
}

# Distinct runner-ids that own this exact job-id. Should be 1 in steady state.
distinct_runners_for_job() {
  local -r job_id="${1}"
  dx_driver bash -c "
    cd /tmp && rm -rf check && git clone -q /git/daft.git check >/dev/null
    find check/.daft/archive -type d -name '${job_id}' \
        -exec cat {}/runner-id.txt ';' 2>/dev/null \
      | sort -u | grep -c .
  " || printf '0'
}

# Verify MinIO has at least one object under jobs/<job_id>/.
minio_has_artifacts_for_job() {
  local -r job_id="${1}"
  dx_driver bash -c "
    mc alias set local http://minio:9000 minioadmin minioadmin >/dev/null
    mc ls --recursive local/daft-artifacts/jobs/${job_id}/ 2>/dev/null \
      | grep -q .
  "
}
