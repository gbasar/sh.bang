#!/usr/bin/env bash

declare -A EVENT_HANDLERS=(
  [console]=event_console
  [file]=event_file
  [expand]=event_expand
  [dispatch]=event_dispatch
)

declare -A CONSOLE_EVENT_FORMATTERS=(
  [run.loaded]=console_run_loaded
  [parser.for_each]=console_parser_for_each
  [parser.pipe]=console_parser_pipe
  [parser.label]=console_parser_label
  [cmd.local]=console_cmd_local
  [cmd.scp]=console_cmd_scp
  [cmd.ssh]=console_cmd_ssh
)

emit() {
  local -n emit_event=$1
  local -a handlers
  local name

  read -r -a handlers <<< "${SHBANG_RT[event_handlers]}"

  for name in "${handlers[@]}"; do
    local fn=${EVENT_HANDLERS[$name]:-}
    [[ -n $fn ]] || die "unknown event handler: $name"
    "$fn" emit_event
  done
}

# what the fuck is shift again?
emit_kv() {
  local type=$1
  shift

  local -A kv_event=([type]="$type")

  while (($# > 0)); do
    local key=$1
    local value=${2:-}
    kv_event[$key]=$value
    shift 2
  done

  emit kv_event
}

event_console() {
  local -n ec_event=$1
  local type=${ec_event[type]}
  local formatter=${CONSOLE_EVENT_FORMATTERS[$type]:-console_default}

  "$formatter" ec_event
}

console_run_loaded() {
  local -n crl_event=$1

  log_info "playbook: ${crl_event[playbook]}"
  log_info "context: ${crl_event[ctx]}"
  log_info "dry-run: ${SHBANG_RT[dry_run]}"
}

console_parser_for_each() {
  local -n event=$1
  log_debug "for_each ${event[selector]}"
}

console_parser_pipe() {
  local -n event=$1
  log_debug "pipe subject=${event[subject]} verb=${event[verb]} args=${event[args]}"
}

console_parser_label() {
  local -n event=$1
  printf '\n'
  fmt_label "${event[text]}"
}

console_cmd_local() {
  local -n event=$1
  fmt_local "${event[cmd]}" "${event[capture]}"
}

console_cmd_scp() {
  local -n event=$1
  local arrow
  case ${event[verb]} in
    send)  arrow='↑' ;;
    fetch) arrow='↓' ;;
    *)     arrow='·' ;;
  esac
  fmt_scp "$arrow" "${event[host]}" "${event[path]}" "${event[args]}"
}

console_cmd_ssh() {
  local -n event=$1
  fmt_ssh "${event[host]}" "${event[path]}" "${event[args]}"
}

console_default() {
  local -n event=$1

  log_debug "event ${event[type]}"
}

event_file() {
  local -n ef_event=$1

  [[ -n ${SHBANG_RT[event_file]:-} ]] || return 0

  event_to_json ef_event >> "${SHBANG_RT[event_file]}"
}

# pure bash — no jq subprocess per event
# bash 4.4 compat: ${!nameref[@]} is broken in 4.4 so we eval the key list
event_to_json() {
  local _etj_ref=$1
  local -n etj_event=$_etj_ref
  local out='{'
  local key val escaped
  local first=true
  local -a _etj_keys
  eval "_etj_keys=(\"\${!${_etj_ref}[@]}\")"

  for key in "${_etj_keys[@]}"; do
    val=${etj_event[$key]}
    # escape backslashes then double-quotes
    escaped=${val//\\/\\\\}
    escaped=${escaped//\"/\\\"}
    [[ $first == true ]] && first=false || out+=','
    out+="\"${key}\":\"${escaped}\""
  done

  out+='}'
  printf '%s\n' "$out"
}
