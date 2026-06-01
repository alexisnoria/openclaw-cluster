#!/usr/bin/env bats
# tests/bats/safety.bats — security and safety primitives.

setup() {
  load helpers/load
}

@test "is_safe_token accepts 64-char hex" {
  run is_safe_token "$(printf 'a%.0s' {1..64})"
  [ "$status" -eq 0 ]
}

@test "is_safe_token accepts mixed case hex" {
  # 32 chars of alternating "Ab" + "Cd" patterns = 64 chars, all hex
  token=$(python3 -c "print(('Ab' * 16 + 'Cd' * 16)[:64])")
  run is_safe_token "$token"
  [ "$status" -eq 0 ]
}

@test "is_safe_token rejects short strings" {
  run is_safe_token "abc"
  [ "$status" -ne 0 ]
}

@test "is_safe_token rejects non-hex chars" {
  run is_safe_token "$(printf 'g%.0s' {1..64})"
  [ "$status" -ne 0 ]
}

@test "safe_path_component accepts normal names" {
  result=$(safe_path_component "instance-1")
  [ "$result" = "instance-1" ]
}

@test "safe_path_component rejects path traversal" {
  run safe_path_component "../etc/passwd"
  [ "$status" -ne 0 ]
}

@test "safe_path_component rejects slashes" {
  run safe_path_component "a/b"
  [ "$status" -ne 0 ]
}

@test "safe_path_component rejects empty" {
  run safe_path_component ""
  [ "$status" -ne 0 ]
}
