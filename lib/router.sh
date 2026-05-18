#!/usr/bin/env bash

declare -A GLOBAL_FLAG_HANDLERS=(
  [verbosity]=handle_flag_verbosity
  [version]=handle_flag_version
  [help]=handle_flag_help
)

declare -A RUN_FLAG_HANDLERS=(
  [ctx]=handle_run_ctx
  [dry_run]=handle_run_dry_run
  [verbosity]=handle_flag_verbosity
  [help]=handle_flag_help
)

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
  local spec=$1
  local flag=$2
  local field=$3

  jq -er --arg flag "$flag" --arg field "$field" '.flags[$flag][$field] // empty' "$spec"
}

args_drop() {
  local count=$1
  local -n _arr=$2
  _arr=("${_arr[@]:count}")
}

route_flags() {
  local -n route_args=$1
  local -n handlers=$2
  local -n route_opts=$3

  while ((${#route_args[@]} > 0)); do
    local token=${route_args[0]}
    local kind=
    local handler=

    kind=$(cli_flag_value "${SHBANG_RT[cli_spec]}" "$token" kind 2>/dev/null || true)
    [[ -n $kind ]] || return 0

    handler=${handlers[$kind]:-}
    [[ -n $handler ]] || die "unsupported flag: $token"

    "$handler" route_args route_opts
  done
}

route_cli() {
  local -a args=("$@")
  local -A opts=()

  route_flags args GLOBAL_FLAG_HANDLERS opts

  local command=${args[0]:-}
  [[ -n $command ]] || die "missing command"
  args_drop 1 args

  local handler=${SHBANG_COMMANDS[$command]:-}
  [[ -n $handler ]] || die "unknown command: $command"

  "$handler" "${args[@]}"
}

parse_run_args() {
  local -n out=$1
  shift

  local -a args=("$@")
  out=()

  [[ ${#args[@]} -gt 0 ]] || die "missing playbook"
  out[playbook]=${args[0]}
  args_drop 1 args

  route_flags args RUN_FLAG_HANDLERS out
  [[ ${#args[@]} -eq 0 ]] || die "unknown arg: ${args[0]}"

  [[ -f ${out[playbook]} ]] || die "playbook not found: ${out[playbook]}"
  [[ -n ${out[ctx]:-} ]] || die "missing --ctx"
  [[ -f ${out[ctx]} ]] || die "context not found: ${out[ctx]}"
}

handle_flag_verbosity() {
  local -n flag_args=$1
  local token=${flag_args[0]}

  SHBANG_RT[verbosity]=$(cli_flag_value "${SHBANG_RT[cli_spec]}" "$token" level)
  log_set_verbosity "${SHBANG_RT[verbosity]}"

  args_drop 1 flag_args
}

handle_flag_version() {
  printf '%s\n' "${SHBANG_RT[version]}"
  exit 0
}

handle_flag_help() {
  print_help "${SHBANG_RT[cli_spec]}"
  exit 0
}

handle_run_ctx() {
  local -n ctx_args=$1
  local -n ctx_opts=$2

  ctx_opts[ctx]=${ctx_args[1]:-}
  [[ -n ${ctx_opts[ctx]} ]] || die "missing value for --ctx"

  args_drop 2 ctx_args
}

handle_run_dry_run() {
  local -n dry_args=$1

  SHBANG_RT[dry_run]=true
  args_drop 1 dry_args
}
