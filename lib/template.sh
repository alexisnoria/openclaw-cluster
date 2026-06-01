#!/usr/bin/env bash
# lib/template.sh — Render openclaw.json, auth-profiles.json, auth-state.json,
# models.json, .env, and docker-compose.yml for a single instance.
#
# Each function writes to a specific path. Callers control the output path,
# making the module fully testable (sandbox-safe).
#
# Source from openclaw-cluster.sh or any lib/*.sh. Idempotent.
#
# Provides:
#   - gen_openclaw_json     <out_path> <gateway_port> <api_key> <model>
#                           <headless_yes> <tg_token> <tg_dm_policy>
#   - gen_auth_profiles     <out_path> <api_key>
#   - gen_auth_state        <out_path> <last_used_epoch_ms>
#   - gen_models_json       <out_path> <model_id>
#   - gen_instance_env      <out_path> <gateway_token> <tz>
#   - render_compose        <template_path> <out_path> <vars...>
#                           (vars are key=value pairs)
#
# All functions are pure FS-writers: same inputs → same outputs.

if [[ -n "${__LIB_TEMPLATE_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_TEMPLATE_SOURCED=1

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

# _yaml_bool <yes|no> -> echo "true" or "false" (for JSON)
_yaml_bool() {
  case "$1" in
    yes | YES | y | Y | true | 1) echo "true" ;;
    *) echo "false" ;;
  esac
}

# _json_str <s> -> echo JSON-escaped string
# Used internally; safe for ASCII inputs (no quotes, backslashes, control chars)
_json_str() {
  local s="$1"
  # Escape backslashes and double quotes
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# _mkdirp <path>
_mkdirp() {
  mkdir -p "$1"
}

# ----------------------------------------------------------------------------
# Config file generators
# ----------------------------------------------------------------------------

# gen_openclaw_json <out_path> <gateway_port> <api_key> <model>
#                   <headless_yes|no> <tg_token|""> <tg_dm_policy|"">
#
# When tg_token is empty, the TELEGRAM_BOT_TOKEN env var and the channels block
# are omitted. Matches openclaw-cluster.sh v1.1.0's _create_instance output.
gen_openclaw_json() {
  local out="$1"
  local gateway_port="$2"
  local api_key="$3"
  local model="$4"
  local headless="$5"
  local tg_token="$6"
  local tg_dm_policy="${7:-pairing}"

  _mkdirp "$(dirname "$out")"

  local headless_bool
  headless_bool=$(_yaml_bool "$headless")

  local tg_env=""
  local tg_channels=""
  if [[ -n "$tg_token" ]]; then
    tg_env=",\"TELEGRAM_BOT_TOKEN\": \"$(_json_str "$tg_token")\""
    tg_channels=",

  \"channels\": {
    \"telegram\": {
      \"enabled\": true,
      \"botToken\": \"$(_json_str "$tg_token")\",
      \"dmPolicy\": \"$(_json_str "$tg_dm_policy")\"
    }
  }"
  fi

  cat >"$out" <<EOF
{
  "env": {
    "OPENROUTER_API_KEY": "$(_json_str "$api_key")"${tg_env}
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "$(_json_str "$model")"
      },
      "workspace": "/home/node/.openclaw/workspace",
      "models": {
        "$(_json_str "$model")": {
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
      "token": "PLACEHOLDER_TOKEN"
    },
    "controlUi": {
      "allowedOrigins": ["http://localhost:${gateway_port}", "http://127.0.0.1:${gateway_port}"]
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
  }${tg_channels}
}
EOF
}

# gen_auth_profiles <out_path> <api_key>
gen_auth_profiles() {
  local out="$1"
  local api_key="$2"
  _mkdirp "$(dirname "$out")"
  cat >"$out" <<EOF
{
  "version": 1,
  "profiles": {
    "openrouter:default": {
      "type": "api_key",
      "provider": "openrouter",
      "key": "$(_json_str "$api_key")"
    }
  }
}
EOF
}

# gen_auth_state <out_path> <last_used_epoch_ms>
gen_auth_state() {
  local out="$1"
  local last_used="$2"
  _mkdirp "$(dirname "$out")"
  cat >"$out" <<EOF
{
  "version": 1,
  "lastGood": {
    "openrouter": "openrouter:default"
  },
  "usageStats": {
    "openrouter:default": {
      "errorCount": 0,
      "lastUsed": ${last_used}
    }
  }
}
EOF
}

# gen_models_json <out_path> <model>
# The model is expected in the form "openrouter/<vendor>/<model>"; the
# "openrouter/" prefix is stripped for the OpenRouter model id.
gen_models_json() {
  local out="$1"
  local model="$2"
  _mkdirp "$(dirname "$out")"
  local model_id="${model#openrouter/}"
  cat >"$out" <<EOF
{
  "providers": {
    "openrouter": {
      "baseUrl": "https://openrouter.ai/api/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "$(_json_str "$model_id")",
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
}

# gen_instance_env <out_path> <gateway_token> <tz>
gen_instance_env() {
  local out="$1"
  local token="$2"
  local tz="$3"
  _mkdirp "$(dirname "$out")"
  cat >"$out" <<EOF
OPENCLAW_GATEWAY_TOKEN=${token}
OPENCLAW_TZ=${tz}
EOF
}

# ----------------------------------------------------------------------------
# Compose template renderer
# ----------------------------------------------------------------------------

# render_compose <template_path> <out_path> <vars...>
# Variables are passed as KEY=VALUE pairs. The renderer substitutes
# {{KEY}} occurrences in the template with VALUE.
render_compose() {
  local template="$1"
  local out="$2"
  shift 2
  _mkdirp "$(dirname "$out")"

  local sed_args=()
  local kv
  for kv in "$@"; do
    local key="${kv%%=*}"
    local value="${kv#*=}"
    sed_args+=(-e "s|{{${key}}}|${value}|g")
  done

  sed "${sed_args[@]}" "$template" >"$out"
}
