#!/usr/bin/env bash
# lib/status.sh — Inspection: cluster_status, cluster_logs, cluster_exec.
# All functions touch docker; only the formatting helpers (print_status_table)
# are pure and unit-testable.

if [[ -n "${__LIB_STATUS_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_STATUS_SOURCED=1

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
# Pure helper: render the status table for a given set of instances + states.
# Args: a sequence of "id|state|emoji|uptime|url" tuples (newline-separated).
# Pure: no docker, no FS. Testable in bats.
# ----------------------------------------------------------------------------
print_status_table() {
  local rows="$1"
  printf "${CLR_BOLD}┌──────────┬────────┬──────────────────────┬─────────────┬─────────────┐${CLR_RESET}\n"
  printf "${CLR_BOLD}│ %-8s │ %-6s │ %-20s │ %-11s │ %-11s │${CLR_RESET}\n" "Instancia" "Estado" "Gateway URL" "Puertos" "Uptime"
  printf "${CLR_BOLD}├──────────┼────────┼──────────────────────┼─────────────┼─────────────┤${CLR_RESET}\n"
  while IFS='|' read -r id state emoji uptime url; do
    [[ -z "$id" ]] && continue
    local name; name=$(instance_name "$id")
    local gport; gport=$(instance_gateway_port "$id")
    local bport; bport=$(instance_bridge_port "$id")
    printf "│ %-8s │ %-6s │ %-20s │ %5s/%5s │ %-11s │\n" \
      "${name}" "${emoji} ${state}" "$url" "$gport" "$bport" "$uptime"
  done <<< "$rows"
  printf "${CLR_BOLD}└──────────┴────────┴──────────────────────┴─────────────┴─────────────┘${CLR_RESET}\n"
}

# ----------------------------------------------------------------------------
# cluster_status — list all instances + their container state.
# Iterates get_instance_ids and inspects each container.
# ----------------------------------------------------------------------------
cluster_status() {
  check_docker
  local ids=()
  local id
  for id in $(get_instance_ids); do
    [[ -n "$id" ]] && ids+=("$id")
  done

  if [[ ${#ids[@]} -eq 0 ]]; then
    print_warn "No hay instancias creadas."
    return
  fi

  echo ""
  local rows=""
  for id in "${ids[@]}"; do
    local gport; gport=$(instance_gateway_port "$id")
    local container; container="$(instance_name "$id")-gateway"
    local state emoji uptime url

    if docker ps --format '{{.Names}}' | grep -qx "$container"; then
      state="Up"
      emoji="🟢"
      uptime=$(docker ps --filter "name=^${container}$" --format '{{.Status}}' | sed 's/Up //')
      url="http://localhost:${gport}"
    else
      state="Down"
      emoji="🔴"
      uptime="-"
      url="-"
    fi
    rows+="${id}|${state}|${emoji}|${uptime}|${url}"$'\n'
  done

  print_status_table "$rows"
  echo ""
}

# ----------------------------------------------------------------------------
# cluster_logs — tail logs of an instance's gateway container.
# ----------------------------------------------------------------------------
cluster_logs() {
  check_docker
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia para ver logs")
  fi
  local follow=""
  if read_confirm "¿Seguir logs en tiempo real (-f)?"; then
    follow="-f"
  fi
  instance_compose "$id" logs $follow openclaw-gateway
}

# ----------------------------------------------------------------------------
# cluster_exec — exec a command inside an instance's gateway container.
# ----------------------------------------------------------------------------
cluster_exec() {
  check_docker
  local id="${1:-}"
  shift || true
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia")
  fi
  local cmd="$*"
  if [[ -z "$cmd" ]]; then
    cmd=$(read_input "Comando a ejecutar (ej: openclaw status)")
  fi
  print_info "Ejecutando en instance-${id}: ${cmd}"
  docker compose -f "$(instance_dir "$id")/docker-compose.yml" \
    exec openclaw-gateway bash -lc "${cmd}"
}
