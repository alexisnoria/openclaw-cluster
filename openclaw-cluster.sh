#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OpenClaw Cluster Manager
# Multi-instance Docker orchestrator for OpenClaw with Google Chrome
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="${SCRIPT_DIR}"
INSTANCES_DIR="${CLUSTER_DIR}/instances"
TEMPLATE_FILE="${CLUSTER_DIR}/docker-compose.template.yml"
DOCKERFILE="${CLUSTER_DIR}/Dockerfile.openclaw-chrome"
IMAGE_NAME="openclaw-cluster"
BASE_PORT=18000

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------
CLR_RESET='\033[0m'
CLR_BOLD='\033[1m'
CLR_DIM='\033[2m'
CLR_GREEN='\033[0;32m'
CLR_YELLOW='\033[1;33m'
CLR_BLUE='\033[0;34m'
CLR_MAGENTA='\033[0;35m'
CLR_CYAN='\033[0;36m'
CLR_RED='\033[0;31m'
CLR_ORANGE='\033[38;5;208m'

print_header() {
  echo -e "${CLR_ORANGE}${CLR_BOLD}"
  echo '╔══════════════════════════════════════════════════════════╗'
  echo '║        🦞 OpenClaw Cluster Manager v1.0                  ║'
  echo '╚══════════════════════════════════════════════════════════╝'
  echo -e "${CLR_RESET}"
}

print_success() { echo -e "${CLR_GREEN}✅ $1${CLR_RESET}"; }
print_info()    { echo -e "${CLR_BLUE}ℹ️  $1${CLR_RESET}"; }
print_warn()    { echo -e "${CLR_YELLOW}⚠️  $1${CLR_RESET}"; }
print_error()   { echo -e "${CLR_RED}❌ $1${CLR_RESET}" >&2; }
print_cmd()     { echo -e "${CLR_CYAN}${CLR_BOLD}$1${CLR_RESET}"; }

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
require_command() {
  if ! command -v "$1" &>/dev/null; then
    print_error "Requerido pero no encontrado: $1"
    exit 1
  fi
}

check_docker() {
  require_command docker
  if ! docker info &>/dev/null; then
    print_error "Docker no está corriendo o no tienes permisos."
    exit 1
  fi
}

validate_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_range() {
  [[ "$1" =~ ^[0-9]+-[0-9]+$ ]]
}

read_input() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    echo -en "${CLR_CYAN}${prompt} [${default}]: ${CLR_RESET}" >&2
  else
    echo -en "${CLR_CYAN}${prompt}: ${CLR_RESET}" >&2
  fi
  read -r value
  echo "${value:-$default}"
}

read_confirm() {
  local prompt="$1"
  local value
  echo -en "${CLR_YELLOW}${prompt} [y/N]: ${CLR_RESET}" >&2
  read -r value
  [[ "$value" =~ ^[Yy]$ ]]
}

read_confirm_strong() {
  local prompt="$1"
  local confirm_word="$2"
  local value
  echo -en "${CLR_RED}${prompt} Escribe '${confirm_word}' para confirmar: ${CLR_RESET}" >&2
  read -r value
  [[ "$value" == "$confirm_word" ]]
}

instance_gateway_port() {
  echo $(( BASE_PORT + ($1 * 22) ))
}

instance_bridge_port() {
  echo $(( BASE_PORT + ($1 * 22) + 1 ))
}

instance_name() {
  echo "instance-$1"
}

instance_dir() {
  echo "${INSTANCES_DIR}/instance-$1"
}

generate_token() {
  openssl rand -hex 32
}

get_instance_count() {
  if [[ -d "$INSTANCES_DIR" ]]; then
    find "$INSTANCES_DIR" -maxdepth 1 -type d -name 'instance-*' | wc -l | tr -d ' '
  else
    echo 0
  fi
}

get_instance_ids() {
  if [[ -d "$INSTANCES_DIR" ]]; then
    find "$INSTANCES_DIR" -maxdepth 1 -type d -name 'instance-*' | sort -V | sed 's/.*instance-//' | grep -E '^[0-9]+$' | tr '\n' ' '
  fi
}

