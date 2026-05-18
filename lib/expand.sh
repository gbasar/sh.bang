#!/usr/bin/env bash

# Queue of serialised cmd events built during parse, flushed by dispatch_queue.
# Using a queue rather than nested emit_kv calls avoids Bash nameref depth limits.
_CMD_QUEUE=()

# ---------- selector / variable helpers ----------

selector_to_jq() {
  local sel=$1
  # topology.shards[shard3] → .topology.shards.shard3
  # topology.shards[*]      → .topology.shards[]
  printf '.%s' "$sel" \
    | sed 's/\[\*\]/[]/g; s/\[\([^*][^]]*\)\]/.\1/g'
}

render_vars() {
  local template=$1
  local node_json=$2
  local result=$template

  while [[ $result =~ \$\{([^}]+)\} ]]; do
    local path=${BASH_REMATCH[1]}
    local value
    value=$(jq -r ".${path} // empty" <<< "$node_json" 2>/dev/null || true)
    result="${result/"\${${path}}"/"${value}"}"
  done

  printf '%s' "$result"
}

# ---------- expand listener ----------

event_expand() {
  local -n ex_event=$1
  local type=${ex_event[type]}

  case $type in
    parser.for_each)
      SHBANG_RT[_expand_selector]=${ex_event[selector]}
      ;;
    parser.pipe)
      expand_pipe ex_event
      ;;
  esac
}

expand_pipe() {
  local -n ep_event=$1

  local selector=${SHBANG_RT[_expand_selector]:-}
  [[ -n $selector ]] || return 0

  local jq_path
  jq_path=$(selector_to_jq "$selector")

  local node_json
  while IFS= read -r node_json; do
    [[ -n $node_json ]] || continue

    local subject verb args user
    subject=$(render_vars "${ep_event[subject]}" "$node_json")
    verb="${ep_event[verb]}"
    args=$(render_vars "${ep_event[args]}"    "$node_json")
    user=$(jq -r '.user.name // "deploy"'    <<< "$node_json")

    local prefix=${subject:0:1}
    local host_path=${subject:1}
    local host=${host_path%%:*}
    local path=${host_path#*:}

    local cmd_type
    case $prefix in
      @)  cmd_type=cmd.scp ;;
      '#') cmd_type=cmd.ssh ;;
      *)  log_debug "expand: unknown subject prefix in: $subject"; continue ;;
    esac

    # Serialise to JSON and push onto the queue — no nested emit_kv needed
    _CMD_QUEUE+=("$(jq -cn \
      --arg type    "$cmd_type" \
      --arg user    "$user"     \
      --arg host    "$host"     \
      --arg path    "$path"     \
      --arg verb    "$verb"     \
      --arg args    "$args"     \
      '{type:$type,user:$user,host:$host,path:$path,verb:$verb,args:$args}')")

  done < <(jq -c "$jq_path" "${SHBANG_RT[ctx]}")
}
