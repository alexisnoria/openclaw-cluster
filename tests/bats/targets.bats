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

# ----------------------------------------------------------------------------
# _resolve_target_ids — same logic, one id per line, used by start/stop
# ----------------------------------------------------------------------------

@test "_resolve_target_ids 'all' echoes provided ids one per line" {
  result=$(_resolve_target_ids all 1 2 3)
  [ "$result" = $'1\n2\n3' ]
}

@test "_resolve_target_ids 'all' with no ids returns empty" {
  result=$(_resolve_target_ids all)
  [ -z "$result" ]
}

@test "_resolve_target_ids 'range:2-5' expands 2..5" {
  result=$(_resolve_target_ids range:2-5)
  [ "$result" = $'2\n3\n4\n5' ]
}

@test "_resolve_target_ids 'range:7-7' returns single id" {
  result=$(_resolve_target_ids range:7-7)
  [ "$result" = "7" ]
}

@test "_resolve_target_ids single id passes through" {
  result=$(_resolve_target_ids 42)
  [ "$result" = "42" ]
}

@test "_resolve_target_ids matches expand_targets (alias contract)" {
  # _resolve_target_ids MUST produce the same id set as expand_targets
  for target in "all:1 2 3" "range:1-3" "5"; do
    a=$(expand_targets ${target%%:*} ${target#*:} 2>/dev/null | tr '\n' ' ')
    b=$(_resolve_target_ids ${target%%:*} ${target#*:} 2>/dev/null | tr '\n' ' ')
    [ "$a" = "$b" ] || {
      echo "mismatch for $target: expand=$a resolve=$b" >&2
      return 1
    }
  done
}
