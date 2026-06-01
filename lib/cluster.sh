#!/usr/bin/env bash
# lib/cluster.sh — Pure functions extracted from openclaw-cluster.sh
#
# This module contains pure / side-effect-free helpers that can be unit-tested
# without Docker, without a real instance directory, and without any state.
# It is sourced by tests/bats/helpers/load.bash and (in a future refactor)
# by the main openclaw-cluster.sh script.
#
# Rules:
#   - Functions MUST NOT call docker, openssl, or touch the filesystem.
#   - Functions MUST be deterministic (same input → same output).
#   - Use lower_snake_case names, return via stdout or exit code only.

# Avoid loading twice
if [[ -n "${__LIB_CLUSTER_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || true
fi
__LIB_CLUSTER_SOURCED=1

# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------

# validate_number <str> -> exit 0 if integer >= 0
validate_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# validate_range <str> -> exit 0 if matches N-M
validate_range() {
  [[ "$1" =~ ^[0-9]+-[0-9]+$ ]]
}

# validate_yes <str> -> exit 0 if y/Y/yes/true
validate_yes() {
  [[ "$1" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ----------------------------------------------------------------------------
# Port and naming helpers
# ----------------------------------------------------------------------------

# instance_gateway_port <id> [<base>] -> echo integer port
#   base defaults to 18000, stride is 22
instance_gateway_port() {
  local id="$1"
  local base="${2:-18000}"
  echo $((base + (id * 22)))
}

# instance_bridge_port <id> [<base>] -> echo integer port
instance_bridge_port() {
  local id="$1"
  local base="${2:-18000}"
  echo $((base + (id * 22) + 1))
}

# instance_name <id> -> echo "instance-<id>"
instance_name() {
  echo "instance-$1"
}

# instance_dir <id> [<root>] -> echo path
instance_dir() {
  local id="$1"
  local root="${2:-./instances}"
  echo "${root}/instance-${id}"
}

# ----------------------------------------------------------------------------
# Range expansion (pure)
# ----------------------------------------------------------------------------

# expand_targets "all"|"range:1-3"|"5" [<ids...>] -> echoes ids separated by space
# If first arg is "all", uses subsequent args as the available id list.
expand_targets() {
  local target="$1"
  shift
  case "$target" in
    all)
      if [[ "$#" -eq 0 ]]; then
        return 0
      fi
      local item
      for item in "$@"; do
        echo "$item"
      done
      ;;
    range:*)
      local range="${target#range:}"
      local start="${range%%-*}"
      local end="${range##*-}"
      local i
      for i in $(seq "$start" "$end"); do
        echo "$i"
      done
      ;;
    *)
      echo "$target"
      ;;
  esac
}

# ----------------------------------------------------------------------------
# Token / path safety
# ----------------------------------------------------------------------------

# is_safe_token <str> -> exit 0 if matches hex 64 (32 bytes)
is_safe_token() {
  [[ "$1" =~ ^[0-9a-fA-F]{64}$ ]]
}

# safe_path_component <str> -> echo "str" if it only contains [a-zA-Z0-9._-]
safe_path_component() {
  local s="$1"
  if [[ "$s" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "$s"
    return 0
  fi
  return 1
}

# ----------------------------------------------------------------------------
# Color helpers (no-op in non-TTY)
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED='\033[0;31m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[1;33m'
  C_BLUE='\033[0;34m'
  C_RESET='\033[0m'
else
  # shellcheck disable=SC2034
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
fi