# ------------------------------------------------------------------------------
# Initialization
# ------------------------------------------------------------------------------
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
  mkdir -p "$INSTANCES_DIR"

  # Save cluster metadata
  cat > "${CLUSTER_DIR}/.env" <<EOF
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
  if ! docker build -t "${IMAGE_NAME}:${tag}" -t "${IMAGE_NAME}:latest" "${build_args[@]}" -f "$DOCKERFILE" "$CLUSTER_DIR"; then
    print_error "Falló el build de la imagen Docker."
    return 1
  fi
  print_success "Imagen construida: ${IMAGE_NAME}:${tag}"

  # Create instances
  local i
  for i in $(seq 1 "$count"); do
    _create_instance "$i" "$headless" "$tz" "$openrouter_api_key" "$openrouter_model" "$telegram_bot_token" "$telegram_dm_policy"
  done

  print_success "Cluster inicializado con ${count} instancia(s)."
  echo ""
  print_info "Usa 'Iniciar Instancias' en el menú para levantarlas."
}

_create_instance() {
  local id="$1"
  local headless="$2"
  local tz="$3"
  local openrouter_api_key="$4"
  local openrouter_model="$5"
  local telegram_bot_token="${6:-}"
  local telegram_dm_policy="${7:-pairing}"
  local name; name=$(instance_name "$id")
  local dir; dir=$(instance_dir "$id")
  local gport; gport=$(instance_gateway_port "$id")
  local bport; bport=$(instance_bridge_port "$id")
  local token; token=$(generate_token)

  print_info "Creando ${name} (puertos ${gport}/${bport}) ..."

  mkdir -p "${dir}/config" "${dir}/workspace" "${dir}/home"
  mkdir -p "${dir}/config/agents/main/agent"

  # chown for node user (uid 1000)
  chown -R 1000:1000 "${dir}/config" "${dir}/workspace" "${dir}/home" 2>/dev/null || true

  # Normalize headless to JSON boolean
  local headless_bool="false"
  [[ "$headless" == "yes" ]] && headless_bool="true"

  local tg_env_block=""
  local tg_channels_block=""
  if [[ -n "$telegram_bot_token" ]]; then
    tg_env_block=',"TELEGRAM_BOT_TOKEN": "'"${telegram_bot_token}"'"'
    tg_channels_block=',

  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "'"${telegram_bot_token}"'",
      "dmPolicy": "'"${telegram_dm_policy}"'"
    }
  }'
  fi

  # Generate openclaw.json
  cat > "${dir}/config/openclaw.json" <<EOF
{
  "env": {
    "OPENROUTER_API_KEY": "${openrouter_api_key}"${tg_env_block}
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${openrouter_model}"
      },
      "workspace": "/home/node/.openclaw/workspace",
      "models": {
        "${openrouter_model}": {
          "alias": "OpenRouter"
        }
      }
    }
  },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "token": "${token}"
    },
    "controlUi": {
      "allowedOrigins": ["http://localhost:${gport}", "http://127.0.0.1:${gport}"]
    }
  },
  "browser": {
    "enabled": true,
    "executablePath": "/usr/bin/google-chrome",
    "headless": ${headless_bool},
    "defaultProfile": "openclaw",
    "profiles": {
      "openclaw": {
        "cdpPort": 18800,
        "color": "#FF4500"
      }
    }
  },
  "plugins": {
    "entries": {
      "openai": {
        "enabled": true
      },
      "browser": {
        "enabled": true
      },
      "openrouter": {
        "enabled": true
      },
      "duckduckgo": {
        "enabled": true
      }
    }
  },
  "auth": {
    "profiles": {
      "openrouter:default": {
        "provider": "openrouter",
        "mode": "api_key"
      }
    }
  }${tg_channels_block}
}
EOF

  # Generate auth-profiles.json
  cat > "${dir}/config/agents/main/agent/auth-profiles.json" <<EOF
{
  "version": 1,
  "profiles": {
    "openrouter:default": {
      "type": "api_key",
      "provider": "openrouter",
      "key": "${openrouter_api_key}"
    }
  }
}
EOF

  # Generate auth-state.json
  cat > "${dir}/config/agents/main/agent/auth-state.json" <<EOF
{
  "version": 1,
  "lastGood": {
    "openrouter": "openrouter:default"
  },
  "usageStats": {
    "openrouter:default": {
      "errorCount": 0,
      "lastUsed": $(date +%s)000
    }
  }
}
EOF

  # Generate models.json
  cat > "${dir}/config/agents/main/agent/models.json" <<EOF
{
  "providers": {
    "openrouter": {
      "baseUrl": "https://openrouter.ai/api/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "${openrouter_model#openrouter/}",
          "name": "OpenRouter Default",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": {
            "input": 0,
            "output": 0
          },
          "contextWindow": 200000,
          "maxTokens": 8192
        }
      ],
      "apiKey": "OPENROUTER_API_KEY"
    }
  }
}
EOF

  # Generate .env
  cat > "${dir}/.env" <<EOF
