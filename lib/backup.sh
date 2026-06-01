#!/usr/bin/env bash
# lib/backup.sh — Tar.gz an instance to backups/, and restore from one.
# cluster_backup is pure FS (tar). cluster_restore is also pure FS:
# extract, regenerate token, rewrite template variables, chown.

if [[ -n "${__LIB_BACKUP_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_BACKUP_SOURCED=1

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

CLUSTER_DIR="${CLUSTER_DIR:-$(pwd)}"
TEMPLATE_FILE="${TEMPLATE_FILE:-${CLUSTER_DIR}/docker-compose.template.yml}"

# ----------------------------------------------------------------------------
# cluster_backup <id>
# Pure-FS: tar -czf <cluster>/backups/instance-<id>_<ts>.tar.gz the
# instance directory. Returns the path to stdout for callers that want it.
# ----------------------------------------------------------------------------
cluster_backup() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia a respaldar")
  fi
  local dir; dir=$(instance_dir "$id")
  if [[ ! -d "$dir" ]]; then
    print_error "Instancia ${id} no existe."
    return 1
  fi

  local backup_dir="${CLUSTER_DIR}/backups"
  mkdir -p "$backup_dir"
  local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${backup_dir}/instance-${id}_${timestamp}.tar.gz"

  print_info "Creando backup de instance-${id} ..."
  tar -czf "$backup_file" -C "$INSTANCES_DIR" "instance-${id}"
  print_success "Backup creado: ${backup_file}"
  printf '%s\n' "$backup_file"
}

# ----------------------------------------------------------------------------
# cluster_restore <backup_file> <id>
# Pure-FS + no docker (the only "infra" call is docker compose down if the
# target instance already exists, which we skip if docker isn't there).
# ----------------------------------------------------------------------------
cluster_restore() {
  local backup_file="${1:-}"
  if [[ -z "$backup_file" ]]; then
    local backup_dir="${CLUSTER_DIR}/backups"
    if [[ ! -d "$backup_dir" ]]; then
      print_error "No hay directorio de backups."
      return 1
    fi
    echo "Backups disponibles:"
    ls -1t "$backup_dir"
    backup_file=$(read_input "Nombre del archivo backup (relativo a backups/)")
    backup_file="${backup_dir}/${backup_file}"
  fi

  if [[ ! -f "$backup_file" ]]; then
    print_error "Archivo no encontrado: ${backup_file}"
    return 1
  fi

  local id="${2:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia destino (se sobrescribirá si existe)")
  fi

  local target_dir; target_dir=$(instance_dir "$id")
  if [[ -d "$target_dir" ]]; then
    print_warn "La instancia ${id} ya existe."
    if ! read_confirm "¿Sobrescribir datos existentes?"; then
      print_info "Cancelado."
      return 0
    fi
    if command -v docker >/dev/null 2>&1; then
      docker compose -f "${target_dir}/docker-compose.yml" down 2>/dev/null || true
    fi
    rm -rf "$target_dir"
  fi

  print_info "Restaurando backup en instance-${id} ..."
  tar -xzf "$backup_file" -C "$INSTANCES_DIR"
  local extracted; extracted=$(tar -tzf "$backup_file" | head -n1 | cut -d/ -f1)
  if [[ "$extracted" != "instance-${id}" && -d "${INSTANCES_DIR}/${extracted}" ]]; then
    mv "${INSTANCES_DIR}/${extracted}" "$target_dir"
  fi

  # Regenerate compose in case paths changed
  local tz="UTC"
  [[ -f "${CLUSTER_DIR}/.env" ]] && tz=$(grep '^TZ=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "UTC")
  local headless="yes"
  [[ -f "${CLUSTER_DIR}/.env" ]] && headless=$(grep '^HEADLESS=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "yes")

  local h="$headless"
  [[ "$h" == "yes" ]] && h="1" || h="0"
  local gport; gport=$(instance_gateway_port "$id")
  local bport; bport=$(instance_bridge_port "$id")
  local token; token=$(generate_token)

  echo "OPENCLAW_GATEWAY_TOKEN=${token}" > "${target_dir}/.env"
  sed -i.bak 's/"token": "[^"]*"/"token": "'"${token}"'"/' \
    "${target_dir}/config/openclaw.json" && rm -f "${target_dir}/config/openclaw.json.bak"

  sed \
    -e "s|{{INSTANCE_ID}}|${id}|g" \
    -e "s|{{INSTANCE_NAME}}|instance-${id}|g" \
    -e "s|{{GATEWAY_PORT}}|${gport}|g" \
    -e "s|{{BRIDGE_PORT}}|${bport}|g" \
    -e "s|{{NETWORK_NAME}}|oc-net-${id}|g" \
    -e "s|{{CONFIG_DIR}}|${target_dir}/config|g" \
    -e "s|{{WORKSPACE_DIR}}|${target_dir}/workspace|g" \
    -e "s|{{HOME_DIR}}|${target_dir}/home|g" \
    -e "s|{{GATEWAY_TOKEN}}|${token}|g" \
    -e "s|{{TZ}}|${tz}|g" \
    -e "s|{{BROWSER_HEADLESS}}|${h}|g" \
    "$TEMPLATE_FILE" > "${target_dir}/docker-compose.yml"

  chown -R 1000:1000 "${target_dir}/config" "${target_dir}/workspace" "${target_dir}/home" 2>/dev/null || true

  print_success "Restauración completada en instance-${id}."
}
