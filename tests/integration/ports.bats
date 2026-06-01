#!/usr/bin/env bats
# tests/integration/ports.bats — verifies the port-allocation formula and
# network name scheme used across the cluster. Pure FS, no Docker required
# after init, so this runs as part of the safety net.

load helpers/setup

@test "port assignment is instance*22 + 18000 (gateway) and +1 (bridge)" {
  run run_cluster init 4 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  # instance 1 -> 18022, instance 4 -> 18088
  assert_grep instances/instance-1/docker-compose.yml '18022:18789'
  assert_grep instances/instance-2/docker-compose.yml '18044:18789'
  assert_grep instances/instance-3/docker-compose.yml '18066:18789'
  assert_grep instances/instance-4/docker-compose.yml '18088:18789'
  # bridge is gateway+1
  assert_grep instances/instance-1/docker-compose.yml '18023:18790'
  assert_grep instances/instance-2/docker-compose.yml '18045:18790'
  assert_grep instances/instance-4/docker-compose.yml '18089:18790'
}

@test "each instance gets its own bridge network" {
  run run_cluster init 3 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  for n in 1 2 3; do
    assert_grep "instances/instance-${n}/docker-compose.yml" "oc-net-${n}"
  done
}

@test "no port collisions across 10 instances" {
  run run_cluster init 10 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  # Extract all "XXXXX:18789" lines and check uniqueness
  ports=$(grep -hoE '[0-9]+:18789' instances/*/docker-compose.yml | sort -u)
  count=$(echo "$ports" | wc -l | tr -d ' ')
  [ "$count" -eq 20 ]   # 10 gateway + 10 bridge
}
