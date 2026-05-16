#!/usr/bin/env bash

# ── Flag handler tables ───────────────────────────────────────────────────────

declare -A GLOBAL_FLAG_HANDLERS
GLOBAL_FLAG_HANDLERS[verbosity]=handle_flag_verbosity
GLOBAL_FLAG_HANDLERS[version]=handle_flag_version
GLOBAL_FLAG_HANDLERS[help]=handle_flag_help

declare -A RUN_FLAG_HANDLERS
RUN_FLAG_HANDLERS[ctx]=handle_run_ctx
RUN_FLAG_HANDLERS[dry_run]=handle_run_dry_run
RUN_FLAG_HANDLERS[verbosity]=handle_flag_verbosity
RUN_FLAG_HANDLERS[help]=handle_flag_help

# ── Helpers ───────────────────────────────────────────────────────────────────

print_help() {
  local spec=$1
  jq -r '
    .help.usage[],
    "",
    "verbosity:",
    (.verbosity | to_entries[] | "  \(.key)\t\(.value.name) - \(.value.description)"),
    "",
    "commands:",
    (.commands | to_entries[] | "  \(.key)\t\(.value.description)")
  ' "$spec"
}

cli_flag_value() {
  jq -r --arg flag "$2" --arg field "$3" '.flags[$flag][$field] // empty' "$1"
}

# ── Routing ───────────────────────────────────────────────────────────────────

# Consumes leading flag tokens from the args array, dispatching each to its
# handler. Stops at the first token that isn't in the spec and returns 0.
route_flags() {
  local -n _rf_args=$1
  local -n _rf_handlers=$2
  local -n _rf_opts=$3
  local -n rt=$SHBANG_RT_NAME

  while ((${#_rf_args[@]} > 0)); do
    local token=${_rf_args[0]}
    local kind handler

    kind=$(cli_flag_value "${rt[cli_spec]}" "$token" kind)
    [[ -n $kind ]] || return 0

    handler=${_rf_handlers[$kind]:-}
    [[ -n $handler ]] || die "unsupported flag: $token"

    "$handler" _rf_args _rf_opts
  done
}

route_cli() {
  local -n rt=$SHBANG_RT_NAME
  local -a args=("$@")
  local -A opts=()

  route_flags args GLOBAL_FLAG_HANDLERS opts

  local command=${args[0]:-}
  [[ -n $command ]] || die "missing command"
  args=("${args[@]:1}")

  local handler=${SHBANG_COMMANDS[$command]:-}
  [[ -n $handler ]] || die "unknown command: $command"

  "$handler" "${args[@]}"
}

parse_run_args() {
  local -n _pra_args=$1
  local -n _pra_out=$2

  [[ ${#_pra_args[@]} -gt 0 ]] || die "missing playbook"
  _pra_out[playbook]=${_pra_args[0]}
  _pra_args=("${_pra_args[@]:1}")

  route_flags _pra_args RUN_FLAG_HANDLERS _pra_out
  [[ ${#_pra_args[@]} -eq 0 ]] || die "unknown arg: ${_pra_args[0]}"

  [[ -f ${_pra_out[playbook]} ]] || die "playbook not found: ${_pra_out[playbook]}"
  [[ -n ${_pra_out[ctx]:-}    ]] || die "missing --ctx"
  [[ -f ${_pra_out[ctx]}      ]] || die "context not found: ${_pra_out[ctx]}"
}

# ── Flag handlers ─────────────────────────────────────────────────────────────

handle_flag_verbosity() {
  local -n _hv_args=$1
  local -n rt=$SHBANG_RT_NAME
  local token=${_hv_args[0]}
  rt[verbosity]=$(cli_flag_value "${rt[cli_spec]}" "$token" level)
  _hv_args=("${_hv_args[@]:1}")
}

handle_flag_version() {
  local -n rt=$SHBANG_RT_NAME
  printf '%s\n' "${rt[version]}"
  exit 0
}

handle_flag_help() {
  local -n rt=$SHBANG_RT_NAME
  print_help "${rt[cli_spec]}"
  exit 0
}

handle_run_ctx() {
  local -n _ctx_args=$1
  local -n _ctx_opts=$2
  _ctx_opts[ctx]=${_ctx_args[1]:-}
  [[ -n ${_ctx_opts[ctx]} ]] || die "missing value for --ctx"
  _ctx_args=("${_ctx_args[@]:2}")
}

handle_run_dry_run() {
  local -n _hrd_args=$1
  local -n rt=$SHBANG_RT_NAME
  rt[dry_run]=true
  _hrd_args=("${_hrd_args[@]:1}")
}
