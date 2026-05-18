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
  local -n emit_rt=$1
  local -n emit_event=$2
  local -a handlers
  local name

  read -r -a handlers <<< "${emit_rt[event_handlers]}"

  for name in "${handlers[@]}"; do
    local fn=${EVENT_HANDLERS[$name]:-}
    [[ -n $fn ]] || die "unknown event handler: $name"
    "$fn" emit_rt emit_event
  done
}

# what the fuck is shift agian? 
emit_kv() {
  local -n kv_rt=$1
  local type=$2
  shift 2

  local -A kv_event=([type]="$type")

  while (($# > 0)); do
    local key=$1
    local value=${2:-}
    kv_event[$key]=$value
    shift 2
  done

  emit kv_rt kv_event
}

event_console() {
  local -n ec_rt=$1
  local -n ec_event=$2
  local type=${ec_event[type]}
  local formatter=${CONSOLE_EVENT_FORMATTERS[$type]:-console_default}

  "$formatter" ec_rt ec_event
}

console_run_loaded() {
  local -n crl_rt=$1
  local -n crl_event=$2

  log_info "playbook: ${crl_event[playbook]}"
  log_info "context: ${crl_event[ctx]}"
  log_info "dry-run: ${crl_rt[dry_run]}"
}

console_parser_for_each() {
  local -n event=$2

  printf '[for_each] %s\n' "${event[selector]}"
}

console_parser_pipe() {
  local -n event=$2

  printf '[pipe] subject=%s verb=%s args=%s\n' \
    "${event[subject]}" \
    "${event[verb]}" \
    "${event[args]}"
}

console_cmd_scp() {
  local -n event=$2
  printf '[cmd:scp] %s:%s  %s  %s\n' \
    "${event[host]}" "${event[path]}" "${event[verb]}" "${event[args]}"
}

console_cmd_ssh() {
  local -n event=$2
  printf '[cmd:ssh] %s:%s  %s  %s\n' \
    "${event[host]}" "${event[path]}" "${event[verb]}" "${event[args]}"
}

console_default() {
  local -n event=$2

  log_debug "event ${event[type]}"
}

event_file() {
  local -n ef_rt=$1
  local -n ef_event=$2

  [[ -n ${ef_rt[event_file]:-} ]] || return 0

  event_to_json ef_event >> "${ef_rt[event_file]}"
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
