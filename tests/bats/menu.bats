#!/usr/bin/env bats
# tests/bats/menu.bats — tests for show_menu rendering and the
# batch dispatch table (defined in lib/menu.sh and lib/batch.sh).

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/menu.sh"
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/batch.sh"

  TEST_TMPDIR="$(mktemp -d -t oc-menu-XXXXXX)"
  export INSTANCES_DIR="${TEST_TMPDIR}/instances"
  export CLUSTER_DIR="${TEST_TMPDIR}"
  mkdir -p "${INSTANCES_DIR}"
  cd "${TEST_TMPDIR}"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# ----------------------------------------------------------------------------
# show_menu — visual rendering
# ----------------------------------------------------------------------------

@test "show_menu prints the operations section header" {
  run show_menu
  [ "$status" -eq 0 ]
  [[ "$output" == *"Operaciones"* ]]
}

@test "show_menu prints the administration section header" {
  run show_menu
  [ "$status" -eq 0 ]
  [[ "$output" == *"Administración"* ]]
}

@test "show_menu lists all 18 numbered options" {
  run show_menu
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do
    [[ "$output" == *"[$n]"* ]]
  done
}

@test "show_menu lists the exit option 0" {
  run show_menu
  [[ "$output" == *"Salir"* ]]
}

@test "show_menu shows zero active instances for an empty cluster" {
  run show_menu
  [[ "$output" == *"Instancias activas: 0/0"* ]]
}

@test "show_menu shows instance count when instances exist" {
  mkdir -p "${INSTANCES_DIR}/instance-1"
  mkdir -p "${INSTANCES_DIR}/instance-2"
  run show_menu
  [[ "$output" == *"0/2"* ]]
}

# ----------------------------------------------------------------------------
# run_batch — dispatch table
#
# Each test stubs the target function with a sentinel that records its
# call. We verify the right handler fires for each batch command.
# ----------------------------------------------------------------------------

# Helper: stub a function with a global flag.
stub_handler() {
  local fname="$1"
  eval "${fname}() { echo \"STUB_${fname}_CALLED \${*}\"; return 0; }"
}

# All 18 batch commands (the v1.1.0 set).
# `clean` and `tokens` are no-arg commands in v1.1.0 (the case branches
# don't forward "$@"), so they get tested with no args separately.
ARGS_CMDS=(
  "init:cluster_init"
  "start:cluster_start"
  "stop:cluster_stop"
  "restart:cluster_restart"
  "status:cluster_status"
  "logs:cluster_logs"
  "exec:cluster_exec"
  "config:cluster_config"
  "destroy:cluster_destroy"
  "update:cluster_update"
  "backup:cluster_backup"
  "restore:cluster_restore"
  "scale:cluster_scale"
  "dashboard:cluster_dashboard"
  "set-openrouter-key:cluster_set_openrouter_key"
  "set-telegram:cluster_set_telegram"
)
NOARGS_CMDS=(
  "clean:cluster_clean_all"
  "tokens:cluster_tokens"
)

@test "run_batch dispatches every command to its handler (with args)" {
  for entry in "${ARGS_CMDS[@]}"; do
    handler="${entry##*:}"
    stub_handler "$handler"
  done

  for entry in "${ARGS_CMDS[@]}"; do
    cmd="${entry%%:*}"
    handler="${entry##*:}"
    run run_batch "$cmd" foo bar
    [ "$status" -eq 0 ] || { echo "FAIL: ${cmd} exit=$status"; return 1; }
    [[ "$output" == *"STUB_${handler}_CALLED foo bar"* ]] || {
      echo "FAIL: ${cmd} → expected stub of ${handler} called with 'foo bar', got: $output"
      return 1
    }
  done
}

@test "run_batch dispatches no-arg commands (clean, tokens)" {
  for entry in "${NOARGS_CMDS[@]}"; do
    handler="${entry##*:}"
    stub_handler "$handler"
  done

  for entry in "${NOARGS_CMDS[@]}"; do
    cmd="${entry%%:*}"
    handler="${entry##*:}"
    run run_batch "$cmd"
    [ "$status" -eq 0 ] || { echo "FAIL: ${cmd} exit=$status"; return 1; }
    [[ "$output" == *"STUB_${handler}_CALLED"* ]] || {
      echo "FAIL: ${cmd} → expected stub of ${handler} called, got: $output"
      return 1
    }
  done
}

@test "run_batch forwards args to set-openrouter-key" {
  stub_handler cluster_set_openrouter_key
  run run_batch set-openrouter-key all sk-or-v1-newkey
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB_cluster_set_openrouter_key_CALLED all sk-or-v1-newkey"* ]]
}

@test "run_batch forwards args to set-telegram" {
  stub_handler cluster_set_telegram
  run run_batch set-telegram 1 0000:AA-token allowlist
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB_cluster_set_telegram_CALLED 1 0000:AA-token allowlist"* ]]
}

@test "run_batch forwards multiple args" {
  stub_handler cluster_init
  run run_batch init 3 latest yes no UTC sk-or-v1-foo openrouter/x "tok" "pairing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 latest yes no UTC sk-or-v1-foo openrouter/x tok pairing"* ]]
}

@test "run_batch errors on unknown command" {
  run run_batch frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"desconocido"* ]]
  [[ "$output" == *"frobnicate"* ]]
  [[ "$output" == *"Uso:"* ]]
}

@test "run_batch -h prints usage without error" {
  run run_batch -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"Comandos:"* ]]
}

@test "run_batch --help prints usage" {
  run run_batch --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "run_batch help prints usage" {
  run run_batch help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Comandos:"* ]]
}

@test "batch_usage mentions all 18 commands in the help text" {
  for entry in "${ARGS_CMDS[@]}" "${NOARGS_CMDS[@]}"; do
    cmd="${entry%%:*}"
    run batch_usage test
    [[ "$output" == *"$cmd"* ]]
  done
}
