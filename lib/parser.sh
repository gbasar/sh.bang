#!/usr/bin/env bash

parse_step_line() {
  local line=$1
  local -n _psl_out=$2

  _psl_out=()
  if [[ $line =~ ^Step:[[:space:]]+(.+)$ ]]; then
    _psl_out[type]=step
    _psl_out[name]=${BASH_REMATCH[1]}
    return 0
  fi
  return 1
}

parse_for_each_line() {
  local line=$1
  local -n _pfe_out=$2

  _pfe_out=()
  if [[ $line =~ ^for_each[[:space:]]+\$\{([^}]*)\}[[:space:]]*$ ]]; then
    _pfe_out[type]=for_each
    _pfe_out[selector]=${BASH_REMATCH[1]}
    return 0
  fi
  return 1
}

parse_pipe_line() {
  local line=$1
  local -n _ppl_out=$2

  _ppl_out=()
  if [[ $line =~ ^[[:space:]]*\|[[:space:]]*([^[:space:]]+)[[:space:]]+([^[:space:]]+)(.*)$ ]]; then
    _ppl_out[type]=pipe
    _ppl_out[subject]=${BASH_REMATCH[1]}
    _ppl_out[verb]=${BASH_REMATCH[2]}
    _ppl_out[args]=${BASH_REMATCH[3]# }
    return 0
  fi
  return 1
}

parse_playbook() {
  local playbook=$1
  local -n _pp_nodes=$2
  _pp_nodes=()

  local line line_no=0
  local -A node
  local last_type=""

  while IFS= read -r line || [[ -n $line ]]; do
    (( ++line_no ))
    [[ -z $line ]] && continue
    [[ $line =~ ^[[:space:]]*// ]] && continue

    log_trace "line $line_no: $line"
    node=()

    if parse_step_line "$line" node; then
      log_debug "parsed step name=${node[name]}"
      emit_kv parser.step name "${node[name]}"
      _pp_nodes+=("$(declare -p node)")
      last_type=step
      continue
    fi

    if parse_for_each_line "$line" node; then
      [[ $last_type == step ]] || die "line $line_no: for_each requires a preceding Step: declaration"
      log_debug "parsed for_each selector=${node[selector]}"
      emit_kv parser.for_each selector "${node[selector]}"
      _pp_nodes+=("$(declare -p node)")
      last_type=for_each
      continue
    fi

    if parse_pipe_line "$line" node; then
      log_debug "parsed pipe subject=${node[subject]} verb=${node[verb]}"
      log_wire "pipe args=${node[args]}"
      emit_kv parser.pipe \
        subject "${node[subject]}" \
        verb    "${node[verb]}"    \
        args    "${node[args]}"
      _pp_nodes+=("$(declare -p node)")
      last_type=pipe
      continue
    fi

    die "cannot parse line $line_no: $line"
  done < "$playbook"
}
