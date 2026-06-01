#!/usr/bin/env bash
# lib/batch.sh — Non-interactive command dispatcher.
#
# Provides:
#   - run_batch <cmd> [args...]
#   - batch_usage   : print the help/usage text
#
# Maps the 18 batch commands to their cluster_* handlers. Backward-compat
# with the v1.1.0 batch mode: same names, same semantics.

if [[ -n "${__LIB_BATCH_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_BATCH_SOURCED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -z "${__LIB_LOGGING_SOURCED:-}" ]]; then
  # shellcheck source=lib/logging.sh
  # shellcheck disable=SC1090
  source "${_LIB_DIR}/logging.sh"
fi

# ----------------------------------------------------------------------------
# batch_usage [prog]
# Print the usage text. The first arg is the program name (defaults to $0).
# ----------------------------------------------------------------------------
batch_usage() {
  local prog="${1:-openclaw-cluster}"
  echo "Uso: ${prog} [comando] [args...]"
  echo "Comandos:"
  echo "  init [count] [tag] [chrome] [headless] [tz] [openrouter_api_key] [openrouter_model] [telegram_bot_token] [telegram_dm_policy]"
  echo "  set-openrouter-key [instance|all] [new_key]"
  echo "  set-telegram [instance|all] [bot_token] [dm_policy]"
  echo "  start|stop|restart|status|logs|exec|config|destroy|backup|restore|scale|tokens|dashboard"
  echo "  clean|update"
}

# ----------------------------------------------------------------------------
# run_batch <cmd> [args...]
# Dispatch a single command. Returns 0 on success, 1 on unknown command.
# ----------------------------------------------------------------------------
run_batch() {
  local cmd="$1"
  shift || true

  case "$cmd" in
    init) cluster_init "$@" ;;
    start) cluster_start "$@" ;;
    stop) cluster_stop "$@" ;;
    restart) cluster_restart "$@" ;;
    status) cluster_status "$@" ;;
    logs) cluster_logs "$@" ;;
    exec) cluster_exec "$@" ;;
    config) cluster_config "$@" ;;
    destroy) cluster_destroy "$@" ;;
    clean) cluster_clean_all ;;
    update) cluster_update "$@" ;;
    backup) cluster_backup "$@" ;;
    restore) cluster_restore "$@" ;;
    scale) cluster_scale "$@" ;;
    tokens) cluster_tokens ;;
    dashboard) cluster_dashboard "$@" ;;
    set-openrouter-key) cluster_set_openrouter_key "$@" ;;
    set-telegram) cluster_set_telegram "$@" ;;
    -h | --help | help)
      batch_usage "${BATCH_PROG:-openclaw-cluster}"
      ;;
    *)
      print_error "Comando batch desconocido: ${cmd}"
      batch_usage "${BATCH_PROG:-openclaw-cluster}"
      return 1
      ;;
  esac
}
