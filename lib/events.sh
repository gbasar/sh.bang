#!/usr/bin/env bash

# ── Handler registries ────────────────────────────────────────────────────────

declare -A EVENT_HANDLERS
EVENT_HANDLERS[console]=event_console
EVENT_HANDLERS[file]=event_file

# Which handlers are active. Add/remove keys to change routing at runtime.
declare -gA ACTIVE_EVENT_HANDLERS
ACTIVE_EVENT_HANDLERS[console]=1

declare -A CONSOLE_EVENT_FORMATTERS
CONSOLE_EVENT_FORMATTERS[run.loaded]=console_run_loaded
CONSOLE_EVENT_FORMATTERS[parser.for_each]=console_parser_for_each
CONSOLE_EVENT_FORMATTERS[parser.pipe]=console_parser_pipe
CONSOLE_EVENT_FORMATTERS[exec.for_each]=console_default
CONSOLE_EVENT_FORMATTERS[exec.pipe]=console_default
CONSOLE_EVENT_FORMATTERS[log.info]=console_log
CONSOLE_EVENT_FORMATTERS[log.debug]=console_log
CONSOLE_EVENT_FORMATTERS[log.trace]=console_log
CONSOLE_EVENT_FORMATTERS[log.wire]=console_log
CONSOLE_EVENT_FORMATTERS[log.error]=console_log

# Minimum verbosity level required to print each log type.
declare -A LOG_VERBOSITY_THRESHOLDS
LOG_VERBOSITY_THRESHOLDS[log.info]=1
LOG_VERBOSITY_THRESHOLDS[log.debug]=2
LOG_VERBOSITY_THRESHOLDS[log.trace]=3
LOG_VERBOSITY_THRESHOLDS[log.wire]=4
LOG_VERBOSITY_THRESHOLDS[log.error]=0

# ── Emission ──────────────────────────────────────────────────────────────────

# Internal: build and dispatch an event with an explicit source location.
# Called by emit_kv and log wrappers — never call directly from application code.
_emit_raw() {
  local type=$1 src=$2
  local -A __evt
  __evt[type]=$type
  __evt[_src]=$src

  local -a kv=("${@:3}")
  local i
  for (( i=0; i<${#kv[@]}; i+=2 )); do
    __evt[${kv[i]}]=${kv[i+1]:-}
  done

  local name
  for name in "${!ACTIVE_EVENT_HANDLERS[@]}"; do
    local fn=${EVENT_HANDLERS[$name]:-}
    [[ -n $fn ]] || die "unknown event handler: $name"
    "$fn" __evt
  done
}

# Public: emit a typed event. Source location auto-injected from caller's frame.
# Usage: emit_kv type [key value ...]
emit_kv() {
  _emit_raw "$1" "${BASH_SOURCE[1]}:${BASH_LINENO[0]}" "${@:2}"
}

# ── Console handler ───────────────────────────────────────────────────────────

event_console() {
  local -n _con_ev=$1
  local formatter=${CONSOLE_EVENT_FORMATTERS[${_con_ev[type]}]:-console_default}
  "$formatter" "$1"
}

console_run_loaded() {
  local -n _ev=$1
  local -n rt=$SHBANG_RT_NAME
  (( rt[verbosity] >= 1 )) || return 0
  printf '[sh.bang:info] playbook: %s\n' "${_ev[playbook]}" >&2
  printf '[sh.bang:info] context: %s\n'  "${_ev[ctx]}"      >&2
  printf '[sh.bang:info] dry-run: %s\n'  "${rt[dry_run]}"   >&2
}

console_parser_for_each() {
  local -n _ev=$1
  printf '[for_each] %s\n' "${_ev[selector]}"
}

console_parser_pipe() {
  local -n _ev=$1
  printf '[pipe] subject=%s verb=%s args=%s\n' \
    "${_ev[subject]}" "${_ev[verb]}" "${_ev[args]}"
}

console_log() {
  local -n _ev=$1
  local -n rt=$SHBANG_RT_NAME
  local threshold=${LOG_VERBOSITY_THRESHOLDS[${_ev[type]}]:-0}
  (( rt[verbosity] >= threshold )) || return 0
  printf '[sh.bang:%s] %s\n' "${_ev[type]#log.}" "${_ev[message]:-}" >&2
}

console_default() {
  local -n _ev=$1
  local -n rt=$SHBANG_RT_NAME
  (( rt[verbosity] >= 2 )) || return 0
  printf '[sh.bang:debug] event %s\n' "${_ev[type]}" >&2
}

# ── File handler ──────────────────────────────────────────────────────────────

event_file() {
  local -n _ef_rt=$SHBANG_RT_NAME
  [[ -n ${_ef_rt[event_file]:-} ]] || return 0
  event_to_json "$1" >> "${_ef_rt[event_file]}"
}

# ── Serialization ─────────────────────────────────────────────────────────────

event_to_json() {
  local -n _e2j=$1
  local out='{' sep='' key val
  for key in "${!_e2j[@]}"; do
    val=${_e2j[$key]}
    val=${val//\\/\\\\}
    val=${val//'"'/\\\"}
    val=${val//$'\n'/\\n}
    val=${val//$'\t'/\\t}
    out+="${sep}\"${key}\":\"${val}\""
    sep=','
  done
  printf '%s}\n' "$out"
}
