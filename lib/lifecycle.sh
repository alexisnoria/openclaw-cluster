#!/usr/bin/env bash
# lib/lifecycle.sh — High-level lifecycle: cluster_init (build + create),
# _create_instance (FS + config writers), and the cluster_<verb> wrappers
# (start / stop / restart). All FS-touching; the only docker calls are
# inside cluster_init (build) and the start/stop/restart wrappers (compose).
#
# Source from openclaw-cluster.sh or any lib/*.sh. Idempotent.
#
# Provides:
#   - _create_instance     <id> <headless> <tz> <key> <model> [<tg_token>] [<tg_pol>]
#   - cluster_init         [count] [tag] [chrome] [headless] [tz] [key] [model] [tg] [pol]
#   - cluster_start        [target]
#   - cluster_stop         [target]
#   - cluster_restart      <id>
#   - _resolve_targets     <target> [prompt]
#   - _resolve_target_ids  <target>

if [[ -n "${__LIB_LIFECYCLE_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_LIFECYCLE_SOURCED=1

# ---- load dependencies (idempotent) ---------------------------------------
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
if [[ -z "${__LIB_TEMPLATE_SOURCED:-}" ]]; then
  # shellcheck source=lib/template.sh
  # shellcheck disable=SC1090
  source "${_LIB_DIR}/template.sh"
fi

# ---- configuration variables (overridable from env) -----------------------
# Defaults mirror openclaw-cluster.sh v1.1.0.
IMAGE_NAME="${IMAGE_NAME:-openclaw-cluster}"
DOCKERFILE="${DOCKERFILE:-${CLUSTER_DIR:-./}/Dockerfile.openclaw-chrome}"
TEMPLATE_FILE="${TEMPLATE_FILE:-${CLUSTER_DIR:-./}/docker-compose.template.yml}"
CLUSTER_DIR="${CLUSTER_DIR:-$(pwd)}"

# ---- target resolution (duplicated here so lifecycle.sh is self-contained
#      for PR #7; PR #9 will source lib/cluster.sh's version instead) -------

# _resolve_targets <target> [prompt]
_resolve_targets() {
  local target="${1:-}"
  local prompt="${2:-¿Qué instancias?}"

  if [[ -z "$target" ]]; then
    echo "$prompt"
    echo "  [1] Todas las instancias"
    echo "  [2] Una instancia específica"
    echo "  [3] Rango de instancias (ej: 1-5)"
    local choice
    choice=$(read_input "Selecciona" "1")
    case "$choice" in
      1) target="all" ;;
      2) target=$(read_input "Número de instancia") ;;
      3) target="range:$(read_input "Rango (ej: 1-5)")" ;;
      *)
        print_error "Opción inválida"
        return 1
        ;;
    esac
  fi
  printf '%s' "$target"
}

# _resolve_target_ids <target>
_resolve_target_ids() {
  local target="$1"
  shift || true
  if [[ "$target" == "all" ]]; then
    local id
    for id in $(get_instance_ids); do
      [[ -n "$id" ]] && echo "$id"
    done
  elif [[ "$target" == range:* ]]; then
    local range="${target#range:}"
    local start_r="${range%%-*}"
    local end_r="${range##*-}"
    local i
    for i in $(seq "$start_r" "$end_r"); do
      echo "$i"
    done
  else
    echo "$target"
  fi
}

