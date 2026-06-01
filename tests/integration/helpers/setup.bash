#!/usr/bin/env bash
# tests/integration/helpers/setup.bash — shared bats bootstrap for integration
# tests. Sources the project under test (openclaw-cluster.sh) into a sandboxed
# repo copy, and provides helpers for asserting on instances/, docker, etc.

# Resolve paths. We deliberately do NOT source the real openclaw-cluster.sh
# because its `main` would auto-run. Instead we test it as an external binary.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT_DIR="$(cd "${TESTS_DIR}/../.." && pwd -P)"

# Per-test sandbox: a copy of the repo with its own instances/, backups/, .env
SANDBOX_DIR=""
# shellcheck disable=SC2034  # consumed by .bats files via environment
FAKE_API_KEY="sk-or-v1-fake-integration-test-key-0000000000000000"
# shellcheck disable=SC2034
FAKE_TG_TOKEN="0000000000:AAFakeTelegramBotTokenForIntegrationTest"

# bats helper: run docker info once per file and skip the whole file if absent
_docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

# Make a clean sandbox copy of the repo (without instances/ or .env).
make_sandbox() {
  SANDBOX_DIR="$(mktemp -d -t openclaw-cluster-it-XXXXXX)"
  # Use rsync if available, else cp -R
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='instances' --exclude='backups' --exclude='.env' \
      --exclude='.git' --exclude='*.bak' \
      "${ROOT_DIR}/" "${SANDBOX_DIR}/"
  else
    # Fallback: copy then prune
    cp -R "${ROOT_DIR}/." "${SANDBOX_DIR}/" 2>/dev/null || true
    rm -rf "${SANDBOX_DIR}/instances" "${SANDBOX_DIR}/backups" "${SANDBOX_DIR}/.env" "${SANDBOX_DIR}/.git" 2>/dev/null || true
    find "${SANDBOX_DIR}" -name '*.bak' -delete 2>/dev/null || true
  fi
  cd "${SANDBOX_DIR}" || return 1
}

# Run the cluster manager in batch mode. Echoes stdout, returns the exit code.
# Usage: run_cluster <cmd> [args...]
run_cluster() {
  ./openclaw-cluster.sh "$@"
}

# Common setup for every test
setup() {
  if ! _docker_available; then
    skip "Docker daemon no disponible — integration test omitido"
  fi
  make_sandbox
}

# Common teardown: destroy all instances + clean sandbox
teardown() {
  if [[ -n "${SANDBOX_DIR}" && -d "${SANDBOX_DIR}" ]]; then
    cd "${SANDBOX_DIR}" 2>/dev/null || true
    if [[ -d instances ]]; then
      for f in instances/*/docker-compose.yml; do
        [[ -f "$f" ]] || continue
        docker compose -f "$f" down --remove-orphans -v &>/dev/null || true
      done
    fi
    rm -rf "${SANDBOX_DIR}"
  fi
  SANDBOX_DIR=""
}

# Assertions

# assert_file_exists <path>
assert_file_exists() {
  [[ -f "$1" ]] || {
    echo "FAIL: archivo no existe: $1" >&2
    return 1
  }
}

# assert_dir_exists <path>
assert_dir_exists() {
  [[ -d "$1" ]] || {
    echo "FAIL: directorio no existe: $1" >&2
    return 1
  }
}

# assert_valid_json <file>
assert_valid_json() {
  if ! jq . "$1" >/dev/null 2>&1; then
    echo "FAIL: JSON inválido en $1" >&2
    return 1
  fi
}

# assert_grep <file> <pattern>
assert_grep() {
  grep -qE "$2" "$1" || {
    echo "FAIL: $1 no contiene /$2/" >&2
    return 1
  }
}
