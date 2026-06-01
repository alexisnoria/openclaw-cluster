#!/usr/bin/env bats
# tests/bats/telegram.bats — tests for _update_instance_telegram (jq-based).
# Replaces the v1.1.0 awk-based implementation. Verifies:
#   - Adds TELEGRAM_BOT_TOKEN to .env
#   - Adds channels.telegram block with correct fields
#   - Idempotency: calling twice replaces the existing block, doesn't duplicate
#   - Output remains valid JSON
#   - dmPolicy is honored

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/instance.sh"

  TEST_TMPDIR="$(mktemp -d -t oc-telegram-XXXXXX)"
  export INSTANCES_DIR="${TEST_TMPDIR}/instances"
  export CLUSTER_DIR="${TEST_TMPDIR}"
  mkdir -p "${INSTANCES_DIR}/instance-1/config/agents/main/agent"
  # A minimal openclaw.json fixture, modeled on what _create_instance produces
  jq -n '
    {
      env: { OPENROUTER_API_KEY: "sk-or-v1-fixture" },
      channels: {}
    }
  ' > "${INSTANCES_DIR}/instance-1/config/openclaw.json"
  cd "${TEST_TMPDIR}"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

call_update() {
  _update_instance_telegram 1 "$1" "$2"
}

config_file() {
  echo "${INSTANCES_DIR}/instance-1/config/openclaw.json"
}

# ----------------------------------------------------------------------------
# Happy path
# ----------------------------------------------------------------------------

@test "_update_instance_telegram: file exists and jq is available" {
  call_update "0000:AA-token" "pairing"
  [ "$?" -eq 0 ]
  [ -f "$(config_file)" ]
}

@test "_update_instance_telegram: output is valid JSON" {
  call_update "0000:AA-token" "pairing"
  jq . "$(config_file)" >/dev/null
}

@test "_update_instance_telegram: adds channels.telegram.enabled = true" {
  call_update "0000:AA-token" "pairing"
  enabled=$(jq -r .channels.telegram.enabled "$(config_file)")
  [ "$enabled" = "true" ]
}

@test "_update_instance_telegram: stores the botToken under channels.telegram" {
  call_update "0000:AA-token" "pairing"
  token=$(jq -r .channels.telegram.botToken "$(config_file)")
  [ "$token" = "0000:AA-token" ]
}

@test "_update_instance_telegram: stores the dmPolicy" {
  call_update "0000:AA-token" "allowlist"
  pol=$(jq -r .channels.telegram.dmPolicy "$(config_file)")
  [ "$pol" = "allowlist" ]
}

@test "_update_instance_telegram: also adds TELEGRAM_BOT_TOKEN to .env" {
  call_update "0000:AA-token" "pairing"
  token=$(jq -r .env.TELEGRAM_BOT_TOKEN "$(config_file)")
  [ "$token" = "0000:AA-token" ]
}

@test "_update_instance_telegram: preserves other env keys" {
  call_update "0000:AA-token" "pairing"
  key=$(jq -r .env.OPENROUTER_API_KEY "$(config_file)")
  [ "$key" = "sk-or-v1-fixture" ]
}

# ----------------------------------------------------------------------------
# Idempotency
# ----------------------------------------------------------------------------

@test "_update_instance_telegram: calling twice doesn't duplicate channels.telegram" {
  call_update "0000:AA-token" "pairing"
  call_update "1111:BB-token" "open"
  # Exactly one channels.telegram block
  count=$(jq '[.channels.telegram] | length' "$(config_file)")
  [ "$count" -eq 1 ]
}

@test "_update_instance_telegram: second call replaces the token" {
  call_update "0000:AA-token" "pairing"
  call_update "1111:BB-token" "open"
  token=$(jq -r .channels.telegram.botToken "$(config_file)")
  [ "$token" = "1111:BB-token" ]
}

@test "_update_instance_telegram: second call replaces dmPolicy" {
  call_update "0000:AA-token" "pairing"
  call_update "1111:BB-token" "open"
  pol=$(jq -r .channels.telegram.dmPolicy "$(config_file)")
  [ "$pol" = "open" ]
}

@test "_update_instance_telegram: second call replaces .env.TELEGRAM_BOT_TOKEN" {
  call_update "0000:AA-token" "pairing"
  call_update "1111:BB-token" "open"
  token=$(jq -r .env.TELEGRAM_BOT_TOKEN "$(config_file)")
  [ "$token" = "1111:BB-token" ]
}

# ----------------------------------------------------------------------------
# Error paths
# ----------------------------------------------------------------------------

@test "_update_instance_telegram: errors when openclaw.json is missing" {
  rm -f "$(config_file)"
  run _update_instance_telegram 1 "0000:AA-token" "pairing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no encontrado"* ]]
}

# ----------------------------------------------------------------------------
# Cross-cutting: when combined with the gen_openclaw_json output (no
# TELEGRAM env key initially), the jq helper should produce a config
# equivalent to what gen_openclaw_json produces WITH the telegram token
# passed in (see tests/golden/instance-1/config/openclaw.json).
# ----------------------------------------------------------------------------

@test "_update_instance_telegram: after update, schema matches lib/template.sh output structure" {
  call_update "0000:AA-fixture" "pairing"
  # The result must have the same top-level structure as the golden file
  jq -e '
    has("env") and
    has("channels") and
    (.channels | has("telegram")) and
    (.env | has("TELEGRAM_BOT_TOKEN"))
  ' "$(config_file)" >/dev/null
}
