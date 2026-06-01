#!/usr/bin/env bats
# tests/integration/config.bats — live config updates (set-openrouter-key,
# set-telegram) modify the right files.

load helpers/setup

@test "set-openrouter-key updates both openclaw.json and auth-profiles.json" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]

  new_key="sk-or-v1-NEWKEY-replacement-1234567890"
  run run_cluster set-openrouter-key 1 "$new_key"
  [ "$status" -eq 0 ]

  assert_grep instances/instance-1/config/openclaw.json "$new_key"
  assert_grep instances/instance-1/config/agents/main/agent/auth-profiles.json "$new_key"
}

@test "set-openrouter-key with 'all' updates every instance" {
  run run_cluster init 2 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]

  new_key="sk-or-v1-ALLINSTANCES-1234567890"
  run run_cluster set-openrouter-key all "$new_key"
  [ "$status" -eq 0 ]

  assert_grep instances/instance-1/config/openclaw.json "$new_key"
  assert_grep instances/instance-2/config/openclaw.json "$new_key"
}

@test "set-telegram adds channels.telegram to openclaw.json" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  # Sanity: no channels initially
  ! grep -q '"channels"' instances/instance-1/config/openclaw.json

  run run_cluster set-telegram 1 "${FAKE_TG_TOKEN}" allowlist
  [ "$status" -eq 0 ]

  assert_valid_json instances/instance-1/config/openclaw.json
  assert_grep instances/instance-1/config/openclaw.json '"TELEGRAM_BOT_TOKEN"'
  assert_grep instances/instance-1/config/openclaw.json "${FAKE_TG_TOKEN}"
  assert_grep instances/instance-1/config/openclaw.json '"channels"'
  assert_grep instances/instance-1/config/openclaw.json '"dmPolicy": "allowlist"'
}

@test "set-telegram on an instance that already has it replaces the token" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "${FAKE_TG_TOKEN}" pairing
  [ "$status" -eq 0 ]

  new_tg="9999999999:BBNewTelegramBotToken"
  run run_cluster set-telegram 1 "$new_tg" open
  [ "$status" -eq 0 ]

  # Only the new token should be present
  ! grep -q "${FAKE_TG_TOKEN}" instances/instance-1/config/openclaw.json
  assert_grep instances/instance-1/config/openclaw.json "$new_tg"
  assert_grep instances/instance-1/config/openclaw.json '"dmPolicy": "open"'
}

@test "set-telegram produces a single 'channels' block (no duplicates)" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]

  run run_cluster set-telegram 1 "${FAKE_TG_TOKEN}" pairing
  [ "$status" -eq 0 ]
  run run_cluster set-telegram 1 "${FAKE_TG_TOKEN}" allowlist
  [ "$status" -eq 0 ]

  # Should still parse as valid JSON (no duplicate keys)
  assert_valid_json instances/instance-1/config/openclaw.json
  # Count 'channels' top-level keys
  count=$(grep -c '"channels"' instances/instance-1/config/openclaw.json || true)
  [ "$count" -eq 1 ]
}
