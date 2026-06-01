#!/usr/bin/env bats
# tests/bats/validation.bats — pure validation helpers.

setup() {
  load helpers/load
}

@test "validate_number accepts zero" {
  run validate_number "0"
  [ "$status" -eq 0 ]
}

@test "validate_number accepts positive integers" {
  run validate_number "42"
  [ "$status" -eq 0 ]
}

@test "validate_number accepts large integers" {
  run validate_number "9999999"
  [ "$status" -eq 0 ]
}

@test "validate_number rejects negative numbers" {
  run validate_number "-1"
  [ "$status" -ne 0 ]
}

@test "validate_number rejects letters" {
  run validate_number "abc"
  [ "$status" -ne 0 ]
}

@test "validate_number rejects empty string" {
  run validate_number ""
  [ "$status" -ne 0 ]
}

@test "validate_number rejects floats" {
  run validate_number "3.14"
  [ "$status" -ne 0 ]
}

@test "validate_range accepts N-M" {
  run validate_range "1-5"
  [ "$status" -eq 0 ]
}

@test "validate_range rejects single number" {
  run validate_range "5"
  [ "$status" -ne 0 ]
}

@test "validate_range rejects letters" {
  run validate_range "a-b"
  [ "$status" -ne 0 ]
}

@test "validate_yes accepts y/Y/yes/Yes/YES" {
  for v in y Y yes Yes YES YeS; do
    validate_yes "$v" || { echo "expected '$v' as yes"; return 1; }
  done
}

@test "validate_yes rejects no" {
  run validate_yes "no"
  [ "$status" -ne 0 ]
}

@test "validate_yes rejects empty" {
  run validate_yes ""
  [ "$status" -ne 0 ]
}