OPENCLAW_GATEWAY_TOKEN=${token}
OPENCLAW_TZ=${tz}
EOF

  # Generate docker-compose.yml from template
  local h; h="${headless}"
  [[ "$h" == "yes" ]] && h="1" || h="0"

  sed \
    -e "s|{{INSTANCE_ID}}|${id}|g" \
    -e "s|{{INSTANCE_NAME}}|${name}|g" \
    -e "s|{{GATEWAY_PORT}}|${gport}|g" \
    -e "s|{{BRIDGE_PORT}}|${bport}|g" \
    -e "s|{{NETWORK_NAME}}|oc-net-${id}|g" \
    -e "s|{{CONFIG_DIR}}|${dir}/config|g" \
    -e "s|{{WORKSPACE_DIR}}|${dir}/workspace|g" \
    -e "s|{{HOME_DIR}}|${dir}/home|g" \
    -e "s|{{GATEWAY_TOKEN}}|${token}|g" \
    -e "s|{{TZ}}|${tz}|g" \
    -e "s|{{BROWSER_HEADLESS}}|${h}|g" \
    "$TEMPLATE_FILE" > "${dir}/docker-compose.yml"

  print_success "${name} creada → Gateway: http://localhost:${gport}"
}

# ------------------------------------------------------------------------------
# Start / Stop / Restart
# ------------------------------------------------------------------------------
instance_compose() {
  local id="$1"
  shift
  local dir; dir=$(instance_dir "$id")
  if [[ ! -f "${dir}/docker-compose.yml" ]]; then
    print_error "Instancia ${id} no existe."
    return 1
  fi
  docker compose -f "${dir}/docker-compose.yml" "$@"
}

cluster_start() {
  check_docker
  local target="${1:-}"

  if [[ -z "$target" ]]; then
    echo "¿Qué deseas iniciar?"
    echo "  [1] Todas las instancias"
    echo "  [2] Una instancia específica"
    echo "  [3] Rango de instancias (ej: 1-5)"
    local choice
    choice=$(read_input "Selecciona" "1")
    case "$choice" in
      1) target="all" ;;
      2) target=$(read_input "Número de instancia"); target="${target}" ;;
      3) target=$(read_input "Rango (ej: 1-5)"); target="range:${target}" ;;
      *) print_error "Opción inválida"; return 1 ;;
    esac
  fi

  local ids=()
  if [[ "$target" == "all" ]]; then
    for id in $(get_instance_ids); do
      [[ -n "$id" ]] && ids+=("$id")
    done
  elif [[ "$target" == range:* ]]; then
    local range="${target#range:}"
    local start_r end_r
    start_r="${range%%-*}"
    end_r="${range##*-}"
    for i in $(seq "$start_r" "$end_r"); do
      ids+=("$i")
    done
  else
    ids+=("$target")
  fi

  for id in ${ids[@]+"${ids[@]}"}; do
    if [[ -d "$(instance_dir "$id")" ]]; then
      print_info "Iniciando instance-${id} ..."
      instance_compose "$id" up -d openclaw-gateway || print_warn "Falló inicio de instance-${id}"
    else
      print_warn "Instancia ${id} no existe, omitiendo."
    fi
  done
}

