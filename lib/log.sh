#!/usr/bin/env bash

SHBANG_VERBOSITY=0

log_set_verbosity() {
  local level=$1
  SHBANG_VERBOSITY=$level
}

log_at() {
  local required=$1
  local label=$2
  shift 2

  if (( SHBANG_VERBOSITY >= required )); then
    printf '[sh.bang:%s] %s\n' "$label" "$*" >&2
  fi
}

log_info() {
  log_at 1 info "$@"
}

log_debug() {
  log_at 2 debug "$@"
}

log_trace() {
  log_at 3 trace "$@"
}

log_wire() {
  log_at 4 wire "$@"
}

die() {
  printf '[sh.bang:error] %s\n' "$*" >&2
  exit 1
}

# curl wrapper — passes -v at wire verbosity, silent otherwise.
# Usage: shbang_curl <url> -o <dest> [extra curl args...]
shbang_curl() {
  local -a curl_args=()
  if (( SHBANG_VERBOSITY >= 4 )); then
    curl_args+=(-v)
  else
    curl_args+=(-sS)
  fi
  log_debug "curl $*"
  curl "${curl_args[@]}" "$@"
}
