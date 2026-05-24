#!/usr/bin/env bash

declare -A CMD_DISPATCH=(
  [cmd.scp]=dispatch_scp
  [cmd.ssh]=dispatch_ssh
)

# ControlMaster: one TCP/TLS handshake per host per run.
# First call creates the master socket; subsequent calls to the same host
# reuse it — so a 100-line security banner appears once, not once per pipe.
_SHBANG_CTL_DIR="/tmp/.shbang-ctl"

_ssh_opts() {
  local key_opt= cfg_opt= mux_opts=
  [[ -n ${SHBANG_SSH_KEY:-}    ]] && key_opt=" -i ${SHBANG_SSH_KEY}"
  [[ -n ${SHBANG_SSH_CONFIG:-} ]] && cfg_opt=" -F ${SHBANG_SSH_CONFIG}"
  # ControlMaster uses Unix domain sockets; disable on Windows (Git Bash / MSYS)
  if [[ ${OSTYPE:-} != msys* && ${OSTYPE:-} != cygwin* ]]; then
    mux_opts=" -o ControlMaster=auto -o ControlPath=${_SHBANG_CTL_DIR}/%r@%h:%p -o ControlPersist=30s"
  fi
  printf '%s' \
    "-o StrictHostKeyChecking=no" \
    " -o BatchMode=yes" \
    " -o KexAlgorithms=ecdh-sha2-nistp256" \
    "${mux_opts}" \
    "${key_opt}${cfg_opt}"
}

# Registered in EVENT_HANDLERS; skips events not in CMD_DISPATCH.
# On dry-run: prints a labelled line from verbs.json instead of executing.
event_dispatch() {
  local -n ed_event=$1
  local type=${ed_event[type]}
  local fn=${CMD_DISPATCH[$type]:-}
  [[ -n $fn ]] || return 0

  if [[ ${SHBANG_RT[dry_run]} == true ]]; then
    local verb=${ed_event[verb]}
    local label
    label=$(jq -r --arg v "$verb" \
      '.verbs[$v].dry_run // "(unknown verb)"' \
      "${SHBANG_RT[home]}/spec/verbs.json")
    printf '[dry-run] %-6s %s  %s  %s@%s:%s\n' \
      "$verb" "$label" \
      "${ed_event[args]}" "${ed_event[user]}" \
      "${ed_event[host]}" "${ed_event[path]}"
    return 0
  fi

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
    dq_event=(

      #	Parse `$entry` as JSON, extract `.host`, and if it's missing produce an empty string rather than
      [type]=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -r '.type // empty' <<< "$entry")
      [user]=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -r '.user // "deploy"' <<< "$entry")
      [host]=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -r '.host // empty' <<< "$entry")
      [path]=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -r '.path // empty' <<< "$entry")
      [verb]=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -r '.verb // empty' <<< "$entry")
      [args]=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -r '.args // empty' <<< "$entry")
    )
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
    send)  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' scp $(_ssh_opts) "$args" "${user}@${host}:${path}" 2>&1 | sed 's/^/  | /' ;;
    fetch) MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' scp $(_ssh_opts) "${user}@${host}:${path}" "$args" 2>&1 | sed 's/^/  | /' ;;
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
    run) MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' ssh $(_ssh_opts) "${user}@${host}" "cd ${path} && ${args}" 2>&1 | sed 's/^/  | /' ;;
    *)   log_debug "dispatch_ssh: unknown verb: $verb" ;;
  esac
}
