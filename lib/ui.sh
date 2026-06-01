#!/usr/bin/env bash
# lib/ui.sh — Interactive input helpers and table rendering. Pure: no FS,
# no network. Reads from stdin (fd 0) via read -r; writes prompts to stderr
# so they don't pollute captured stdout.
#
# Source from openclaw-cluster.sh or any lib/*.sh. Idempotent.
#
# Provides:
#   - read_input     <prompt> [default]       -> echoes user input
#   - read_confirm   <prompt>                 -> exit 0 if y/yes
#   - read_confirm_strong <prompt> <word>     -> exit 0 if input == word
#   - print_table    <header_pairs...> <rows...>  -> ASCII table
#   - section_header <text>                  -> bold section divider

if [[ -n "${__LIB_UI_SOURCED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi
__LIB_UI_SOURCED=1

# Requires lib/logging.sh for color constants
if [[ -z "${CLR_CYAN:-}" ]]; then
  # shellcheck source=lib/logging.sh
  # shellcheck disable=SC1090
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
fi

# ----------------------------------------------------------------------------
# Interactive input
# ----------------------------------------------------------------------------

# read_input <prompt> [default]
#   Prompts on stderr (so stdout stays clean for value capture).
#   Echoes the user's input (or default) to stdout.
read_input() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    echo -en "${CLR_CYAN}${prompt} [${default}]: ${CLR_RESET}" >&2
  else
    echo -en "${CLR_CYAN}${prompt}: ${CLR_RESET}" >&2
  fi
  read -r value
  echo "${value:-$default}"
}

# read_confirm <prompt> -> exit 0 if user typed y/Y/yes
read_confirm() {
  local prompt="$1"
  local value
  echo -en "${CLR_YELLOW}${prompt} [y/N]: ${CLR_RESET}" >&2
  read -r value
  [[ "$value" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# read_confirm_strong <prompt> <confirm_word> -> exit 0 if input == word
read_confirm_strong() {
  local prompt="$1"
  local confirm_word="$2"
  local value
  echo -en "${CLR_RED}${prompt} Escribe '${confirm_word}' para confirmar: ${CLR_RESET}" >&2
  read -r value
  [[ "$value" == "$confirm_word" ]]
}

# ----------------------------------------------------------------------------
# Visual helpers
# ----------------------------------------------------------------------------

# section_header <text>
section_header() {
  echo -e "${CLR_BOLD}${CLR_MAGENTA}── $1 ──${CLR_RESET}"
}

# print_table <col1_width> <col2_width> ... -- <row1c1> <row1c2> ... <row2c1> ...
# Each row is a sequence of values; widths are inferred from the first
# occurrence of each column. Simpler alternative: pass rows via stdin.
#
# For the cluster manager we use a fixed-width helper below.
print_table_row() {
  local sep="$1"
  shift
  printf "%s" "$sep"
  printf " %-*s " "${COL_WIDTHS[0]}" "$1"
  shift
  local i=1
  for v in "$@"; do
    printf "${sep} %-*s " "${COL_WIDTHS[$i]}" "$v"
    i=$((i + 1))
  done
  printf "%s\n" "$sep"
}
