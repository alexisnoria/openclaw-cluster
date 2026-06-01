#!/usr/bin/env bash
# lib/config.sh — Edit an instance's openclaw.json in-place.
# Pure-FS with optional interactive editor fallback. The ${EDITOR} → vi → cat
# cascade is preserved from v1.1.0 for backward compat.

if [[ -n "${__LIB_CONFIG_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_CONFIG_SOURCED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -z "${__LIB_LOGGING_SOURCED:-}" ]]; then
  # shellcheck source=lib/logging.sh
  # shellcheck disable=SC1090
  source "${_LIB_DIR}/logging.sh"
fi
if [[ -z "${__LIB_UI_SOURCED:-}" ]]; then
  # shellcheck source=lib/ui.sh
  # shellcheck disable=SC1090
  source "${_LIB_DIR}/ui.sh"
fi
if [[ -z "${__LIB_INSTANCE_SOURCED:-}" ]]; then
  # shellcheck source=lib/instance.sh
  # shellcheck disable=SC1090
  source "${_LIB_DIR}/instance.sh"
fi

# ----------------------------------------------------------------------------
# cluster_config <id>
# Opens the instance's openclaw.json with $EDITOR, falling back to vi, then
# to cat if no editor is available. Pure-FS + no docker — safe to unit test.
# ----------------------------------------------------------------------------
cluster_config() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia a configurar")
  fi
  local config_file
  config_file="$(instance_dir "$id")/config/openclaw.json"
  if [[ ! -f "$config_file" ]]; then
    print_error "Config no encontrado para instance-${id}"
    return 1
  fi

  echo "Archivo: ${config_file}"
  echo "Abriendo con el editor por defecto... (Ctrl+C para cancelar)"
  ${EDITOR:-nano} "$config_file" || vi "$config_file" || cat "$config_file"
}
