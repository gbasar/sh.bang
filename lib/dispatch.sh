#!/usr/bin/env bash

declare -A CMD_DISPATCH=(
  [cmd.scp]=dispatch_scp
  [cmd.ssh]=dispatch_ssh
)

# ControlMaster: one TCP/TLS handshake per host per run.
# First call creates the master socket; subsequent calls to the same host
# reuse it — so a 100-line security banner appears once, not once per pipe.
_SHBANG_CTL_DIR="${TMPDIR:-/tmp}/.shbang-ctl"

_ssh_opts() {
  printf '%s' \
    "-o StrictHostKeyChecking=no" \
    " -o BatchMode=yes" \
    " -o ControlMaster=auto" \
    " -o ControlPath=${_SHBANG_CTL_DIR}/%r@%h:%p" \
    " -o ControlPersist=30s"
}

# Registered in EVENT_HANDLERS; skips events not in CMD_DISPATCH and dry-runs.
event_dispatch() {
  local -n ed_event=$1
  local type=${ed_event[type]}
  local fn=${CMD_DISPATCH[$type]:-}
  [[ -n $fn ]]                          || return 0
  [[ ${SHBANG_RT[dry_run]} == true ]]   && return 0
  "$fn" ed_event
}

# Flush _CMD_QUEUE: deserialise each JSON entry into an associative array and
# run it through the full event pipeline (console prints, dispatch executes).
# Called from cmd_run after parse_playbook returns.
dispatch_queue() {
  mkdir -p "$_SHBANG_CTL_DIR"
  local entry
  local -A dq_event
  for entry in "${_CMD_QUEUE[@]}"; do
    dq_event=()
    local line k v
    while IFS= read -r line; do
      k=${line%%=*}
      v=${line#*=}
      dq_event[$k]=$v
    done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<< "$entry" | tr -d '\r')
    emit dq_event
  done
  _CMD_QUEUE=()
}

dispatch_scp() {
  local -n ds_event=$1
  local user=${ds_event[user]}
  local host=${ds_event[host]}
  local path=${ds_event[path]}
  local verb=${ds_event[verb]}
  local args=${ds_event[args]}

  # shellcheck disable=SC2046
  case $verb in
    send)  scp $(_ssh_opts) "$args" "${user}@${host}:${path}" ;;
    fetch) scp $(_ssh_opts) "${user}@${host}:${path}" "$args" ;;
    *)     log_debug "dispatch_scp: unknown verb: $verb" ;;
  esac
}

dispatch_ssh() {
  local -n dsh_event=$1
  local user=${dsh_event[user]}
  local host=${dsh_event[host]}
  local path=${dsh_event[path]}
  local verb=${dsh_event[verb]}
  local args=${dsh_event[args]}

  # shellcheck disable=SC2046
  case $verb in
    run) ssh $(_ssh_opts) "${user}@${host}" "cd ${path} && ${args}" ;;
    *)   log_debug "dispatch_ssh: unknown verb: $verb" ;;
  esac
}
