#!/usr/bin/env bash
# scripts/test-integration.sh — Run bats integration tests against a real
# (or mocked) Docker daemon.
#
# Integration tests live in tests/integration/ and REQUIRE:
#   - docker daemon reachable (`docker info` exits 0)
#   - the openclaw-cluster.sh binary in the repo root
#   - a writable $TMPDIR
#
# They are NOT run in CI by default. Trigger them locally with:
#   make test-integration
# or in GitHub Actions via workflow_dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${ROOT_DIR}/tests/integration"

CLR_GREEN='\033[0;32m'
CLR_RED='\033[0;31m'
CLR_YELLOW='\033[1;33m'
CLR_BLUE='\033[0;34m'
CLR_RESET='\033[0m'

info() { echo -e "${CLR_BLUE}ℹ️  $*${CLR_RESET}"; }
success() { echo -e "${CLR_GREEN}✅ $*${CLR_RESET}"; }
warn() { echo -e "${CLR_YELLOW}⚠️  $*${CLR_RESET}" >&2; }
error() { echo -e "${CLR_RED}❌ $*${CLR_RESET}" >&2; }

require_docker() {
  if ! command -v docker &>/dev/null; then
    error "docker no está instalado. Instálalo desde https://docs.docker.com/get-docker/"
    exit 1
  fi
  if ! docker info &>/dev/null; then
    error "Docker daemon no responde. Inicia Docker Desktop o el servicio de Docker."
    exit 1
  fi
  info "Docker daemon: $(docker info --format '{{.ServerVersion}}')"
}

ensure_bats() {
  if ! command -v bats &>/dev/null; then
    error "bats no está instalado. Ejecuta: ./scripts/test-unit.sh (instala helpers) o brew install bats-core"
    exit 1
  fi
}

cleanup_orphans() {
  # Defensive: if a previous test crashed, wipe any dangling instances
  if [[ -d "${ROOT_DIR}/instances" ]]; then
    for f in "${ROOT_DIR}/instances"/*/docker-compose.yml; do
      [[ -f "$f" ]] || continue
      docker compose -f "$f" down --remove-orphans -v &>/dev/null || true
    done
  fi
}

main() {
  require_docker
  ensure_bats

  if [[ ! -d "$TESTS_DIR" ]]; then
    error "No existe el directorio de tests: $TESTS_DIR"
    exit 1
  fi

  trap cleanup_orphans EXIT
  cleanup_orphans

  info "Ejecutando bats en ${TESTS_DIR}"
  if bats "$@" "${TESTS_DIR}"; then
    success "Tests de integración: PASS"
  else
    error "Tests de integración: FAIL"
    return 1
  fi
}

main "$@"
