#!/usr/bin/env bats
# tests/bats/lifecycle.bats — unit tests for _create_instance (pure FS).
# cluster_init and the docker compose wrappers are exercised by integration
# tests in tests/integration/.

setup() {
  load helpers/load
  # Source all modules the lifecycle depends on
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/lifecycle.sh"

  TEST_TMPDIR="$(mktemp -d -t oc-lifecycle-XXXXXX)"
  export INSTANCES_DIR="${TEST_TMPDIR}/instances"
  export CLUSTER_DIR="${TEST_TMPDIR}"
  export TEMPLATE_FILE="${ROOT_DIR}/docker-compose.template.yml"
  mkdir -p "${INSTANCES_DIR}"
  cd "${TEST_TMPDIR}"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# Helper: run _create_instance with known args
create_fixt_1() {
  _create_instance 1 yes UTC \
    "sk-or-v1-fixture-0000000000000000" \
    "openrouter/fixture/test-model" \
    "" "pairing"
}

create_fixt_with_telegram() {
  _create_instance 1 yes UTC \
    "sk-or-v1-fixture-0000000000000000" \
    "openrouter/fixture/test-model" \
    "0000000000:AA-fixture" "pairing"
}

# ----------------------------------------------------------------------------
# _create_instance — directory layout
# ----------------------------------------------------------------------------

@test "_create_instance creates the full directory tree" {
  create_fixt_1
  [ -d instances/instance-1 ]
  [ -d instances/instance-1/config ]
  [ -d instances/instance-1/workspace ]
  [ -d instances/instance-1/home ]
  [ -d instances/instance-1/config/agents/main/agent ]
}

@test "_create_instance writes all 4 config files" {
  create_fixt_1
  [ -f instances/instance-1/config/openclaw.json ]
  [ -f instances/instance-1/config/agents/main/agent/auth-profiles.json ]
  [ -f instances/instance-1/config/agents/main/agent/auth-state.json ]
  [ -f instances/instance-1/config/agents/main/agent/models.json ]
  [ -f instances/instance-1/.env ]
  [ -f instances/instance-1/docker-compose.yml ]
}

# ----------------------------------------------------------------------------
# _create_instance — JSON validity
# ----------------------------------------------------------------------------

@test "_create_instance openclaw.json is valid JSON" {
  create_fixt_1
  jq . instances/instance-1/config/openclaw.json >/dev/null
}

@test "_create_instance openclaw.json has the gateway port in allowedOrigins" {
  create_fixt_1
  gport=$(jq -r '.gateway.controlUi.allowedOrigins[0]' instances/instance-1/config/openclaw.json)
  [[ "$gport" == *":18022"* ]]
}

@test "_create_instance openclaw.json has 64-char token" {
  create_fixt_1
  token=$(jq -r .gateway.auth.token instances/instance-1/config/openclaw.json)
  [[ "$token" =~ ^[0-9a-f]{64}$ ]]
}

@test "_create_instance openclaw.json embeds the OpenRouter key" {
  create_fixt_1
  jq -e '.env.OPENROUTER_API_KEY == "sk-or-v1-fixture-0000000000000000"' \
    instances/instance-1/config/openclaw.json >/dev/null
}

@test "_create_instance openclaw.json has the model as primary" {
  create_fixt_1
  primary=$(jq -r .agents.defaults.model.primary instances/instance-1/config/openclaw.json)
  [ "$primary" = "openrouter/fixture/test-model" ]
}

@test "_create_instance openclaw.json omits telegram when token empty" {
  create_fixt_1
  ! jq -e '.env.TELEGRAM_BOT_TOKEN' instances/instance-1/config/openclaw.json >/dev/null
  ! jq -e '.channels' instances/instance-1/config/openclaw.json >/dev/null
}

@test "_create_instance openclaw.json includes telegram when token set" {
  create_fixt_with_telegram
  jq -e '.env.TELEGRAM_BOT_TOKEN == "0000000000:AA-fixture"' \
    instances/instance-1/config/openclaw.json >/dev/null
  jq -e '.channels.telegram.dmPolicy == "pairing"' \
    instances/instance-1/config/openclaw.json >/dev/null
}

@test "_create_instance auth-profiles.json has the OpenRouter key" {
  create_fixt_1
  key=$(jq -r '.profiles["openrouter:default"].key' instances/instance-1/config/agents/main/agent/auth-profiles.json)
  [ "$key" = "sk-or-v1-fixture-0000000000000000" ]
}

@test "_create_instance auth-state.json has errorCount=0" {
  create_fixt_1
  count=$(jq -r '.usageStats["openrouter:default"].errorCount' instances/instance-1/config/agents/main/agent/auth-state.json)
  [ "$count" = "0" ]
}

@test "_create_instance auth-state.json lastUsed is a recent timestamp" {
  create_fixt_1
  last=$(jq -r '.usageStats["openrouter:default"].lastUsed' instances/instance-1/config/agents/main/agent/auth-state.json)
  # Must be within 60s of now (in ms)
  now_ms=$(($(date +%s) * 1000))
  diff=$(( now_ms - last ))
  [ "$diff" -ge 0 ] && [ "$diff" -lt 60000 ]
}

@test "_create_instance models.json strips 'openrouter/' prefix" {
  create_fixt_1
  id=$(jq -r .providers.openrouter.models[0].id instances/instance-1/config/agents/main/agent/models.json)
  [ "$id" = "fixture/test-model" ]
}

# ----------------------------------------------------------------------------
# _create_instance — .env and compose
# ----------------------------------------------------------------------------

@test "_create_instance .env has 64-char token" {
  create_fixt_1
  token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' instances/instance-1/.env | cut -d= -f2)
  [[ "$token" =~ ^[0-9a-f]{64}$ ]]
}

@test "_create_instance .env matches the openclaw.json token" {
  create_fixt_1
  env_token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' instances/instance-1/.env | cut -d= -f2)
  json_token=$(jq -r .gateway.auth.token instances/instance-1/config/openclaw.json)
  [ "$env_token" = "$json_token" ]
}

@test "_create_instance docker-compose.yml has the gateway port mapping" {
  create_fixt_1
  grep -q '18022:18789' instances/instance-1/docker-compose.yml
}

@test "_create_instance docker-compose.yml has the bridge port mapping" {
  create_fixt_1
  grep -q '18023:18790' instances/instance-1/docker-compose.yml
}

@test "_create_instance docker-compose.yml has the network name" {
  create_fixt_1
  grep -q 'oc-net-1' instances/instance-1/docker-compose.yml
}

@test "_create_instance docker-compose.yml embeds the token" {
  create_fixt_1
  token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' instances/instance-1/.env | cut -d= -f2)
  grep -q "OPENCLAW_GATEWAY_TOKEN: \"$token\"" instances/instance-1/docker-compose.yml
}

@test "_create_instance docker-compose.yml sets BROWSER_HEADLESS=1 for headless=yes" {
  create_fixt_1
  grep -q 'OPENCLAW_BROWSER_HEADLESS: "1"' instances/instance-1/docker-compose.yml
}

@test "_create_instance docker-compose.yml sets BROWSER_HEADLESS=0 for headless=no" {
  _create_instance 1 no UTC \
    "sk-or-v1-fixture-0000000000000000" \
    "openrouter/fixture/test-model" \
    "" "pairing"
  grep -q 'OPENCLAW_BROWSER_HEADLESS: "0"' instances/instance-1/docker-compose.yml
}

# ----------------------------------------------------------------------------
# Idempotency-ish: tokens are unique across calls
# ----------------------------------------------------------------------------

@test "_create_instance generates unique tokens across calls" {
  create_fixt_1
  mv instances/instance-1 instances/instance-1.first
  _create_instance 1 yes UTC \
    "sk-or-v1-fixture-0000000000000000" \
    "openrouter/fixture/test-model" \
    "" "pairing"
  t1=$(jq -r .gateway.auth.token instances/instance-1.first/config/openclaw.json)
  t2=$(jq -r .gateway.auth.token instances/instance-1/config/openclaw.json)
  [ "$t1" != "$t2" ]
}
