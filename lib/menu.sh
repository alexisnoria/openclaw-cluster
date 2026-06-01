#!/usr/bin/env bash
# lib/menu.sh — Interactive menu loop.
#
# Provides:
#   - show_menu         : render the 18-option menu
#   - run_interactive   : the while-true dispatch loop (blocking on stdin)
#
# Interactive only — no automated tests possible (the loop blocks on `read
# -rp`). We unit-test show_menu rendering and the case dispatch separately.

if [[ -n "${__LIB_MENU_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_MENU_SOURCED=1

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
# show_menu — print the interactive menu with live cluster stats.
# ----------------------------------------------------------------------------
show_menu() {
  print_header

  local active=0 total=0
  if [[ -d "$INSTANCES_DIR" ]]; then
    total=$(get_instance_count)
    local ids=()
    local id
    for id in $(get_instance_ids); do
      [[ -n "$id" ]] && ids+=("$id")
    done
    for id in ${ids[@]+"${ids[@]}"}; do
      local c
      c="$(instance_name "$id")-gateway"
      if command -v docker >/dev/null 2>&1; then
        docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c" && ((active++)) || true
      fi
    done
  fi

  echo -e "${CLR_DIM}Cluster: ${CLUSTER_DIR}${CLR_RESET}"
  echo -e "${CLR_DIM}Instancias activas: ${active}/${total}${CLR_RESET}"
  echo ""

  echo -e "${CLR_BOLD}${CLR_MAGENTA}⚡ Operaciones${CLR_RESET}"
  echo -e "  [1]  📦 Inicializar Cluster"
  echo -e "  [2]  ▶️  Iniciar Instancias"
  echo -e "  [3]  ⏹️  Detener Instancias"
  echo -e "  [4]  🔄 Reiniciar Instancia"
  echo -e "  [5]  📊 Estado del Cluster"
  echo -e "  [6]  📜 Ver Logs"
  echo -e "  [7]  🐚 Ejecutar Comando en Instancia"
  echo -e "  [8]  ⚙️  Configurar Instancia"
  echo -e "  [9]  🗑️  Destruir Instancia"
  echo ""
  echo -e "${CLR_BOLD}${CLR_MAGENTA}🔧 Administración${CLR_RESET}"
  echo -e "  [10] 🧹 Limpiar Todo (Nuclear)"
  echo -e "  [11] ⬆️  Actualizar Imagen de OpenClaw"
  echo -e "  [12] 💾 Backup de Instancia"
  echo -e "  [13] ♻️  Restore de Instancia"
  echo -e "  [14] 🏗️  Escalar Cluster"
  echo -e "  [15] 🔑 Ver Tokens de Acceso"
  echo -e "  [16] 🌐 Abrir Dashboard en Navegador"
  echo -e "  [17] 🔑 Cambiar OpenRouter API Key"
  echo -e "  [18] 💬 Configurar Telegram"
  echo ""
  echo -e "  [0]  ❌ Salir"
  echo ""
}

# ----------------------------------------------------------------------------
# run_interactive — the while-true loop. Reads from stdin. Not unit-testable
# because the inner `read` blocks. Use `show_menu` for visual tests.
# ----------------------------------------------------------------------------
run_interactive() {
  while true; do
    show_menu
    local choice
    choice=$(read_input "Selecciona una opción")

    case "$choice" in
      1) cluster_init ;;
      2) cluster_start ;;
      3) cluster_stop ;;
      4) cluster_restart ;;
      5) cluster_status ;;
      6) cluster_logs ;;
      7) cluster_exec ;;
      8) cluster_config ;;
      9) cluster_destroy ;;
      10) cluster_clean_all ;;
      11) cluster_update ;;
      12) cluster_backup ;;
      13) cluster_restore ;;
      14) cluster_scale ;;
      15) cluster_tokens ;;
      16) cluster_dashboard ;;
      17) cluster_set_openrouter_key ;;
      18) cluster_set_telegram ;;
      0 | q | quit | exit)
        echo -e "${CLR_GREEN}👋 Hasta luego.${CLR_RESET}"
        exit 0
        ;;
      *)
        print_error "Opción inválida."
        ;;
    esac

    echo ""
    read -rp "Presiona Enter para continuar..."
  done
}
