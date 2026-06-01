#!/usr/bin/env bats
# tests/bats/template.bats — golden file comparison for lib/template.sh.
#
# Each @test renders into a temp dir, normalizes the output (jq -S to sort
# keys), and diffs against tests/golden/instance-1/.
#
# This is the byte-for-byte safety net for the Phase 2 refactor: if any
# generator in lib/template.sh deviates from the v1.1.0 output, this test
# catches it.

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/template.sh"

  TEST_TMPDIR="$(mktemp -d -t oc-template-XXXXXX)"
  PINNED_TOKEN="$(printf 'a%.0s' {1..64})"
  PINNED_LAST_USED=1700000000000
  FAKE_API_KEY="sk-or-v1-golden-fixture-0000000000000000"
  FAKE_TG_TOKEN="0000000000:AA-golden-telegram-fixture"
  MODEL="openrouter/golden/fixture-model"
  GATEWAY_PORT=18022
  TZ="UTC"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# Helper: normalize a JSON file (sort keys) and write to a target.
normalize_json() {
  local src="$1"
  local dst="$2"
  jq -S . "$src" > "$dst"
}

@test "gen_openclaw_json produces the golden openclaw.json (with telegram)" {
  gen_openclaw_json "${TEST_TMPDIR}/openclaw.json" \
    "$GATEWAY_PORT" "$FAKE_API_KEY" "$MODEL" yes \
    "$FAKE_TG_TOKEN" pairing

  # Replace placeholder token with pinned one for stable diff
  jq --arg t "$PINNED_TOKEN" '.gateway.auth.token = $t' \
    "${TEST_TMPDIR}/openclaw.json" > "${TEST_TMPDIR}/openclaw.json.tmp"
  mv "${TEST_TMPDIR}/openclaw.json.tmp" "${TEST_TMPDIR}/openclaw.json"

  normalize_json "${TEST_TMPDIR}/openclaw.json" "${TEST_TMPDIR}/openclaw.norm.json"
  diff -u \
    "${ROOT_DIR}/tests/golden/instance-1/config/openclaw.json" \
    "${TEST_TMPDIR}/openclaw.norm.json"
}

@test "gen_openclaw_json omits telegram block when token is empty" {
  gen_openclaw_json "${TEST_TMPDIR}/openclaw.json" \
    "$GATEWAY_PORT" "$FAKE_API_KEY" "$MODEL" yes "" pairing
  # No TELEGRAM_BOT_TOKEN
  ! jq -e '.env.TELEGRAM_BOT_TOKEN' "${TEST_TMPDIR}/openclaw.json" >/dev/null
  # No channels block
  ! jq -e '.channels' "${TEST_TMPDIR}/openclaw.json" >/dev/null
  # But the rest is intact
  jq -e '.env.OPENROUTER_API_KEY' "${TEST_TMPDIR}/openclaw.json" >/dev/null
  jq -e '.gateway.port == 18789' "${TEST_TMPDIR}/openclaw.json" >/dev/null
}

@test "gen_openclaw_json headless=no produces false boolean" {
  gen_openclaw_json "${TEST_TMPDIR}/openclaw.json" \
    "$GATEWAY_PORT" "$FAKE_API_KEY" "$MODEL" no "" pairing
  [ "$(jq -r .browser.headless "${TEST_TMPDIR}/openclaw.json")" = "false" ]
}

@test "gen_openclaw_json headless=yes produces true boolean" {
  gen_openclaw_json "${TEST_TMPDIR}/openclaw.json" \
    "$GATEWAY_PORT" "$FAKE_API_KEY" "$MODEL" yes "" pairing
  [ "$(jq -r .browser.headless "${TEST_TMPDIR}/openclaw.json")" = "true" ]
}

@test "gen_openclaw_json embeds the gateway port in allowedOrigins" {
  gen_openclaw_json "${TEST_TMPDIR}/openclaw.json" \
    18110 "$FAKE_API_KEY" "$MODEL" yes "" pairing
  origins=$(jq -c .gateway.controlUi.allowedOrigins "${TEST_TMPDIR}/openclaw.json")
  [[ "$origins" == *'"http://localhost:18110"'* ]]
  [[ "$origins" == *'"http://127.0.0.1:18110"'* ]]
}

