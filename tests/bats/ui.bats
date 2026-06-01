#!/usr/bin/env bats
# tests/bats/ui.bats — interactive input helpers.

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/logging.sh"
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/ui.sh"
  logging_init color
}

@test "read_input echoes the user value" {
  result=$(echo "my-value" | read_input "Prompt")
  [ "$result" = "my-value" ]
}

@test "read_input uses the default when empty input" {
  result=$(echo "" | read_input "Prompt" "fallback")
  [ "$result" = "fallback" ]
}

@test "read_input uses the default when just newline" {
  result=$(printf "\n" | read_input "Prompt" "fb")
  [ "$result" = "fb" ]
}

@test "read_input empty value and no default returns empty" {
  result=$(echo "" | read_input "Prompt")
  [ "$result" = "" ]
}

@test "read_input writes prompt to stderr not stdout" {
  out=$(echo "x" | read_input "Enter value" 2>/dev/null)
  err=$(echo "x" | read_input "Enter value" 2>&1 1>/dev/null)
  [ "$out" = "x" ]
  [[ "$err" == *"Enter value"* ]]
}

@test "read_input default suffix shows when default provided" {
  err=$(echo "x" | read_input "Prompt" "def" 2>&1 1>/dev/null)
  [[ "$err" == *"[def]"* ]]
}

@test "read_confirm accepts y" {
  result=$(echo "y" | read_confirm "Continue?" && echo yes)
  [ "$result" = "yes" ]
}

@test "read_confirm accepts Y" {
  result=$(echo "Y" | read_confirm "Continue?" && echo yes)
  [ "$result" = "yes" ]
}

@test "read_confirm accepts yes" {
  result=$(echo "yes" | read_confirm "Continue?" && echo yes)
  [ "$result" = "yes" ]
}

@test "read_confirm accepts Yes" {
  result=$(echo "Yes" | read_confirm "Continue?" && echo yes)
  [ "$result" = "yes" ]
}

@test "read_confirm rejects n" {
  result=$(echo "n" | read_confirm "Continue?" && echo yes || echo no)
  [ "$result" = "no" ]
}

@test "read_confirm rejects empty" {
  result=$(echo "" | read_confirm "Continue?" && echo yes || echo no)
  [ "$result" = "no" ]
}

@test "read_confirm rejects no" {
  result=$(echo "no" | read_confirm "Continue?" && echo yes || echo no)
  [ "$result" = "no" ]
}

@test "read_confirm_strong accepts exact word" {
  result=$(echo "DESTRUIR-instance-1" | read_confirm_strong "Confirm?" "DESTRUIR-instance-1" && echo ok)
  [ "$result" = "ok" ]
}

@test "read_confirm_strong rejects wrong word" {
  result=$(echo "nope" | read_confirm_strong "Confirm?" "DESTRUIR-instance-1" && echo ok || echo no)
  [ "$result" = "no" ]
}

@test "read_confirm_strong rejects prefix match" {
  result=$(echo "DESTRUIR" | read_confirm_strong "Confirm?" "DESTRUIR-instance-1" && echo ok || echo no)
  [ "$result" = "no" ]
}

@test "read_confirm_strong is case-sensitive" {
  result=$(echo "destruir-instance-1" | read_confirm_strong "Confirm?" "DESTRUIR-instance-1" && echo ok || echo no)
  [ "$result" = "no" ]
}