# ---- _create_instance: pure FS operation ----------------------------------
#
# Creates instance-N directory tree, writes all 4 config files using
# lib/template.sh, and renders the docker-compose.yml from the template.
# No docker, no network. Fully unit-testable.
#
# Args:
#   $1 id
#   $2 headless (yes|no)
#   $3 tz
#   $4 openrouter_api_key
#   $5 openrouter_model
#   $6 telegram_bot_token (optional, default "")
#   $7 telegram_dm_policy (optional, default "pairing")
_create_instance() {
  local id="$1"
  local headless="$2"
  local tz="$3"
  local openrouter_api_key="$4"
  local openrouter_model="$5"
  local telegram_bot_token="${6:-}"
  local telegram_dm_policy="${7:-pairing}"

  local name
  name=$(instance_name "$id")
  local dir
  dir=$(instance_dir "$id")
  local gport
  gport=$(instance_gateway_port "$id")
  local bport
  bport=$(instance_bridge_port "$id")
  local token
  token=$(generate_token)

  print_info "Creando ${name} (puertos ${gport}/${bport}) ..."

  mkdir -p "${dir}/config" "${dir}/workspace" "${dir}/home"
  mkdir -p "${dir}/config/agents/main/agent"

  # chown for node user (uid 1000) — best-effort, may fail in non-root sandbox
  chown -R 1000:1000 "${dir}/config" "${dir}/workspace" "${dir}/home" 2>/dev/null || true

  # Write openclaw.json (using lib/template.sh)
  gen_openclaw_json \
    "${dir}/config/openclaw.json" \
    "$gport" "$openrouter_api_key" "$openrouter_model" \
    "$headless" "$telegram_bot_token" "$telegram_dm_policy"

  # Inject the real token (gen_openclaw_json uses PLACEHOLDER_TOKEN)
  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp=$(mktemp)
    jq --arg t "$token" '.gateway.auth.token = $t' \
      "${dir}/config/openclaw.json" >"$tmp" && mv "$tmp" "${dir}/config/openclaw.json"
  else
    # Fallback: in-place sed (matches v1.1.0 when jq is unavailable)
    sed -i.bak "s|\"token\": \"PLACEHOLDER_TOKEN\"|\"token\": \"${token}\"|" \
      "${dir}/config/openclaw.json" && rm -f "${dir}/config/openclaw.json.bak"
  fi

  # Write auth-profiles.json
  gen_auth_profiles "${dir}/config/agents/main/agent/auth-profiles.json" "$openrouter_api_key"

  # Write auth-state.json (lastUsed = now in ms)
  local last_used_ms
  last_used_ms=$(($(date +%s) * 1000))
  gen_auth_state "${dir}/config/agents/main/agent/auth-state.json" "$last_used_ms"

  # Write models.json
  gen_models_json "${dir}/config/agents/main/agent/models.json" "$openrouter_model"

  # Write .env
  gen_instance_env "${dir}/.env" "$token" "$tz"

  # Write docker-compose.yml from template
  local h="$headless"
  [[ "$h" == "yes" ]] && h="1" || h="0"
  render_compose "$TEMPLATE_FILE" "${dir}/docker-compose.yml" \
    INSTANCE_ID="$id" \
    INSTANCE_NAME="$name" \
    GATEWAY_PORT="$gport" \
    BRIDGE_PORT="$bport" \
    NETWORK_NAME="oc-net-${id}" \
    CONFIG_DIR="${dir}/config" \
    WORKSPACE_DIR="${dir}/workspace" \
    HOME_DIR="${dir}/home" \
    GATEWAY_TOKEN="$token" \
    TZ="$tz" \
    BROWSER_HEADLESS="$h"

  print_success "${name} creada → Gateway: http://localhost:${gport}"
}