cluster_stop() {
  check_docker
  local target="${1:-}"

  if [[ -z "$target" ]]; then
    echo "¿Qué deseas detener?"
    echo "  [1] Todas las instancias"
    echo "  [2] Una instancia específica"
    echo "  [3] Rango de instancias"
    local choice
    choice=$(read_input "Selecciona" "1")
    case "$choice" in
      1) target="all" ;;
      2) target=$(read_input "Número de instancia"); target="${target}" ;;
      3) target=$(read_input "Rango (ej: 1-5)"); target="range:${target}" ;;
      *) print_error "Opción inválida"; return 1 ;;
    esac
  fi

  local ids=()
  if [[ "$target" == "all" ]]; then
    for id in $(get_instance_ids); do
      [[ -n "$id" ]] && ids+=("$id")
    done
  elif [[ "$target" == range:* ]]; then
    local range="${target#range:}"
    local start_r end_r
    start_r="${range%%-*}"
    end_r="${range##*-}"
    for i in $(seq "$start_r" "$end_r"); do
      ids+=("$i")
    done
  else
    ids+=("$target")
  fi

  for id in "${ids[@]}"; do
    if [[ -d "$(instance_dir "$id")" ]]; then
      print_info "Deteniendo instance-${id} ..."
      instance_compose "$id" down || print_warn "Falló detener instance-${id}"
    fi
  done
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

