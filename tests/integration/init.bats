#!/usr/bin/env bats
# tests/integration/init.bats — `cluster_init` produces a correct instance
# layout: directories, config files, JSON validity, port allocation, and
# template variable substitution. This is the safety net for Phase 2 PRs.

load helpers/setup

@test "init 1 creates the full instance-1 directory tree" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_dir_exists instances/instance-1
  assert_dir_exists instances/instance-1/config
  assert_dir_exists instances/instance-1/workspace
  assert_dir_exists instances/instance-1/home
  assert_dir_exists instances/instance-1/config/agents/main/agent
  assert_file_exists instances/instance-1/.env
  assert_file_exists instances/instance-1/docker-compose.yml
  assert_file_exists instances/instance-1/config/openclaw.json
  assert_file_exists instances/instance-1/config/agents/main/agent/auth-profiles.json
  assert_file_exists instances/instance-1/config/agents/main/agent/auth-state.json
  assert_file_exists instances/instance-1/config/agents/main/agent/models.json
}

@test "init 1 generates parseable openclaw.json" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_valid_json instances/instance-1/config/openclaw.json
  assert_valid_json instances/instance-1/config/agents/main/agent/auth-profiles.json
  assert_valid_json instances/instance-1/config/agents/main/agent/auth-state.json
  assert_valid_json instances/instance-1/config/agents/main/agent/models.json
}

@test "init 1 assigns correct port (18022/18023) for instance 1" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  # Gateway port
  assert_grep instances/instance-1/docker-compose.yml '18022:18789'
  # Bridge port
  assert_grep instances/instance-1/docker-compose.yml '18023:18790'
}

@test "init 1 uses isolated network oc-net-1" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/docker-compose.yml 'oc-net-1'
}

@test "init 1 sets OPENCLAW_GATEWAY_TOKEN in .env" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/.env 'OPENCLAW_GATEWAY_TOKEN=[a-f0-9]{64}'
}

@test "init 1 embeds OpenRouter model id" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/config/openclaw.json 'openrouter/test/test-model'
}

@test "init 1 embeds OpenRouter API key in config" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/config/openclaw.json "${FAKE_API_KEY}"
  assert_grep instances/instance-1/config/agents/main/agent/auth-profiles.json "${FAKE_API_KEY}"
}

@test "init 1 omits Telegram block when token is empty" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  ! grep -q '"TELEGRAM_BOT_TOKEN"' instances/instance-1/config/openclaw.json
  ! grep -q '"channels"' instances/instance-1/config/openclaw.json
}

@test "init 1 includes Telegram block when token is provided" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "${FAKE_TG_TOKEN}" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/config/openclaw.json '"TELEGRAM_BOT_TOKEN"'
  assert_grep instances/instance-1/config/openclaw.json "${FAKE_TG_TOKEN}"
  assert_grep instances/instance-1/config/openclaw.json '"channels"'
  assert_grep instances/instance-1/config/openclaw.json '"dmPolicy": "pairing"'
}

@test "init 1 sets correct timezone" {
  run run_cluster init 1 latest yes yes America/Mexico_City "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/docker-compose.yml 'TZ: "America/Mexico_City"'
}

@test "init 1 sets browser_headless=1 when headless=yes" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/docker-compose.yml 'OPENCLAW_BROWSER_HEADLESS: "1"'
}

@test "init 1 sets browser_headless=0 when headless=no" {
  run run_cluster init 1 latest yes no UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_grep instances/instance-1/docker-compose.yml 'OPENCLAW_BROWSER_HEADLESS: "0"'
}

@test "init 3 creates instance-1, instance-2, instance-3" {
  run run_cluster init 3 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  for n in 1 2 3; do
    assert_dir_exists "instances/instance-${n}"
    assert_file_exists "instances/instance-${n}/docker-compose.yml"
  done
  # Port assignment monotonic
  assert_grep instances/instance-1/docker-compose.yml '18022:18789'
  assert_grep instances/instance-2/docker-compose.yml '18044:18789'
  assert_grep instances/instance-3/docker-compose.yml '18066:18789'
}

@test "init 1 writes cluster .env file" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  assert_file_exists .env
  assert_grep .env '^TAG=latest$'
  assert_grep .env "^OPENROUTER_API_KEY=${FAKE_API_KEY}$"
  assert_grep .env '^TZ=UTC$'
}
