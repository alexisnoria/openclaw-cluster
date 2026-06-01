#!/usr/bin/env bats
# tests/bats/instance.bats — instance discovery, naming, and port helpers.

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/instance.sh"
  # Use a temp INSTANCES_DIR per test
  TEST_INSTANCES_DIR="$(mktemp -d -t oc-inst-XXXXXX)"
  export INSTANCES_DIR="$TEST_INSTANCES_DIR"
}

teardown() {
  [[ -n "${TEST_INSTANCES_DIR:-}" ]] && rm -rf "$TEST_INSTANCES_DIR"
}

# ----- naming ---------------------------------------------------------------

@test "instance_name produces instance-<id>" {
  result=$(instance_name 12)
  [ "$result" = "instance-12" ]
}

@test "instance_name handles zero" {
  result=$(instance_name 0)
  [ "$result" = "instance-0" ]
}

# ----- dirs -----------------------------------------------------------------

@test "instance_dir uses INSTANCES_DIR env" {
  result=$(instance_dir 3)
  [ "$result" = "${TEST_INSTANCES_DIR}/instance-3" ]
}

@test "instance_dir honors custom root override" {
  result=$(instance_dir 3 /tmp/custom)
  [ "$result" = "/tmp/custom/instance-3" ]
}

@test "instance_compose_path appends docker-compose.yml" {
  result=$(instance_compose_path 1)
  [ "$result" = "${TEST_INSTANCES_DIR}/instance-1/docker-compose.yml" ]
}

# ----- ports ----------------------------------------------------------------

@test "instance_gateway_port id=1 returns 18022" {
  result=$(instance_gateway_port 1)
  [ "$result" = "18022" ]
}

@test "instance_gateway_port id=0 returns 18000" {
  result=$(instance_gateway_port 0)
  [ "$result" = "18000" ]
}

@test "instance_gateway_port id=5 returns 18110" {
  result=$(instance_gateway_port 5)
  [ "$result" = "18110" ]
}

@test "instance_bridge_port is gateway+1" {
  gid=$(instance_gateway_port 7)
  bid=$(instance_bridge_port 7)
  [ "$((bid - gid))" = "1" ]
}

@test "ports are unique across ids" {
  seen=""
  for i in 1 2 3 4 5 6 7 8 9 10; do
    p=$(instance_gateway_port "$i")
    if [[ " $seen " == *" $p "* ]]; then
      echo "duplicate gateway port: $p" >&2
      return 1
    fi
    seen="$seen $p"
  done
}

@test "no port collision between gateway and bridge" {
  for i in 1 2 3 4 5 6 7 8 9 10; do
    g=$(instance_gateway_port "$i")
    b=$(instance_bridge_port "$i")
    [ "$g" != "$b" ] || { echo "collision at $i" >&2; return 1; }
  done
}

@test "custom base port is honored" {
  result=$(instance_gateway_port 1 20000)
  [ "$result" = "20022" ]
}

# ----- tokens ---------------------------------------------------------------

@test "generate_token returns 64 hex chars" {
  result=$(generate_token)
  [[ "$result" =~ ^[0-9a-f]{64}$ ]]
}

@test "generate_token returns unique values" {
  t1=$(generate_token)
  t2=$(generate_token)
  [ "$t1" != "$t2" ]
}

@test "generate_token handles 100 iterations without collision" {
  local seen=""
  local t
  for _ in $(seq 1 100); do
    t=$(generate_token)
    if [[ " $seen " == *" $t "* ]]; then
      echo "collision: $t" >&2
      return 1
    fi
    seen="$seen $t"
  done
}

# ----- discovery ------------------------------------------------------------

@test "get_instance_count returns 0 when empty" {
  result=$(get_instance_count)
  [ "$result" = "0" ]
}

@test "get_instance_count returns N when N instances exist" {
  mkdir -p "${TEST_INSTANCES_DIR}/instance-1"
  mkdir -p "${TEST_INSTANCES_DIR}/instance-2"
  mkdir -p "${TEST_INSTANCES_DIR}/instance-3"
  result=$(get_instance_count)
  [ "$result" = "3" ]
}

@test "get_instance_count ignores non-instance dirs" {
  mkdir -p "${TEST_INSTANCES_DIR}/instance-1"
  mkdir -p "${TEST_INSTANCES_DIR}/backups"
  mkdir -p "${TEST_INSTANCES_DIR}/.git"
  result=$(get_instance_count)
  [ "$result" = "1" ]
}

@test "get_instance_ids returns numeric ids sorted" {
  for n in 10 2 1 5; do
    mkdir -p "${TEST_INSTANCES_DIR}/instance-${n}"
  done
  result=$(get_instance_ids)
  [ "$result" = "1 2 5 10 " ]
}

@test "get_highest_instance_id returns max" {
  for n in 1 5 3 7; do
    mkdir -p "${TEST_INSTANCES_DIR}/instance-${n}"
  done
  result=$(get_highest_instance_id)
  [ "$result" = "7" ]
}

@test "get_highest_instance_id returns 0 when empty" {
  result=$(get_highest_instance_id)
  [ "$result" = "0" ]
}

@test "get_lowest_instance_id returns min" {
  for n in 1 5 3 7; do
    mkdir -p "${TEST_INSTANCES_DIR}/instance-${n}"
  done
  result=$(get_lowest_instance_id)
  [ "$result" = "1" ]
}

# ----- external commands ----------------------------------------------------

@test "require_command succeeds for an existing command" {
  require_command bash
}

@test "require_command fails for a missing command" {
  ! require_command this-command-does-not-exist-12345
}

@test "check_docker succeeds when docker is available" {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    check_docker
  else
    skip "docker daemon not available"
  fi
}
