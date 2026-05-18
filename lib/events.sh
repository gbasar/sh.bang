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

  printf '[for_each] %s\n' "${event[selector]}"
}

console_parser_pipe() {
  local -n event=$1

  printf '[pipe] subject=%s verb=%s args=%s\n' \
    "${event[subject]}" \
    "${event[verb]}" \
    "${event[args]}"
}

console_cmd_scp() {
  local -n event=$1
  printf '[cmd:scp] %s:%s  %s  %s\n' \
    "${event[host]}" "${event[path]}" "${event[verb]}" "${event[args]}"
}

console_cmd_ssh() {
  local -n event=$1
  printf '[cmd:ssh] %s:%s  %s  %s\n' \
    "${event[host]}" "${event[path]}" "${event[verb]}" "${event[args]}"
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

# can jq really not do this?
event_to_json() {
  local -n etj_event=$1
  local -a jq_args=()
  local filter='{'
  local key
  local first=true

  for key in "${!etj_event[@]}"; do
    jq_args+=(--arg "$key" "${etj_event[$key]}")
    if [[ $first == true ]]; then
      first=false
    else
      filter+=','
    fi
    filter+="\"$key\":\$$key"
  done

  filter+='}'
  jq -cn "${jq_args[@]}" "$filter"
}
