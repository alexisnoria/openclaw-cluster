#!/usr/bin/env bash
# lib/logging.sh — Colored output, level-based logging, and the project
# header banner. No side effects beyond printing to stdout/stderr.
#
# Source from openclaw-cluster.sh or any lib/*.sh. Idempotent (safe to
# source multiple times).
#
# Provides:
#   - Color constants: CLR_RESET, CLR_BOLD, CLR_DIM, CLR_GREEN, CLR_YELLOW,
#     CLR_BLUE, CLR_MAGENTA, CLR_CYAN, CLR_RED, CLR_ORANGE
#   - Header / banners: print_header
#   - Level helpers:    print_success, print_info, print_warn, print_error,
#                       print_cmd
#   - Configuration:    logging_set_level <debug|info|warn|error>
#                       logging_init <color|no-color>

if [[ -n "${__LIB_LOGGING_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_LOGGING_SOURCED=1

# ----------------------------------------------------------------------------
# Color codes
# ----------------------------------------------------------------------------
# All CLR_* are part of the module's public API (consumed by callers). The
# C_* aliases provide short names.
# shellcheck disable=SC2034
CLR_RESET='\033[0m'
# shellcheck disable=SC2034
CLR_BOLD='\033[1m'
# shellcheck disable=SC2034
CLR_DIM='\033[2m'
# shellcheck disable=SC2034
CLR_GREEN='\033[0;32m'
# shellcheck disable=SC2034
CLR_YELLOW='\033[1;33m'
# shellcheck disable=SC2034
CLR_BLUE='\033[0;34m'
# shellcheck disable=SC2034
CLR_MAGENTA='\033[0;35m'
# shellcheck disable=SC2034
CLR_CYAN='\033[0;36m'
# shellcheck disable=SC2034
CLR_RED='\033[0;31m'
# shellcheck disable=SC2034
CLR_ORANGE='\033[38;5;208m'

# Inherit from lib/cluster.sh if those exist (C_RED, C_GREEN, ...). They are
# aliases; not all callers use them.
# shellcheck disable=SC2034
C_RED="${CLR_RED}"
# shellcheck disable=SC2034
C_GREEN="${CLR_GREEN}"
# shellcheck disable=SC2034
C_YELLOW="${CLR_YELLOW}"
# shellcheck disable=SC2034
C_BLUE="${CLR_BLUE}"
# shellcheck disable=SC2034
C_RESET="${CLR_RESET}"

# LOG_USE_COLOR is read by callers to decide if to wrap output in escapes
# shellcheck disable=SC2034
LOG_USE_COLOR="${LOG_USE_COLOR:-1}"

# ----------------------------------------------------------------------------
# Log level (default: info)
# ----------------------------------------------------------------------------
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_USE_COLOR=1

_log_level_value() {
  case "$1" in
    debug) echo 0 ;;
    info) echo 1 ;;
    warn) echo 2 ;;
    error) echo 3 ;;
    *) echo 1 ;;
  esac
}

# logging_set_level <level>
logging_set_level() {
  LOG_LEVEL="$1"
}

# logging_init <color|no-color>
logging_init() {
  case "$1" in
    no-color | nocolor | plain)
      LOG_USE_COLOR=0
      CLR_RESET='' CLR_BOLD='' CLR_DIM='' CLR_GREEN='' CLR_YELLOW=''
      CLR_BLUE='' CLR_MAGENTA='' CLR_CYAN='' CLR_RED='' CLR_ORANGE=''
      C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
      ;;
    color | colored | "")
      LOG_USE_COLOR=1
      # shellcheck disable=SC2034
      CLR_RESET='\033[0m'
      # shellcheck disable=SC2034
      CLR_BOLD='\033[1m'
      # shellcheck disable=SC2034
      CLR_DIM='\033[2m'
      # shellcheck disable=SC2034
      CLR_GREEN='\033[0;32m'
      # shellcheck disable=SC2034
      CLR_YELLOW='\033[1;33m'
      # shellcheck disable=SC2034
      CLR_BLUE='\033[0;34m'
      # shellcheck disable=SC2034
      CLR_MAGENTA='\033[0;35m'
      # shellcheck disable=SC2034
      CLR_CYAN='\033[0;36m'
      # shellcheck disable=SC2034
      CLR_RED='\033[0;31m'
      # shellcheck disable=SC2034
      CLR_ORANGE='\033[38;5;208m'
      # shellcheck disable=SC2034
      C_RED="${CLR_RED}"
      # shellcheck disable=SC2034
      C_GREEN="${CLR_GREEN}"
      # shellcheck disable=SC2034
      C_YELLOW="${CLR_YELLOW}"
      # shellcheck disable=SC2034
      C_BLUE="${CLR_BLUE}"
      # shellcheck disable=SC2034
      C_RESET="${CLR_RESET}"
      ;;
    *)
      return 1
      ;;
  esac
}

# Auto-disable colors when not on a TTY (but allow NO_COLOR env var)
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
  logging_init no-color
fi

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------
print_header() {
  echo -e "${CLR_ORANGE}${CLR_BOLD}"
  echo '╔══════════════════════════════════════════════════════════╗'
  echo '║        🦞 OpenClaw Cluster Manager                       ║'
  echo '╚══════════════════════════════════════════════════════════╝'
  echo -e "${CLR_RESET}"
}

print_success() { echo -e "${CLR_GREEN}✅ $1${CLR_RESET}"; }
print_info() { echo -e "${CLR_BLUE}ℹ️  $1${CLR_RESET}"; }
print_warn() { echo -e "${CLR_YELLOW}⚠️  $1${CLR_RESET}" >&2; }
print_error() { echo -e "${CLR_RED}❌ $1${CLR_RESET}" >&2; }
print_cmd() { echo -e "${CLR_CYAN}${CLR_BOLD}$1${CLR_RESET}"; }

# Level-aware log (use these for verbose/debug output)
_log_emit() {
  local level="$1"
  local msg="$2"
  local current
  current=$(_log_level_value "$LOG_LEVEL")
  local incoming
  incoming=$(_log_level_value "$level")
  if [[ "$incoming" -lt "$current" ]]; then
    return 0
  fi
  case "$level" in
    debug) echo -e "${CLR_DIM}🔍 ${msg}${CLR_RESET}" >&2 ;;
    info) print_info "$msg" ;;
    warn) print_warn "$msg" ;;
    error) print_error "$msg" ;;
    *)
      print_info "$msg"
      return 1
      ;;
  esac
}

log_debug() { _log_emit debug "$1"; }
log_info() { _log_emit info "$1"; }
log_warn() { _log_emit warn "$1"; }
log_error() { _log_emit error "$1"; }
