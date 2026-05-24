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

parse_local_line() {
  local line=$1
  local -n out=$2

  out=()

  if [[ $line =~ ^\$[[:space:]]+run[[:space:]]+(.+)[[:space:]]+-\>[[:space:]]+([^[:space:]]+)$ ]]; then
    out[type]=local
    out[cmd]=${BASH_REMATCH[1]}
    out[capture]=${BASH_REMATCH[2]}
    return 0
  fi

  return 1
}

parse_playbook() {
  local playbook=$1
  local line
  local line_no=0
  local -A node
  local in_resources=false

  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    (( line_no += 1 ))
    log_trace "line $line_no: $line"

    [[ -z $line ]] && continue
    [[ $line =~ ^[[:space:]]*// ]] && continue
    [[ $line =~ ^[[:space:]]*#! ]] && continue

    # resources {} block — skip for now, resolved in preflight phase
    if [[ $line =~ ^[[:space:]]*resources[[:space:]]*\{ ]]; then
      in_resources=true
      continue
    fi
    if [[ $in_resources == true ]]; then
      [[ $line =~ ^[[:space:]]*\} ]] && in_resources=false
      continue
    fi

    if parse_for_each_line "$line" node; then
      log_debug "parsed for_each selector=${node[selector]}"
      emit_kv parser.for_each selector "${node[selector]}"
      continue
    fi

    if parse_local_line "$line" node; then
      log_debug "parsed local cmd=${node[cmd]} capture=${node[capture]}"
      emit_kv parser.local \
        cmd     "${node[cmd]}" \
        capture "${node[capture]}"
      continue
    fi

    if parse_pipe_line "$line" node; then
      log_debug "parsed pipe subject=${node[subject]} verb=${node[verb]}"
      log_wire "pipe args=${node[args]}"
      emit_kv parser.pipe \
        subject "${node[subject]}" \
        verb    "${node[verb]}" \
        args    "${node[args]}"
      continue
    fi

    die "cannot parse line $line_no: $line"
  done < "$playbook"
}
