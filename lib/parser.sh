#!/usr/bin/env bash

parse_for_each_line() {
  local line=$1
  local -n out=$2

  out=()

  if [[ $line =~ ^for_each[[:space:]]+\$\{([^}]*)\}[[:space:]]*$ ]]; then
    out[type]=for_each
    out[selector]=${BASH_REMATCH[1]}
    return 0
  fi

  return 1
}

parse_pipe_line() {
  local line=$1
  local -n out=$2

  out=()

  if [[ $line =~ ^[[:space:]]*\|[[:space:]]*([^[:space:]]+)[[:space:]]+([^[:space:]]+)(.*)$ ]]; then
    out[type]=pipe
    out[subject]=${BASH_REMATCH[1]}
    out[verb]=${BASH_REMATCH[2]}
    out[args]=${BASH_REMATCH[3]# }
    return 0
  fi

  return 1
}

parse_playbook() {
  local -n pp_rt=$1
  local playbook=$2
  local line
  local line_no=0
  local -A node

  while IFS= read -r line || [[ -n $line ]]; do
    (( line_no += 1 ))
    log_trace "line $line_no: $line"

    [[ -z $line ]] && continue
    [[ $line =~ ^[[:space:]]*// ]] && continue

    if parse_for_each_line "$line" node; then
      log_debug "parsed for_each selector=${node[selector]}"
      emit_kv pp_rt parser.for_each selector "${node[selector]}"
      continue
    fi

    if parse_pipe_line "$line" node; then
      log_debug "parsed pipe subject=${node[subject]} verb=${node[verb]}"
      log_wire "pipe args=${node[args]}"
      emit_kv pp_rt parser.pipe \
        subject "${node[subject]}" \
        verb "${node[verb]}" \
        args "${node[args]}"
      continue
    fi

    die "cannot parse line $line_no: $line"
  done < "$playbook"
}
