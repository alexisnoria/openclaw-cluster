#!/usr/bin/env bats
# tests/integration/scale.bats — `cluster_scale +N` and `cluster_scale -N`
# create/destroy instances.

load helpers/setup

@test "scale +2 adds instances 2 and 3" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  run run_cluster scale +2
  [ "$status" -eq 0 ]
  assert_dir_exists instances/instance-2
  assert_dir_exists instances/instance-3
}

@test "scale -1 removes the highest instance" {
  run run_cluster init 3 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  run run_cluster scale -1
  [ "$status" -eq 0 ]
  ! [ -d instances/instance-3 ]
  [ -d instances/instance-1 ]
  [ -d instances/instance-2 ]
}

@test "scale rejects removing more than exists" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  run run_cluster scale -5
  [ "$status" -ne 0 ]
  [[ "$output" == *"más instancias"* ]]
}

@test "scale rejects invalid format" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  run run_cluster scale abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"inválido"* ]]
}
