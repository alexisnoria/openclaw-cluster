#!/usr/bin/env bats
# tests/bats/destroy.bats — minimal smoke tests for cluster_destroy +
# cluster_clean_all. Both gate on check_docker and require interactive
# confirmations; we only verify the function signatures and missing-instance
# error path here. Full behavior is covered by tests/integration/.

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/destroy.sh"
}

@test "cluster_destroy is defined" {
  declare -F cluster_destroy >/dev/null
}

@test "cluster_clean_all is defined" {
  declare -F cluster_clean_all >/dev/null
}

@test "cluster_destroy returns 1 when instance dir is missing" {
  TEST_TMPDIR="$(mktemp -d -t oc-destroy-XXXXXX)"
  export INSTANCES_DIR="${TEST_TMPDIR}/instances"
  export CLUSTER_DIR="${TEST_TMPDIR}"
  # read_input is now interactive — pipe a number to stdin
  export INSTANCES_DIR="${TEST_TMPDIR}/instances"
  mkdir -p "${INSTANCES_DIR}"
  run bash -c "
    export INSTANCES_DIR='${TEST_TMPDIR}/instances'
    export CLUSTER_DIR='${TEST_TMPDIR}'
    # shellcheck disable=SC1091
    source '${ROOT_DIR}/lib/destroy.sh'
    echo 99 | cluster_destroy
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"no existe"* ]]
  rm -rf "${TEST_TMPDIR}"
}
