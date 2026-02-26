#!/usr/bin/env bash
# lib/log.sh — Logging utilities
# Dual output: colored terminal + plain text log file.

# Colors
readonly _CLR_RESET='\033[0m'
readonly _CLR_RED='\033[1;31m'
readonly _CLR_GREEN='\033[1;32m'
readonly _CLR_YELLOW='\033[1;33m'
readonly _CLR_CYAN='\033[1;36m'
readonly _CLR_BOLD='\033[1m'
readonly _CLR_DIM='\033[2m'

_log() {
  local level="$1" color="$2"
  shift 2
  local msg="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  # Terminal (colored)
  printf '%b[%-5s]%b %s\n' "$color" "$level" "$_CLR_RESET" "$msg" >&2

  # Log file (plain)
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf "[%s] [%-5s] %s\n" "$timestamp" "$level" "$msg" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

log_info() {
  _log "INFO" "$_CLR_GREEN" "$@"
}

log_warn() {
  _log "WARN" "$_CLR_YELLOW" "$@"
}

log_error() {
  _log "ERROR" "$_CLR_RED" "$@"
}

log_debug() {
  if [[ "${DEBUG:-0}" == "1" ]]; then
    _log "DEBUG" "$_CLR_DIM" "$@"
  fi
}

log_section() {
  local title="$1"
  local line
  line="$(printf '=%.0s' {1..60})"
  printf '\n%b%b%s%b\n' "$_CLR_CYAN" "$_CLR_BOLD" "$line" "$_CLR_RESET" >&2
  printf '%b%b  %s%b\n' "$_CLR_CYAN" "$_CLR_BOLD" "$title" "$_CLR_RESET" >&2
  printf '%b%b%s%b\n\n' "$_CLR_CYAN" "$_CLR_BOLD" "$line" "$_CLR_RESET" >&2

  if [[ -n "${LOG_FILE:-}" ]]; then
    printf "\n%s\n  %s\n%s\n\n" "$line" "$title" "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# Run a command with logging. Logs the command, streams output, and checks exit code.
run_logged() {
  local desc="$1"
  shift
  log_info "$desc"
  log_debug "Running: $*"

  if [[ -n "${LOG_FILE:-}" ]]; then
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}
  else
    "$@"
    local rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    log_error "$desc — failed (exit code $rc)"
    return "$rc"
  fi
  return 0
}

# Fatal error: log and exit
die() {
  log_error "$@"
  exit 1
}
