#!/usr/bin/env bash
# lib/instance.sh — Instance discovery, naming, and `docker compose` plumbing.
# Pure helpers plus a small set of FS-touching functions (read-only).
#
# Source from openclaw-cluster.sh or any lib/*.sh. Idempotent.
#
# Provides:
#   - instance_name     <id>                   -> "instance-N"
#   - instance_dir      <id> [<root>]          -> path
#   - instance_gateway_port <id> [<base>]      -> int
#   - instance_bridge_port  <id> [<base>]      -> int
#   - instance_compose_path <id>              -> docker-compose.yml path
#   - generate_token                            -> 64-hex (uses openssl)
#   - get_instance_count                        -> echo integer
#   - get_instance_ids                          -> echoes ids separated by space
#   - require_command <cmd>                     -> die if not on PATH
#   - check_docker                              -> die if daemon not reachable

if [[ -n "${__LIB_INSTANCE_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_INSTANCE_SOURCED=1

# Requires lib/cluster.sh for validate_number, is_safe_token, etc.
if [[ -z "${__LIB_CLUSTER_SOURCED:-}" ]]; then
  # shellcheck source=lib/cluster.sh
  # shellcheck disable=SC1090
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cluster.sh"
fi

# ----------------------------------------------------------------------------
# Path constants
# ----------------------------------------------------------------------------
# These mirror the constants in openclaw-cluster.sh v1.1.0. Refactor-safe:
# callers can override them via env vars before sourcing this file.
INSTANCES_DIR="${INSTANCES_DIR:-${CLUSTER_DIR:-./}/instances}"
BASE_PORT="${BASE_PORT:-18000}"

# ----------------------------------------------------------------------------
# Naming and port helpers (pure)
# ----------------------------------------------------------------------------

# instance_name <id> -> "instance-N"
instance_name() {
  echo "instance-$1"
}

# instance_dir <id> [<root>] -> path
# Default root is $INSTANCES_DIR. Callers can pass a sandbox root for tests.
instance_dir() {
  local id="$1"
  local root="${2:-${INSTANCES_DIR}}"
  echo "${root}/instance-${id}"
}

# instance_compose_path <id> [<root>] -> path to docker-compose.yml
instance_compose_path() {
  local dir
  dir=$(instance_dir "$@")
  echo "${dir}/docker-compose.yml"
}

# instance_gateway_port <id> [<base>] -> echo int
# Stride: 22. Base defaults to $BASE_PORT (18000).
instance_gateway_port() {
  local id="$1"
  local base="${2:-${BASE_PORT}}"
  echo $((base + (id * 22)))
}

# instance_bridge_port <id> [<base>] -> echo int
# Always gateway + 1.
instance_bridge_port() {
  local id="$1"
  local base="${2:-${BASE_PORT}}"
  echo $((base + (id * 22) + 1))
}

# ----------------------------------------------------------------------------
# Token generation (uses openssl, side-effect free)
# ----------------------------------------------------------------------------

# generate_token -> echo 64 hex chars
generate_token() {
  openssl rand -hex 32
}

# ----------------------------------------------------------------------------
# Instance discovery (read-only FS)
# ----------------------------------------------------------------------------

# get_instance_count -> echo int
get_instance_count() {
  if [[ -d "$INSTANCES_DIR" ]]; then
    find "$INSTANCES_DIR" -maxdepth 1 -type d -name 'instance-*' | wc -l | tr -d ' '
  else
    echo 0
  fi
}

# get_instance_ids -> echoes ids sorted numerically, space separated
get_instance_ids() {
  if [[ -d "$INSTANCES_DIR" ]]; then
    find "$INSTANCES_DIR" -maxdepth 1 -type d -name 'instance-*' \
      | sort -V | sed 's/.*instance-//' | grep -E '^[0-9]+$' | tr '\n' ' '
  fi
}

# get_instance_ids_nl -> same as get_instance_ids but newline-separated
get_instance_ids_nl() {
  if [[ -d "$INSTANCES_DIR" ]]; then
    find "$INSTANCES_DIR" -maxdepth 1 -type d -name 'instance-*' \
      | sort -V | sed 's/.*instance-//' | grep -E '^[0-9]+$'
  fi
}

# get_highest_instance_id -> echo int, or 0 if none
get_highest_instance_id() {
  local ids
  ids=$(get_instance_ids_nl)
  if [[ -z "$ids" ]]; then
    echo 0
    return
  fi
  # Last id in the sorted list is the highest
  echo "$ids" | tail -n 1
}

# get_lowest_instance_id -> echo int, or 0 if none
get_lowest_instance_id() {
  local first
  first=$(get_instance_ids_nl | head -n 1)
  if [[ -z "$first" ]]; then
    echo 0
    return
  fi
  echo "$first"
}

# ----------------------------------------------------------------------------
# External commands
# ----------------------------------------------------------------------------

# require_command <cmd> -> die if not on PATH
require_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "❌ Requerido pero no encontrado: $1" >&2
    return 1
  fi
}

# check_docker -> die if docker daemon unreachable
check_docker() {
  require_command docker || return 1
  if ! docker info &>/dev/null; then
    echo "❌ Docker no está corriendo o no tienes permisos." >&2
    return 1
  fi
}

# instance_compose <id> [compose args...] -> run docker compose on the
# instance's compose file. Requires docker to be available.
instance_compose() {
  local id="$1"
  shift
  local dir
  dir=$(instance_dir "$id")
  if [[ ! -f "${dir}/docker-compose.yml" ]]; then
    echo "❌ Instancia ${id} no existe." >&2
    return 1
  fi
  docker compose -f "${dir}/docker-compose.yml" "$@"
}

# ----------------------------------------------------------------------------
# cluster_set_openrouter_key [target] [new_key]
# Update the OpenRouter key in one or all instances + the cluster .env.
# Pure-FS (no docker needed; just sed on JSON files).
# ----------------------------------------------------------------------------
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
    local id
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

# _update_instance_openrouter_key <id> <new_key>
# Internal helper: rewrites the key in openclaw.json and auth-profiles.json.
_update_instance_openrouter_key() {
  local id="$1"
  local new_key="$2"
  local dir
  dir=$(instance_dir "$id")

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

# ----------------------------------------------------------------------------
# cluster_set_telegram [target] [bot_token] [dm_policy]
# Adds/updates the Telegram bot config in one or all instances.
# Pure-FS: uses awk to manipulate openclaw.json (PR #10 will migrate to jq).
# ----------------------------------------------------------------------------
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
    local id
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

# _update_instance_telegram <id> <bot_token> <dm_policy>
# Internal helper: rewrites the channels.telegram block in openclaw.json.
# Uses awk (PR #10 will migrate to jq).
_update_instance_telegram() {
  local id="$1"
  local bot_token="$2"
  local dm_policy="$3"
  local dir
  dir=$(instance_dir "$id")
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
  ' "$config_file" >"${config_file}.tmp"

  # Remove existing TELEGRAM_BOT_TOKEN line from env
  grep -v '"TELEGRAM_BOT_TOKEN"' "${config_file}.tmp" >"${config_file}.tmp2"
  mv "${config_file}.tmp2" "${config_file}.tmp"

  # Add TELEGRAM_BOT_TOKEN after OPENROUTER_API_KEY
  awk -v tk="$bot_token" '
    /"OPENROUTER_API_KEY"/ { print; print "    \"TELEGRAM_BOT_TOKEN\": \"" tk "\","; next }
    { print }
  ' "${config_file}.tmp" >"${config_file}.tmp2"
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
  ' "${config_file}.tmp" >"${config_file}"
  rm -f "${config_file}.tmp"

  print_success "instance-${id} actualizada con Telegram"
}