# ---- cluster_init: build image + create N instances -----------------------
#
# The v1.1.0 cluster_init is a large function that:
#   1. Reads 9 args (with interactive prompts as fallback)
#   2. Writes cluster-level .env
#   3. docker build
#   4. Calls _create_instance N times
#
# We keep the same signature and behavior, but route through lib/* modules.
cluster_init() {
  check_docker
  print_header

  local count tag chrome headless tz openrouter_api_key openrouter_model telegram_bot_token telegram_dm_policy
  count="${1:-}"
  tag="${2:-}"
  chrome="${3:-}"
  headless="${4:-}"
  tz="${5:-}"
  openrouter_api_key="${6:-}"
  openrouter_model="${7:-}"
  telegram_bot_token="${8:-}"
  telegram_dm_policy="${9:-}"

  if [[ -z "$count" ]]; then
    count=$(read_input "¿Cuántas instancias deseas crear? (1-50)" "1")
  fi
  if ! validate_number "$count" || [[ "$count" -lt 1 || "$count" -gt 50 ]]; then
    print_error "Número inválido. Debe ser entre 1 y 50."
    return 1
  fi

  if [[ -z "$tag" ]]; then
    tag=$(read_input "¿Qué versión/tag de OpenClaw?" "latest")
  fi
  if [[ -z "$chrome" ]]; then
    if read_confirm "¿Incluir Google Chrome en la imagen?"; then
      chrome="yes"
    else
      chrome="no"
    fi
  fi
  if [[ -z "$headless" ]]; then
    if read_confirm "¿Modo headless por defecto para el navegador?"; then
      headless="yes"
    else
      headless="no"
    fi
  fi

  if [[ -z "$tz" ]]; then
    tz=$(read_input "Zona horaria (TZ)" "UTC")
  fi

  if [[ -z "$openrouter_api_key" ]]; then
    openrouter_api_key=$(read_input "OpenRouter API Key")
  fi
  if [[ -z "$openrouter_model" ]]; then
    openrouter_model=$(read_input "Modelo por defecto (OpenRouter)" "openrouter/deepseek/deepseek-v4-pro")
  fi

  if [[ -z "$telegram_bot_token" ]]; then
    telegram_bot_token=$(read_input "Token de Telegram Bot (de @BotFather)" "")
  fi
  if [[ -z "$telegram_dm_policy" ]]; then
    telegram_dm_policy=$(read_input "DM Policy (pairing/allowlist/open)" "pairing")
  fi

  print_info "Creando cluster en: ${CLUSTER_DIR}"
  mkdir -p "${INSTANCES_DIR}"

  # Save cluster metadata
  cat >"${CLUSTER_DIR}/.env" <<EOF
TAG=${tag}
CHROME=${chrome}
HEADLESS=${headless}
TZ=${tz}
OPENROUTER_API_KEY=${openrouter_api_key}
OPENROUTER_MODEL=${openrouter_model}
TELEGRAM_BOT_TOKEN=${telegram_bot_token}
TELEGRAM_DM_POLICY=${telegram_dm_policy}
CREATED=$(date -Iseconds)
EOF

  # Build image
  print_info "Construyendo imagen Docker: ${IMAGE_NAME}:${tag} ..."
  local build_args=()
  build_args+=(--build-arg "OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:${tag}")
  if ! docker build -t "${IMAGE_NAME}:${tag}" -t "${IMAGE_NAME}:latest" \
    "${build_args[@]}" -f "$DOCKERFILE" "$CLUSTER_DIR"; then
    print_error "Falló el build de la imagen Docker."
    return 1
  fi
  print_success "Imagen construida: ${IMAGE_NAME}:${tag}"

  # Create instances
  local i
  for i in $(seq 1 "$count"); do
    _create_instance "$i" "$headless" "$tz" "$openrouter_api_key" \
      "$openrouter_model" "$telegram_bot_token" "$telegram_dm_policy"
  done

  print_success "Cluster inicializado con ${count} instancia(s)."
  echo ""
  print_info "Usa 'Iniciar Instancias' en el menú para levantarlas."
}

# ---- cluster_start / cluster_stop / cluster_restart ----------------------
cluster_start() {
  check_docker
  local target
  target=$(_resolve_targets "${1:-}" "¿Qué deseas iniciar?") || return 1

  local id
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if [[ -d "$(instance_dir "$id")" ]]; then
      print_info "Iniciando instance-${id} ..."
      instance_compose "$id" up -d openclaw-gateway || print_warn "Falló inicio de instance-${id}"
    else
      print_warn "Instancia ${id} no existe, omitiendo."
    fi
  done < <(_resolve_target_ids "$target")
}

cluster_stop() {
  check_docker
  local target
  target=$(_resolve_targets "${1:-}" "¿Qué deseas detener?") || return 1

  local id
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if [[ -d "$(instance_dir "$id")" ]]; then
      print_info "Deteniendo instance-${id} ..."
      instance_compose "$id" down || print_warn "Falló detener instance-${id}"
    fi
  done < <(_resolve_target_ids "$target")
}

cluster_restart() {
  check_docker
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia a reiniciar")
  fi
  print_info "Reiniciando instance-${id} ..."
  instance_compose "$id" restart openclaw-gateway
}

