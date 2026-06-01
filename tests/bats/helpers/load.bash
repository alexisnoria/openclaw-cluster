#!/usr/bin/env bash
# tests/bats/helpers/load.bash — shared bats bootstrap.
#
# Sourcing this file makes the pure functions in lib/cluster.sh available
# inside @test blocks without booting Docker or instantiating the cluster.
#
# Path resolution uses BASH_SOURCE[0] which is the absolute path of this
# load.bash file when sourced — robust regardless of how bats was invoked
# (relative or absolute paths, symlinks, etc.).

# tests/bats/helpers/load.bash -> tests/bats
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# tests/bats -> repo root
ROOT_DIR="$(cd "${TESTS_DIR}/../.." && pwd -P)"

LIB_CLUSTER="${ROOT_DIR}/lib/cluster.sh"

if [[ ! -f "${LIB_CLUSTER}" ]]; then
  echo "FATAL: no se encontró lib/cluster.sh en ${LIB_CLUSTER}" >&2
  echo "  ROOT_DIR=${ROOT_DIR}" >&2
  exit 1
fi

# Source the library under test. `source` preserves functions in this shell.
# shellcheck disable=SC1090
source "${LIB_CLUSTER}"

# Common assertions used by multiple .bats files.

# assert_eq <actual> <expected> [message]
assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="${3:-assertion failed}"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $msg" >&2
    echo "  expected: <$expected>" >&2
    echo "  actual:   <$actual>" >&2
    return 1
  fi
}

# assert_status <expected_rc> <command...>
assert_status() {
  local expected="$1"
  shift
  local rc=0
  "$@" || rc=$?
  if [[ "$rc" -ne "$expected" ]]; then
    echo "FAIL: '$*' exited $rc, expected $expected" >&2
    return 1
  fi
}