@test "gen_auth_profiles matches golden" {
  gen_auth_profiles "${TEST_TMPDIR}/auth-profiles.json" "$FAKE_API_KEY"
  normalize_json "${TEST_TMPDIR}/auth-profiles.json" \
    "${TEST_TMPDIR}/auth-profiles.norm.json"
  diff -u \
    "${ROOT_DIR}/tests/golden/instance-1/config/agents/main/agent/auth-profiles.json" \
    "${TEST_TMPDIR}/auth-profiles.norm.json"
}

@test "gen_auth_state matches golden when lastUsed is pinned" {
  gen_auth_state "${TEST_TMPDIR}/auth-state.json" "$PINNED_LAST_USED"
  normalize_json "${TEST_TMPDIR}/auth-state.json" \
    "${TEST_TMPDIR}/auth-state.norm.json"
  diff -u \
    "${ROOT_DIR}/tests/golden/instance-1/config/agents/main/agent/auth-state.json" \
    "${TEST_TMPDIR}/auth-state.norm.json"
}

@test "gen_auth_state produces errorCount=0" {
  gen_auth_state "${TEST_TMPDIR}/auth-state.json" 1000
  [ "$(jq -r '.usageStats["openrouter:default"].errorCount' "${TEST_TMPDIR}/auth-state.json")" = "0" ]
}

@test "gen_models_json matches golden" {
  gen_models_json "${TEST_TMPDIR}/models.json" "$MODEL"
  normalize_json "${TEST_TMPDIR}/models.json" "${TEST_TMPDIR}/models.norm.json"
  diff -u \
    "${ROOT_DIR}/tests/golden/instance-1/config/agents/main/agent/models.json" \
    "${TEST_TMPDIR}/models.norm.json"
}

@test "gen_models_json strips 'openrouter/' prefix from id" {
  gen_models_json "${TEST_TMPDIR}/models.json" "openrouter/anthropic/claude-3-sonnet"
  [ "$(jq -r .providers.openrouter.models[0].id "${TEST_TMPDIR}/models.json")" = "anthropic/claude-3-sonnet" ]
}

@test "gen_instance_env matches golden" {
  gen_instance_env "${TEST_TMPDIR}/.env" "$PINNED_TOKEN" "$TZ"
  diff -u \
    "${ROOT_DIR}/tests/golden/instance-1/.env" \
    "${TEST_TMPDIR}/.env"
}

@test "render_compose substitutes all variables" {
  # Build a minimal template
  cat > "${TEST_TMPDIR}/tpl.yml" <<'TPL'
name: "{{INSTANCE_NAME}}"
ports:
  - "{{GATEWAY_PORT}}:18789"
TZ: "{{TZ}}"
TPL

  render_compose "${TEST_TMPDIR}/tpl.yml" "${TEST_TMPDIR}/out.yml" \
    INSTANCE_NAME=instance-7 \
    GATEWAY_PORT=18154 \
    TZ=America/Mexico_City

  grep -q "name: \"instance-7\"" "${TEST_TMPDIR}/out.yml"
  grep -q '"18154:18789"' "${TEST_TMPDIR}/out.yml"
  grep -q 'TZ: "America/Mexico_City"' "${TEST_TMPDIR}/out.yml"
}

@test "render_compose is idempotent on the same inputs" {
  cat > "${TEST_TMPDIR}/tpl.yml" <<'TPL'
key: "{{K}}"
TPL
  render_compose "${TEST_TMPDIR}/tpl.yml" "${TEST_TMPDIR}/a.yml" K=hello
  render_compose "${TEST_TMPDIR}/tpl.yml" "${TEST_TMPDIR}/b.yml" K=hello
  diff -u "${TEST_TMPDIR}/a.yml" "${TEST_TMPDIR}/b.yml"
}

@test "render_compose leaves unknown placeholders alone" {
  cat > "${TEST_TMPDIR}/tpl.yml" <<'TPL'
foo: "{{FOO}}"
bar: "{{BAR}}"
TPL
  render_compose "${TEST_TMPDIR}/tpl.yml" "${TEST_TMPDIR}/out.yml" FOO=hi
  grep -q 'foo: "hi"' "${TEST_TMPDIR}/out.yml"
  grep -q 'bar: "{{BAR}}"' "${TEST_TMPDIR}/out.yml"
}
