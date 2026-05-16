#!/usr/bin/env bash

declare -A VERB_ARGV  # verb → JSON array string e.g. '["ls","-lAh"]'
declare -A VERB_KIND  # verb → local | remote

_load_verbs() {
  local verbs_file=$1
  [[ -f $verbs_file ]] || die "verbs spec not found: $verbs_file"
  local verb
  while IFS= read -r verb; do
    VERB_KIND[$verb]=$(jq -r --arg v "$verb" '.verbs[$v].kind' "$verbs_file")
    VERB_ARGV[$verb]=$(jq -c --arg v "$verb" '.verbs[$v].argv'  "$verbs_file")
  done < <(jq -r '.verbs | keys[]' "$verbs_file")
}

# Replace ${key} and ${a.b} placeholders using values from a JSON object.
_expand_vars() {
  local template=$1 item_json=$2
  local result=$template key val
  while [[ $result =~ \$\{([^}]+)\} ]]; do
    key=${BASH_REMATCH[1]}
    val=$(jq -r ".${key} // empty" <<< "$item_json")
    result=${result//"\${$key}"/$val}
  done
  printf '%s' "$result"
}

# Unpack a JSON argv array into a bash array.
_argv_from_json() {
  local -n _afj_out=$1
  local json=$2
  _afj_out=()
  while IFS= read -r arg; do
    _afj_out+=("$arg")
  done < <(jq -r '.[]' <<< "$json")
}

# Groups nodes into (for_each, pipe[]) blocks and runs each block.
execute_playbook() {
  local -n _ep_nodes=$1
  local -n rt=$SHBANG_RT_NAME

  _load_verbs "${rt[home]}/spec/verbs.json"

  local -i i=0 n=${#_ep_nodes[@]}
  while (( i < n )); do
    local -A node=()
    eval "${_ep_nodes[i]}"
    (( ++i ))

    [[ ${node[type]} == for_each ]] || die "expected for_each, got ${node[type]}"

    local selector=${node[selector]}
    local -a body=()
    while (( i < n )); do
      local -A node=()
      eval "${_ep_nodes[i]}"
      [[ ${node[type]} == pipe ]] || break
      body+=("${_ep_nodes[i]}")
      (( ++i ))
    done

    _run_for_each_block "$selector" body
  done
}

_run_for_each_block() {
  local selector=$1
  local -n _rfb_body=$2
  local -n rt=$SHBANG_RT_NAME

  emit_kv exec.for_each selector "$selector"

  local item
  while IFS= read -r item; do
    local serialized
    for serialized in "${_rfb_body[@]}"; do
      local -A node=()
      eval "$serialized"
      _run_pipe node "$item"
    done
  done < <(jq -c ".${selector}[]" "${rt[ctx]}")
}

_run_pipe() {
  local -n _rp_node=$1
  local item_json=$2
  local -n rt=$SHBANG_RT_NAME

  local subject verb args
  subject=$(_expand_vars "${_rp_node[subject]}" "$item_json")
  verb=$(_expand_vars    "${_rp_node[verb]}"    "$item_json")
  args=$(_expand_vars    "${_rp_node[args]}"    "$item_json")

  emit_kv exec.pipe subject "$subject" verb "$verb" args "$args"

  local verb_json=${VERB_ARGV[$verb]:-}
  [[ -n $verb_json ]] || die "unknown verb: $verb"

  local kind=${VERB_KIND[$verb]}
  [[ $kind == local ]] || die "remote execution not yet implemented"

  # Strip @ sigil — subject is a local path
  local target=${subject#@}

  local name
  name=$(jq -r '.name // .path' <<< "$item_json")
  printf '\n\033[1;36m[%s]\033[0m %s  %s\n' "$name" "$verb" "$target"

  if [[ ${rt[dry_run]} == true ]]; then
    log_info "dry-run: $verb $target"
    return 0
  fi

  local -a cmd=()
  _argv_from_json cmd "$verb_json"
  "${cmd[@]}" "$target"
}
