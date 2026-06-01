#!/usr/bin/env bats
# tests/bats/targets.bats — target expansion for start/stop/scale.

setup() {
  load helpers/load
}

@test "expand_targets all returns the provided list" {
  result=$(expand_targets all 1 2 3 | tr '\n' ' ')
  [ "$result" = "1 2 3 " ]
}

@test "expand_targets all with empty list returns nothing" {
  result=$(expand_targets all | tr '\n' ' ')
  [ "$result" = "" ]
}

@test "expand_targets range expands inclusive" {
  result=$(expand_targets range:1-3 | tr '\n' ' ')
  [ "$result" = "1 2 3 " ]
}

@test "expand_targets range handles single element" {
  result=$(expand_targets range:5-5 | tr '\n' ' ')
  [ "$result" = "5 " ]
}

@test "expand_targets range handles reverse-looking range" {
  result=$(expand_targets range:1-10 | wc -l | tr -d ' ')
  [ "$result" = "10" ]
}

@test "expand_targets single id passes through" {
  result=$(expand_targets 7)
  [ "$result" = "7" ]
}