# ---- cluster_update: pull + rebuild + recreate ---------------------------
cluster_update() {
  check_docker
  print_info "Actualizando imagen de OpenClaw..."

  local tag="latest"
  if [[ -f "${CLUSTER_DIR}/.env" ]]; then
    tag=$(grep '^TAG=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "latest")
  fi

  tag=$(read_input "Tag a descargar/rebuild" "$tag")

  print_info "Descargando ghcr.io/openclaw/openclaw:${tag} ..."
  docker pull "ghcr.io/openclaw/openclaw:${tag}" || print_warn "No se pudo hacer pull (puede ser normal si usas local)"

  print_info "Reconstruyendo imagen cluster..."
  if ! docker build -t "${IMAGE_NAME}:${tag}" -t "${IMAGE_NAME}:latest" \
    --build-arg "OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:${tag}" \
    -f "$DOCKERFILE" "$CLUSTER_DIR"; then
    print_error "Falló el rebuild."
    return 1
  fi

  # Update meta
  sed -i.bak "s/^TAG=.*/TAG=${tag}/" "${CLUSTER_DIR}/.env" && rm -f "${CLUSTER_DIR}/.env.bak"

  local ids=()
  local id
  for id in $(get_instance_ids); do
    [[ -n "$id" ]] && ids+=("$id")
  done
  for id in ${ids[@]+"${ids[@]}"}; do
    print_info "Recreando instance-${id} con nueva imagen..."
    instance_compose "$id" up -d --force-recreate openclaw-gateway || print_warn "Falló recrear instance-${id}"
  done

  print_success "Actualización completada."
}

# ---- cluster_scale: +N (create) or -N (destroy) --------------------------
# Reuses _create_instance from this lib for additions; calls docker compose
# down + rm -rf for removals. Reads defaults from cluster .env.
cluster_scale() {
  local current
  current=$(get_instance_count)
  print_info "Instancias actuales: ${current}"

  local action
  action=$(read_input "¿Agregar (+N) o Eliminar (-N) instancias? (ej: +3 o -2)")

  if [[ "$action" =~ ^\+([0-9]+)$ ]]; then
    local add="${BASH_REMATCH[1]}"
    local headless tz openrouter_api_key openrouter_model telegram_bot_token telegram_dm_policy
    headless="yes"
    tz="UTC"
    openrouter_api_key=""
    openrouter_model="openrouter/deepseek/deepseek-v4-pro"
    telegram_bot_token=""
    telegram_dm_policy="pairing"
    if [[ -f "${CLUSTER_DIR}/.env" ]]; then
      headless=$(grep '^HEADLESS=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "yes")
      tz=$(grep '^TZ=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "UTC")
      openrouter_api_key=$(grep '^OPENROUTER_API_KEY=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "")
      openrouter_model=$(grep '^OPENROUTER_MODEL=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "openrouter/deepseek/deepseek-v4-pro")
      telegram_bot_token=$(grep '^TELEGRAM_BOT_TOKEN=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "")
      telegram_dm_policy=$(grep '^TELEGRAM_DM_POLICY=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "pairing")
    fi
    local start_id=$((current + 1))
    local end_id=$((current + add))
    local i
    for i in $(seq "$start_id" "$end_id"); do
      _create_instance "$i" "$headless" "$tz" "$openrouter_api_key" \
        "$openrouter_model" "$telegram_bot_token" "$telegram_dm_policy"
    done
    print_success "Escalado completado. Total instancias: ${end_id}"

  elif [[ "$action" =~ ^-([0-9]+)$ ]]; then
    local rem="${BASH_REMATCH[1]}"
    if [[ "$rem" -gt "$current" ]]; then
      print_error "No puedes eliminar más instancias de las existentes (${current})."
      return 1
    fi
    local start_id=$((current - rem + 1))
    local i
    for i in $(seq "$start_id" "$current"); do
      print_info "Eliminando instance-${i} ..."
      docker compose -f "$(instance_dir "$i")/docker-compose.yml" down --remove-orphans 2>/dev/null || true
      rm -rf "$(instance_dir "$i")"
    done
    print_success "Escalado completado. Total instancias: $((current - rem))"
  else
    print_error "Formato inválido. Usa +N o -N."
    return 1
  fi
}
