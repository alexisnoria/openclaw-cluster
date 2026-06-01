#!/usr/bin/env bash
# scripts/test-unit.sh — Run bats unit tests for the cluster manager.
#
# This is a thin wrapper around `bats` that:
#   - Verifies bats is installed
#   - Auto-installs bats from source if missing (best effort)
#   - Runs tests/bats/ with TAP output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${ROOT_DIR}/tests/bats"

CLR_GREEN='\033[0;32m'
CLR_RED='\033[0;31m'
CLR_BLUE='\033[0;34m'
CLR_RESET='\033[0m'

info()    { echo -e "${CLR_BLUE}ℹ️  $*${CLR_RESET}"; }
success() { echo -e "${CLR_GREEN}✅ $*${CLR_RESET}"; }
error()   { echo -e "${CLR_RED}❌ $*${CLR_RESET}" >&2; }

ensure_bats() {
  if command -v bats &>/dev/null; then
    return 0
  fi

  warn "bats no está instalado. Intentando instalación rápida..."

  if command -v brew &>/dev/null; then
    info "brew install bats-core"
    brew install bats-core && return 0
  fi

  if command -v apt-get &>/dev/null; then
    info "sudo apt-get install -y bats"
    sudo apt-get update && sudo apt-get install -y bats && return 0
  fi

  if command -v git &>/dev/null; then
    local target="${HOME}/.local/bats"
    info "git clone https://github.com/bats-core/bats-core.git ${target}"
    git clone --depth 1 https://github.com/bats-core/bats-core.git "${target}"
    "${target}/install.sh" "${HOME}/.local"
    export PATH="${HOME}/.local/bin:${PATH}"
    command -v bats &>/dev/null && return 0
  fi

  error "No se pudo instalar bats automáticamente. Instálalo manualmente:"
  error "  brew install bats-core      # macOS"
  error "  apt install bats            # Debian/Ubuntu"
  error "  https://github.com/bats-core/bats-core"
  return 1
}

main() {
  ensure_bats

  if [[ ! -d "$TESTS_DIR" ]]; then
    error "No existe el directorio de tests: $TESTS_DIR"
    exit 1
  fi

  info "Ejecutando bats en ${TESTS_DIR}"
  if bats "$@"; then
    success "Tests unitarios: PASS"
  else
    error "Tests unitarios: FAIL"
    return 1
  fi
}

main "$@"
