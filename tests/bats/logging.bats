#!/usr/bin/env bats
# tests/bats/logging.bats — colored output and level helpers.

setup() {
  load helpers/load
  # Source the logging module under test
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/lib/logging.sh"
  # Force colors ON for predictable assertions (bats captures stdout, so the
  # module's auto-detect thinks we're not a TTY)
  logging_init color
}

@test "logging module is idempotent (sourcing twice doesn't break)" {
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/logging.sh"
  [ -n "${CLR_GREEN}" ]
  [ -n "${CLR_RED}" ]
}

@test "print_success writes to stdout with success prefix" {
  result=$(print_success "it works")
  [[ "$result" == *"✅ it works"* ]]
}

@test "print_info writes to stdout with info prefix" {
  result=$(print_info "hello")
  [[ "$result" == *"ℹ️  hello"* ]]
}

@test "print_warn writes to stderr with warning prefix" {
  result=$(print_warn "watch out" 2>&1 1>/dev/null)
  [[ "$result" == *"⚠️  watch out"* ]]
}

@test "print_error writes to stderr with error prefix" {
  result=$(print_error "boom" 2>&1 1>/dev/null)
  [[ "$result" == *"❌ boom"* ]]
}

@test "print_header includes the project name" {
  result=$(print_header)
  [[ "$result" == *"OpenClaw Cluster Manager"* ]]
}

@test "logging_set_level changes the active level" {
  logging_set_level error
  [ "${LOG_LEVEL}" = "error" ]
}

@test "logging_init no-color strips ANSI codes" {
  logging_init no-color
  [ -z "${CLR_GREEN}" ]
  [ -z "${CLR_RED}" ]
}

@test "logging_init color restores ANSI codes" {
  logging_init no-color
  logging_init color
  [ -n "${CLR_GREEN}" ]
  [ -n "${CLR_RED}" ]
}

@test "log_info respects level filter (info hidden when level=error)" {
  logging_set_level error
  # Capture stderr (log_info uses >&2 for debug, stdout for info)
  out=$(log_info "should be hidden" 2>&1)
  [ -z "$out" ]
}

@test "log_error always shows when level=error" {
  logging_set_level error
  out=$(log_error "always visible" 2>&1)
  [[ "$out" == *"always visible"* ]]
}

@test "log_warn is hidden when level=error" {
  logging_set_level error
  out=$(log_warn "hidden" 2>&1)
  [ -z "$out" ]
}

@test "log_debug is hidden at default level (info)" {
  logging_set_level info
  out=$(log_debug "hidden" 2>&1)
  [ -z "$out" ]
}

@test "log_debug is shown at level debug" {
  logging_set_level debug
  out=$(log_debug "shown" 2>&1)
  [[ "$out" == *"shown"* ]]
}