# ------------------------------------------------------------------------------
# Status
# ------------------------------------------------------------------------------
cluster_status() {
  check_docker
  local ids=()
  for id in $(get_instance_ids); do
    [[ -n "$id" ]] && ids+=("$id")
  done

  if [[ ${#ids[@]} -eq 0 ]]; then
    print_warn "No hay instancias creadas."
    return
  fi

  echo ""
  printf "${CLR_BOLD}┌──────────┬────────┬──────────────────────┬─────────────┬─────────────┐${CLR_RESET}\n"
  printf "${CLR_BOLD}│ %-8s │ %-6s │ %-20s │ %-11s │ %-11s │${CLR_RESET}\n" "Instancia" "Estado" "Gateway URL" "Puertos" "Uptime"
  printf "${CLR_BOLD}├──────────┼────────┼──────────────────────┼─────────────┼─────────────┤${CLR_RESET}\n"

  for id in "${ids[@]}"; do
    local name; name=$(instance_name "$id")
    local gport; gport=$(instance_gateway_port "$id")
    local bport; bport=$(instance_bridge_port "$id")
    local container="${name}-gateway"
    local state emoji uptime url health

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

    printf "│ %-8s │ %-6s │ %-20s │ %5s/%5s │ %-11s │\n" "${name}" "${emoji} ${state}" "$url" "$gport" "$bport" "$uptime"
  done
  printf "${CLR_BOLD}└──────────┴────────┴──────────────────────┴─────────────┴─────────────┘${CLR_RESET}\n"
  echo ""
}

# ------------------------------------------------------------------------------
# Logs
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# Exec
# ------------------------------------------------------------------------------
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
  docker compose -f "$(instance_dir "$id")/docker-compose.yml" exec openclaw-gateway bash -lc "${cmd}"
}

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
cluster_config() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia a configurar")
  fi
  local config_file; config_file="$(instance_dir "$id")/config/openclaw.json"
  if [[ ! -f "$config_file" ]]; then
    print_error "Config no encontrado para instance-${id}"
    return 1
  fi

  echo "Archivo: ${config_file}"
  echo "Abriendo con el editor por defecto... (Ctrl+C para cancelar)"
  ${EDITOR:-nano} "$config_file" || vi "$config_file" || cat "$config_file"
}

# ------------------------------------------------------------------------------
# Destroy
# ------------------------------------------------------------------------------
cluster_destroy() {
  check_docker
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id=$(read_input "Número de instancia a destruir")
  fi

  local name; name=$(instance_name "$id")
  local dir; dir=$(instance_dir "$id")

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

# ------------------------------------------------------------------------------
# Clean All
# ------------------------------------------------------------------------------
cluster_clean_all() {
  check_docker
  echo ""
  print_warn "Esto destruirá TODAS las instancias, imágenes y datos del cluster."
  if ! read_confirm_strong "¿Confirmas?" "NUCLEAR"; then
    print_info "Cancelado."
    return 0
  fi

  local ids=()
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

# ------------------------------------------------------------------------------
# Update Image
# ------------------------------------------------------------------------------
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
  if ! docker build -t "${IMAGE_NAME}:${tag}" -t "${IMAGE_NAME}:latest" --build-arg "OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:${tag}" -f "$DOCKERFILE" "$CLUSTER_DIR"; then
    print_error "Falló el rebuild."
    return 1
  fi

  # Update meta
  sed -i.bak "s/^TAG=.*/TAG=${tag}/" "${CLUSTER_DIR}/.env" && rm -f "${CLUSTER_DIR}/.env.bak"

  local ids=()
  for id in $(get_instance_ids); do
    [[ -n "$id" ]] && ids+=("$id")
  done
  for id in ${ids[@]+"${ids[@]}"}; do
    print_info "Recreando instance-${id} con nueva imagen..."
    instance_compose "$id" up -d --force-recreate openclaw-gateway || print_warn "Falló recrear instance-${id}"
  done

  print_success "Actualización completada."
}

# ------------------------------------------------------------------------------
# Backup / Restore
# ------------------------------------------------------------------------------
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
}

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
    # Stop if running
    docker compose -f "${target_dir}/docker-compose.yml" down 2>/dev/null || true
    rm -rf "$target_dir"
  fi

  print_info "Restaurando backup en instance-${id} ..."
  tar -xzf "$backup_file" -C "$INSTANCES_DIR"
  # Rename if backup had different instance id
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

  # Update token in env and json for freshness
  echo "OPENCLAW_GATEWAY_TOKEN=${token}" > "${target_dir}/.env"
  sed -i.bak 's/"token": "[^"]*"/"token": "'"${token}"'"/' "${target_dir}/config/openclaw.json" && rm -f "${target_dir}/config/openclaw.json.bak"

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

# ------------------------------------------------------------------------------
# Scale
# ------------------------------------------------------------------------------
cluster_scale() {
  local current; current=$(get_instance_count)
  print_info "Instancias actuales: ${current}"

  local action
  action=$(read_input "¿Agregar (+N) o Eliminar (-N) instancias? (ej: +3 o -2)")

  if [[ "$action" =~ ^\+([0-9]+)$ ]]; then
    local add="${BASH_REMATCH[1]}"
    local headless tz openrouter_api_key openrouter_model telegram_bot_token telegram_dm_policy
    headless="yes"; tz="UTC"; openrouter_api_key=""; openrouter_model="openrouter/deepseek/deepseek-v4-pro"; telegram_bot_token=""; telegram_dm_policy="pairing"
    if [[ -f "${CLUSTER_DIR}/.env" ]]; then
      headless=$(grep '^HEADLESS=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "yes")
      tz=$(grep '^TZ=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "UTC")
      openrouter_api_key=$(grep '^OPENROUTER_API_KEY=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "")
      openrouter_model=$(grep '^OPENROUTER_MODEL=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "openrouter/deepseek/deepseek-v4-pro")
      telegram_bot_token=$(grep '^TELEGRAM_BOT_TOKEN=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "")
      telegram_dm_policy=$(grep '^TELEGRAM_DM_POLICY=' "${CLUSTER_DIR}/.env" | cut -d= -f2 || echo "pairing")
    fi
    local start_id=$(( current + 1 ))
    local end_id=$(( current + add ))
    for i in $(seq "$start_id" "$end_id"); do
      _create_instance "$i" "$headless" "$tz" "$openrouter_api_key" "$openrouter_model" "$telegram_bot_token" "$telegram_dm_policy"
    done
    print_success "Escalado completado. Total instancias: ${end_id}"

  elif [[ "$action" =~ ^-([0-9]+)$ ]]; then
    local rem="${BASH_REMATCH[1]}"
    if [[ "$rem" -gt "$current" ]]; then
      print_error "No puedes eliminar más instancias de las existentes (${current})."
      return 1
    fi
    local start_id=$(( current - rem + 1 ))
    for i in $(seq "$start_id" "$current"); do
      print_info "Eliminando instance-${i} ..."
      docker compose -f "$(instance_dir "$i")/docker-compose.yml" down --remove-orphans 2>/dev/null || true
      rm -rf "$(instance_dir "$i")"
    done
    print_success "Escalado completado. Total instancias: $(( current - rem ))"
  else
    print_error "Formato inválido. Usa +N o -N."
    return 1
  fi
}

# ------------------------------------------------------------------------------
# Tokens
# ------------------------------------------------------------------------------
cluster_tokens() {
  local ids=()
  for id in $(get_instance_ids); do
    [[ -n "$id" ]] && ids+=("$id")
  done
  if [[ ${#ids[@]} -eq 0 ]]; then
    print_warn "No hay instancias."
    return
  fi

  echo ""
  printf "${CLR_BOLD}┌──────────┬─────────────┬────────────────────────────────────────┐${CLR_RESET}\n"
  printf "${CLR_BOLD}│ %-8s │ %-11s │ %-38s │${CLR_RESET}\n" "Instancia" "Puerto" "Token (parcial)"
  printf "${CLR_BOLD}├──────────┼─────────────┼────────────────────────────────────────┤${CLR_RESET}\n"

  for id in "${ids[@]}"; do
    local gport; gport=$(instance_gateway_port "$id")
    local env_file; env_file="$(instance_dir "$id")/.env"
    local token="N/A"
    if [[ -f "$env_file" ]]; then
      token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$env_file" | cut -d= -f2 || echo "N/A")
      token="${token:0:16}..."
    fi
    printf "│ %-8s │ %-11s │ %-38s │\n" "instance-${id}" "$gport" "$token"
  done
  printf "${CLR_BOLD}└──────────┴─────────────┴────────────────────────────────────────┘${CLR_RESET}\n"
  echo ""
}

# ------------------------------------------------------------------------------
# Dashboard
# ------------------------------------------------------------------------------
cluster_dashboard() {
  local ids=()
  local running=()

  for id in $(get_instance_ids); do
    [[ -n "$id" ]] && ids+=("$id")
  done
  for id in ${ids[@]+"${ids[@]}"}; do
    local container; container="$(instance_name "$id")-gateway"
    if docker ps --format '{{.Names}}' | grep -qx "$container"; then
      running+=("$id")
    fi
  done

  if [[ ${#running[@]} -eq 0 ]]; then
    print_error "No hay instancias corriendo. Inicia una primero."
    return 1
  fi

  local selected
  if [[ ${#running[@]} -eq 1 ]]; then
    selected="${running[0]}"
  else
    echo "Instancias activas:"
    for id in "${running[@]}"; do
      echo "  [${id}] instance-${id} → http://localhost:$(instance_gateway_port "$id")"
    done
    selected=$(read_input "Selecciona instancia")
  fi

  local gport; gport=$(instance_gateway_port "$selected")
  local url; url="http://localhost:${gport}"

  # Read token from instance .env
  local env_file; env_file="$(instance_dir "$selected")/.env"
  local token=""
  if [[ -f "$env_file" ]]; then
    token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$env_file" | cut -d= -f2 || echo "")
  fi

  echo ""
  print_success "Dashboard Instance-${selected}"
  echo ""
  echo -e "${CLR_BOLD}${CLR_CYAN}URL base:${CLR_RESET} ${url}"
  if [[ -n "$token" ]]; then
    echo -e "${CLR_BOLD}${CLR_GREEN}URL con token (copia y pega):${CLR_RESET}"
    echo -e "${CLR_MAGENTA}${url}/?token=${token}${CLR_RESET}"
  else
    print_warn "Token no encontrado en ${env_file}"
  fi
  echo ""

  if read_confirm "¿Abrir en navegador?"; then
    open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null || echo "Abre manualmente: $url"
  fi
}

# ------------------------------------------------------------------------------
# Set OpenRouter API Key
# ------------------------------------------------------------------------------
cluster_set_openrouter_key() {
  local target="${1:-}"
  local new_key="${2:-}"

  if [[ -z "$target" ]]; then
    echo "¿Qué instancia deseas actualizar?"
    echo "  [a] Todas las instancias"
    echo "  [n] Número de instancia específica"
    local choice
    choice=$(read_input "Opción")
    if [[ "$choice" == "a" ]]; then
      target="all"
    else
      target="$choice"
    fi
  fi

  if [[ -z "$new_key" ]]; then
    new_key=$(read_input "Nueva OpenRouter API Key")
  fi

  if [[ "$target" == "all" ]]; then
    for id in $(get_instance_ids); do
      _update_instance_openrouter_key "$id" "$new_key"
    done
    if [[ -f "${CLUSTER_DIR}/.env" ]]; then
      sed -i "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=${new_key}|" "${CLUSTER_DIR}/.env"
      print_success ".env actualizado"
    fi
  else
    if [[ ! -d "$(instance_dir "$target")" ]]; then
      print_error "Instancia ${target} no existe."
      return 1
    fi
    _update_instance_openrouter_key "$target" "$new_key"
  fi

  print_success "OpenRouter API Key actualizada."
}

_update_instance_openrouter_key() {
  local id="$1"
  local new_key="$2"
  local dir; dir=$(instance_dir "$id")

  local config_file="${dir}/config/openclaw.json"
  if [[ -f "$config_file" ]]; then
    sed -i "s|\"OPENROUTER_API_KEY\": \"[^\"]*\"|\"OPENROUTER_API_KEY\": \"${new_key}\"|" "$config_file"
  fi

  local auth_file="${dir}/config/agents/main/agent/auth-profiles.json"
  if [[ -f "$auth_file" ]]; then
    sed -i "s|\"key\": \"[^\"]*\"|\"key\": \"${new_key}\"|" "$auth_file"
  fi

  print_success "instance-${id} actualizada"
}

# ------------------------------------------------------------------------------
# Set Telegram Configuration
# ------------------------------------------------------------------------------
cluster_set_telegram() {
  local target="${1:-}"
  local bot_token="${2:-}"
  local dm_policy="${3:-}"

  if [[ -z "$target" ]]; then
    echo "¿Qué instancia deseas actualizar?"
    echo "  [a] Todas las instancias"
    echo "  [n] Número de instancia específica"
    local choice
    choice=$(read_input "Opción")
    if [[ "$choice" == "a" ]]; then
      target="all"
    else
      target="$choice"
    fi
  fi

  if [[ -z "$bot_token" ]]; then
    bot_token=$(read_input "Token de Telegram Bot (de @BotFather)" "")
  fi
  if [[ -z "$dm_policy" ]]; then
    dm_policy=$(read_input "DM Policy (pairing/allowlist/open)" "pairing")
  fi

  if [[ "$target" == "all" ]]; then
    for id in $(get_instance_ids); do
      _update_instance_telegram "$id" "$bot_token" "$dm_policy"
    done
    if [[ -f "${CLUSTER_DIR}/.env" ]]; then
      sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${bot_token}|" "${CLUSTER_DIR}/.env"
      sed -i "s|^TELEGRAM_DM_POLICY=.*|TELEGRAM_DM_POLICY=${dm_policy}|" "${CLUSTER_DIR}/.env"
      print_success ".env actualizado"
    fi
  else
    if [[ ! -d "$(instance_dir "$target")" ]]; then
      print_error "Instancia ${target} no existe."
      return 1
    fi
    _update_instance_telegram "$target" "$bot_token" "$dm_policy"
  fi

  print_success "Telegram configurado correctamente."
}

_update_instance_telegram() {
  local id="$1"
  local bot_token="$2"
  local dm_policy="$3"
  local dir; dir=$(instance_dir "$id")
  local config_file="${dir}/config/openclaw.json"

  if [[ ! -f "$config_file" ]]; then
    print_error "openclaw.json no encontrado en instance-${id}"
    return 1
  fi

  # Remove existing "channels" top-level block (count braces)
  awk '
    BEGIN { skip = 0; depth = 0 }
    /^  "channels": \{/ { skip = 1; depth = 1; next }
    skip { if (/{/) depth++; if (/}/) depth--; if (depth == 0) { skip = 0 } next }
    { print }
  ' "$config_file" > "${config_file}.tmp"

  # Remove existing TELEGRAM_BOT_TOKEN line from env
  grep -v '"TELEGRAM_BOT_TOKEN"' "${config_file}.tmp" > "${config_file}.tmp2"
  mv "${config_file}.tmp2" "${config_file}.tmp"

  # Add TELEGRAM_BOT_TOKEN after OPENROUTER_API_KEY
  awk -v tk="$bot_token" '
    /"OPENROUTER_API_KEY"/ { print; print "    \"TELEGRAM_BOT_TOKEN\": \"" tk "\","; next }
    { print }
  ' "${config_file}.tmp" > "${config_file}.tmp2"
  mv "${config_file}.tmp2" "${config_file}.tmp"

  # Insert channels.telegram before closing }
  awk -v tk="$bot_token" -v pol="$dm_policy" '
    /^}$/ {
      print "  \"channels\": {"
      print "    \"telegram\": {"
      print "      \"enabled\": true,"
      print "      \"botToken\": \"" tk "\","
      print "      \"dmPolicy\": \"" pol "\""
      print "    }"
      print "  }"
    }
    { print }
  ' "${config_file}.tmp" > "${config_file}"
  rm -f "${config_file}.tmp"

  print_success "instance-${id} actualizada con Telegram"
}

# ------------------------------------------------------------------------------
# Interactive Menu
# ------------------------------------------------------------------------------
show_menu() {
  print_header

  local active=0 total=0
  if [[ -d "$INSTANCES_DIR" ]]; then
    total=$(get_instance_count)
    local ids=()
    for id in $(get_instance_ids); do
      [[ -n "$id" ]] && ids+=("$id")
    done
    for id in ${ids[@]+"${ids[@]}"}; do
      local c; c="$(instance_name "$id")-gateway"
      docker ps --format '{{.Names}}' | grep -qx "$c" && ((active++)) || true
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

run_interactive() {
  while true; do
    show_menu
    local choice
    choice=$(read_input "Selecciona una opción")

    case "$choice" in
      1)  cluster_init ;;
      2)  cluster_start ;;
      3)  cluster_stop ;;
      4)  cluster_restart ;;
      5)  cluster_status ;;
      6)  cluster_logs ;;
      7)  cluster_exec ;;
      8)  cluster_config ;;
      9)  cluster_destroy ;;
      10) cluster_clean_all ;;
      11) cluster_update ;;
      12) cluster_backup ;;
      13) cluster_restore ;;
      14) cluster_scale ;;
      15) cluster_tokens ;;
      16) cluster_dashboard ;;
      17) cluster_set_openrouter_key ;;
      18) cluster_set_telegram ;;
       0|q|quit|exit)
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

