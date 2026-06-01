#!/usr/bin/env bats
# tests/bats/config.bats — tests for cluster_config (file existence + error
# path). The editor flow is untestable in CI; we stub $EDITOR with `cat` so
# cluster_config becomes a no-op on a valid config.

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/config.sh"

  TEST_TMPDIR="$(mktemp -d -t oc-config-XXXXXX)"
  export INSTANCES_DIR="${TEST_TMPDIR}/instances"
  export CLUSTER_DIR="${TEST_TMPDIR}"
  mkdir -p "${INSTANCES_DIR}/instance-1/config"
  printf '{"x":1}' > "${INSTANCES_DIR}/instance-1/config/openclaw.json"
  # Stub editor to a no-op (just dumps the file to stdout)
  export EDITOR="cat"
  cd "${TEST_TMPDIR}"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

@test "cluster_config prints the file path" {
  run cluster_config 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Archivo: "* ]]
  [[ "$output" == *"config/openclaw.json"* ]]
}

@test "cluster_config dumps the config to stdout via the stubbed editor" {
  run cluster_config 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'{"x":1}'* ]]
}

@test "cluster_config errors when the config file is missing" {
  rm -f "${INSTANCES_DIR}/instance-1/config/openclaw.json"
  run cluster_config 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Config no encontrado"* ]]
  [[ "$output" == *"instance-1"* ]]
}

@test "cluster_config errors when the instance directory is missing" {
  rm -rf "${INSTANCES_DIR}/instance-1"
  run cluster_config 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Config no encontrado"* ]]
}

@test "cluster_config uses \$EDITOR when set" {
  # Override the stub to verify EDITOR is honored
  export EDITOR="echo USING_EDITOR"
  run cluster_config 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"USING_EDITOR"* ]]
}
