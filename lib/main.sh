#!/usr/bin/env bash
# lib/main.sh — Entry point: validates requirements, sets up the cluster
# directory, then dispatches to the menu or batch handler.
#
# main [args...]

if [[ -n "${__LIB_MAIN_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_MAIN_SOURCED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -z "${__LIB_CLUSTER_SOURCED:-}" ]]; then
  # shellcheck source=lib/cluster.sh
  # shellcheck disable=SC1090
  source "${_LIB_DIR}/cluster.sh"
fi
if [[ -z "${__LIB_LOGGING_SOURCED:-}" ]]; then
  # shellcheck source=lib/logging.sh
  # shellcheck disable=SC1090
  source "${_LIB_DIR}/logging.sh"
fi

# ----------------------------------------------------------------------------
# main [args...]
#   - No args: interactive menu
#   - With args: batch mode (first arg is the command)
# ----------------------------------------------------------------------------
main() {
  # Check requirements
  require_command docker
  require_command openssl

  # Ensure cluster dir structure exists
  mkdir -p "${INSTANCES_DIR}" "${CLUSTER_DIR}/backups"

  if [[ $# -eq 0 ]]; then
    run_interactive
  else
    run_batch "$@"
  fi
}
