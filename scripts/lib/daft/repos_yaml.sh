#!/usr/bin/env bash
# repos_yaml.sh
# Repo-registry YAML reader for DAFt. Requires `yq`. Source this file; do not execute.

function registry_path() {
  printf '.daft/repos/registry.yaml\n'
}

function registry_exists() {
  [ -f "$(registry_path)" ]
}

function registry_repos_count() {
  if ! registry_exists; then
    printf '0\n'
    return 0
  fi
  yq -o=json '.repos // [] | length' "$(registry_path)"
}

function registry_repos_tsv() {
  if ! registry_exists; then
    return 0
  fi
  yq -o=tsv '.repos[] | [.name, .clone_url, .ref] | @tsv' "$(registry_path)" 2>/dev/null \
    || yq '.repos[] | (.name + "\t" + .clone_url + "\t" + .ref)' "$(registry_path)"
}

function registry_repo_field() {
  local -r name="${1}"
  local -r field="${2}"
  yq -r ".repos[] | select(.name == \"${name}\") | .${field}" "$(registry_path)"
}

function registry_repo_exists() {
  local -r name="${1}"
  local -r found="$(registry_repo_field "${name}" 'name')"
  [ "${found}" = "${name}" ]
}
