#!/usr/bin/env bash
# lib/destroy.sh — Tear down instances and (optionally) their data, or nuke
# the whole cluster. Both functions gate on check_docker and prompt for
# strong confirmation.

if [[ -n "${__LIB_DESTROY_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_DESTROY_SOURCED=1

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
# cluster_destroy <id>
# Stops a single instance's container. Optionally removes the persistent
# data tree (config/workspace/home).
# ----------------------------------------------------------------------------
cluster_destroy() {
  check_docker
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia a destruir")
  fi

  local name
  name=$(instance_name "$id")
  local dir
  dir=$(instance_dir "$id")

  if [[ ! -d "$dir" ]]; then
    print_error "Instancia ${id} no existe."
    return 1
  fi

  echo ""
  print_warn "Vas a destruir PERMANENTEMENTE ${name}"
  if ! read_confirm_strong "¿Estás seguro?" "DESTRUIR-${name}"; then
    print_info "Cancelado."
    return 0
  fi

  print_info "Eliminando contenedores de ${name} ..."
  docker compose -f "${dir}/docker-compose.yml" down --remove-orphans 2>/dev/null || true

  local delete_data="no"
  if read_confirm "¿Eliminar también datos persistentes (config/workspace/home)?"; then
    delete_data="yes"
  fi

  if [[ "$delete_data" == "yes" ]]; then
    print_info "Eliminando datos de ${name} ..."
    rm -rf "$dir"
    print_success "${name} y sus datos fueron eliminados."
  else
    print_success "${name} detenida. Datos preservados en: ${dir}"
  fi
}

# ----------------------------------------------------------------------------
# cluster_clean_all
# Nuclear option: stop + remove ALL instance containers, the instances
# directory, the cluster .env, and the built docker image. Requires typing
# "NUCLEAR" to confirm.
# ----------------------------------------------------------------------------
cluster_clean_all() {
  check_docker
  echo ""
  print_warn "Esto destruirá TODAS las instancias, imágenes y datos del cluster."
  if ! read_confirm_strong "¿Confirmas?" "NUCLEAR"; then
    print_info "Cancelado."
    return 0
  fi

  local ids=()
  local id
  for id in $(get_instance_ids); do
    [[ -n "$id" ]] && ids+=("$id")
  done
  for id in ${ids[@]+"${ids[@]}"}; do
    print_info "Destruyendo instance-${id} ..."
    docker compose -f "$(instance_dir "$id")/docker-compose.yml" down --remove-orphans -v 2>/dev/null || true
  done

  print_info "Eliminando directorio de instancias ..."
  rm -rf "$INSTANCES_DIR"

  print_info "Eliminando imagen Docker ${IMAGE_NAME} ..."
  docker rmi "${IMAGE_NAME}:latest" 2>/dev/null || true

  rm -f "${CLUSTER_DIR}/.env"

  print_success "Cluster limpiado completamente."
}