# ------------------------------------------------------------------------------
# Batch Mode
# ------------------------------------------------------------------------------
run_batch() {
  local cmd="$1"
  shift

  case "$cmd" in
    init)     cluster_init "$@" ;;
    start)    cluster_start "$@" ;;
    stop)     cluster_stop "$@" ;;
    restart)  cluster_restart "$@" ;;
    status)   cluster_status "$@" ;;
    logs)     cluster_logs "$@" ;;
    exec)     cluster_exec "$@" ;;
    config)   cluster_config "$@" ;;
    destroy)  cluster_destroy "$@" ;;
    clean)    cluster_clean_all ;;
    update)   cluster_update "$@" ;;
    backup)   cluster_backup "$@" ;;
    restore)  cluster_restore "$@" ;;
    scale)    cluster_scale "$@" ;;
    tokens)   cluster_tokens ;;
    dashboard) cluster_dashboard "$@" ;;
    set-openrouter-key) cluster_set_openrouter_key "$@" ;;
    set-telegram) cluster_set_telegram "$@" ;;
    *)
      print_error "Comando batch desconocido: ${cmd}"
      echo "Uso: $0 [comando] [args...]"
      echo "Comandos:"
      echo "  init [count] [tag] [chrome] [headless] [tz] [openrouter_api_key] [openrouter_model] [telegram_bot_token] [telegram_dm_policy]"
      echo "  set-openrouter-key [instance|all] [new_key]"
      echo "  set-telegram [instance|all] [bot_token] [dm_policy]"
      echo "  start|stop|restart|status|logs|exec|config|destroy|backup|restore|scale|tokens|dashboard"
      exit 1
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
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

main "$@"
