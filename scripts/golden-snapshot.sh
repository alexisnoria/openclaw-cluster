#!/usr/bin/env bash
# scripts/golden-snapshot.sh — Capture the canonical output that
# openclaw-cluster.sh v1.1.0's _create_instance produces. These files
# become the byte-for-byte expected output that lib/template.sh must
# match in Phase 2 PR #5.
#
# We cannot rely on running `cluster_init` because that needs a Docker
# daemon. Instead, we extract the exact heredoc payloads from
# openclaw-cluster.sh and render them with fixed inputs.
#
# Usage: ./scripts/golden-snapshot.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GOLDEN_DIR="${ROOT_DIR}/tests/golden"
TEMPLATE_FILE="${ROOT_DIR}/docker-compose.template.yml"

# ----- Pinned fixture values -----------------------------------------------
ID=1
NAME="instance-1"
GATEWAY_PORT=18022
BRIDGE_PORT=18023
NETWORK_NAME="oc-net-1"
HEADLESS_BOOL=true
HEADLESS_VAL="1"
TZ="UTC"
API_KEY="sk-or-v1-golden-fixture-0000000000000000"
TG_TOKEN="0000000000:AA-golden-telegram-fixture"
TG_POLICY="pairing"
MODEL="openrouter/golden/fixture-model"
PINNED_TOKEN="$(printf 'a%.0s' {1..64})"
PINNED_LAST_USED=1700000000000

OUT="${GOLDEN_DIR}/instance-1"
rm -rf "${OUT}"
mkdir -p "${OUT}/config/agents/main/agent"

# ----- openclaw.json (the v1.1.0 _create_instance heredoc) -----------------
cat >"${OUT}/config/openclaw.json" <<EOF
{
  "env": {
    "OPENROUTER_API_KEY": "${API_KEY}",
    "TELEGRAM_BOT_TOKEN": "${TG_TOKEN}"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${MODEL}"
      },
      "workspace": "/home/node/.openclaw/workspace",
      "models": {
        "${MODEL}": {
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
      "token": "${PINNED_TOKEN}"
    },
    "controlUi": {
      "allowedOrigins": ["http://localhost:${GATEWAY_PORT}", "http://127.0.0.1:${GATEWAY_PORT}"]
    }
  },
  "browser": {
    "enabled": true,
    "executablePath": "/usr/bin/google-chrome",
    "headless": ${HEADLESS_BOOL},
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
  },

  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "${TG_TOKEN}",
      "dmPolicy": "${TG_POLICY}"
    }
  }
}
EOF

# ----- auth-profiles.json --------------------------------------------------
cat >"${OUT}/config/agents/main/agent/auth-profiles.json" <<EOF
{
  "version": 1,
  "profiles": {
    "openrouter:default": {
      "type": "api_key",
      "provider": "openrouter",
      "key": "${API_KEY}"
    }
  }
}
EOF

# ----- auth-state.json (pinned lastUsed) -----------------------------------
cat >"${OUT}/config/agents/main/agent/auth-state.json" <<EOF
{
  "version": 1,
  "lastGood": {
    "openrouter": "openrouter:default"
  },
  "usageStats": {
    "openrouter:default": {
      "errorCount": 0,
      "lastUsed": ${PINNED_LAST_USED}
    }
  }
}
EOF

# ----- models.json ---------------------------------------------------------
cat >"${OUT}/config/agents/main/agent/models.json" <<EOF
{
  "providers": {
    "openrouter": {
      "baseUrl": "https://openrouter.ai/api/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "golden/fixture-model",
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

# ----- .env ----------------------------------------------------------------
cat >"${OUT}/.env" <<EOF
OPENCLAW_GATEWAY_TOKEN=${PINNED_TOKEN}
OPENCLAW_TZ=${TZ}
EOF

# ----- docker-compose.yml (sed the template) -------------------------------
sed \
  -e "s|{{INSTANCE_ID}}|${ID}|g" \
  -e "s|{{INSTANCE_NAME}}|${NAME}|g" \
  -e "s|{{GATEWAY_PORT}}|${GATEWAY_PORT}|g" \
  -e "s|{{BRIDGE_PORT}}|${BRIDGE_PORT}|g" \
  -e "s|{{NETWORK_NAME}}|${NETWORK_NAME}|g" \
  -e "s|{{CONFIG_DIR}}|${OUT}/config|g" \
  -e "s|{{WORKSPACE_DIR}}|${OUT}/workspace|g" \
  -e "s|{{HOME_DIR}}|${OUT}/home|g" \
  -e "s|{{GATEWAY_TOKEN}}|${PINNED_TOKEN}|g" \
  -e "s|{{TZ}}|${TZ}|g" \
  -e "s|{{BROWSER_HEADLESS}}|${HEADLESS_VAL}|g" \
  "${TEMPLATE_FILE}" >"${OUT}/docker-compose.yml"

# ----- Normalize: sort keys in JSONs ---------------------------------------
for j in config/openclaw.json config/agents/main/agent/auth-profiles.json \
  config/agents/main/agent/auth-state.json \
  config/agents/main/agent/models.json; do
  f="${OUT}/${j}"
  jq -S . "$f" >"${f}.tmp" && mv "${f}.tmp" "$f"
done

echo "✅ Golden files written to ${OUT}/"
echo ""
echo "Files:"
ls -la "${OUT}"
ls -la "${OUT}/config"
ls -la "${OUT}/config/agents/main/agent"
