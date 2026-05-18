#!/usr/bin/env bash

declare -A EVENT_HANDLERS=(
  [console]=event_console
  [file]=event_file
)

declare -A CONSOLE_EVENT_FORMATTERS=(
  [run.loaded]=console_run_loaded
  [parser.for_each]=console_parser_for_each
  [parser.pipe]=console_parser_pipe
)

emit() {
  local -n rt=$1
  local -n event=$2
  local -a handlers
  local name

  read -r -a handlers <<< "${rt[event_handlers]}"

  for name in "${handlers[@]}"; do
    local fn=${EVENT_HANDLERS[$name]:-}
    [[ -n $fn ]] || die "unknown event handler: $name"
    "$fn" rt event
  done
}

# what the fuck is shift agian? 
emit_kv() {
  local -n rt=$1
  local type=$2
  shift 2

  local -A event=([type]="$type")

  while (($# > 0)); do
    local key=$1
    local value=${2:-}
    event[$key]=$value
    shift 2
  done

  emit rt event
}

event_console() {
  local -n rt=$1
  local -n event=$2
  local type=${event[type]}
  local formatter=${CONSOLE_EVENT_FORMATTERS[$type]:-console_default}

  "$formatter" rt event
}

console_run_loaded() {
  local -n rt=$1
  local -n event=$2

  log_info "playbook: ${event[playbook]}"
  log_info "context: ${event[ctx]}"
  log_info "dry-run: ${rt[dry_run]}"
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

console_default() {
  local -n event=$2

  log_debug "event ${event[type]}"
}

event_file() {
  local -n rt=$1
  local -n event=$2

  [[ -n ${rt[event_file]:-} ]] || return 0

  event_to_json event >> "${rt[event_file]}"
}

# can jq really not do this?
event_to_json() {
  local -n event=$1
  local -a jq_args=()
  local filter='{'
  local key
  local first=true

  for key in "${!event[@]}"; do
    jq_args+=(--arg "$key" "${event[$key]}")
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
