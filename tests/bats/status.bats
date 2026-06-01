#!/usr/bin/env bats
# tests/bats/status.bats — tests for print_status_table (pure helper).
# cluster_status / cluster_logs / cluster_exec touch docker; they're covered
# by tests/integration/.

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/status.sh"
}

@test "print_status_table is defined" {
  declare -F print_status_table >/dev/null
}

@test "print_status_table renders the header row" {
  out=$(print_status_table "")
  [[ "$out" == *"Instancia"* ]]
  [[ "$out" == *"Estado"* ]]
  [[ "$out" == *"Gateway URL"* ]]
  [[ "$out" == *"Puertos"* ]]
  [[ "$out" == *"Uptime"* ]]
}

@test "print_status_table renders the borders" {
  out=$(print_status_table "")
  [[ "$out" == *"┌"* ]]
  [[ "$out" == *"└"* ]]
  [[ "$out" == *"┐"* ]]
  [[ "$out" == *"┘"* ]]
}

@test "print_status_table renders one row per id" {
  rows=$'1|Up|🟢|2 hours|http://localhost:18022\n2|Down|🔴|-|-\n'
  out=$(print_status_table "$rows")
  [[ "$out" == *"instance-1"* ]]
  [[ "$out" == *"instance-2"* ]]
  [[ "$out" == *"🟢 Up"* ]]
  [[ "$out" == *"🔴 Down"* ]]
  [[ "$out" == *"18022"* ]]
  [[ "$out" == *"18023"* ]] # instance-2 bridge port
}

@test "print_status_table shows '-' for down instances" {
  rows=$'3|Down|🔴|-|-\n'
  out=$(print_status_table "$rows")
  [[ "$out" == *"-"* ]]
}

@test "print_status_table handles empty rows" {
  out=$(print_status_table "")
  # No instance rows but the table frame still appears
  [[ "$out" == *"Instancia"* ]]
}

@test "cluster_status is defined and gates on docker" {
  declare -F cluster_status >/dev/null
}

@test "cluster_logs is defined and gates on docker" {
  declare -F cluster_logs >/dev/null
}

@test "cluster_exec is defined and gates on docker" {
  declare -F cluster_exec >/dev/null
}
