#!/usr/bin/env bash

# Queue of serialised cmd events built during parse, flushed by dispatch_queue.
# Using a queue rather than nested emit_kv calls avoids Bash nameref depth limits.
_CMD_QUEUE=()

# ---------- selector / variable helpers ----------

selector_to_jq() {
  local sel=$1
  # trading.shards[*]   → .trading.shards[]       (iterate all values)
  # trading.shards[4]   → .trading.shards["4"]    (string key — works for integer-keyed maps)
  # trading.shards[foo] → .trading.shards["foo"]  (named key)
  # plain trading.shards with no brackets → .trading.shards[]  (auto-iterate)
  local result
  result=$(printf '.%s' "$sel" \
    | sed 's/\[\*\]/[]/g; s/\[\([^*][^]]*\)\]/["\1"]/g')
  # only auto-append [] if there are no brackets at all (bare path, no selector)
  [[ $result == *'['* ]] || result="${result}[]"
  printf '%s' "$result"
}

render_vars() {
  local template=$1
  local node_json=$2
  local result=$template

  while [[ $result =~ \$\{([^}]+)\} ]]; do
    local path=${BASH_REMATCH[1]}
    local value
    # 1. try the shard node
    value=$(MSYS_NO_PATHCONV=1 jq -r ".${path} // empty" <<< "$node_json" 2>/dev/null || true)
    # 2. fall back to full context JSON (top-level fields like runtime.javaHome)
    if [[ -z $value ]]; then
      value=$(MSYS_NO_PATHCONV=1 jq -r ".${path} // empty" "${SHBANG_RT[ctx]}" 2>/dev/null || true)
    fi
    # 3. fall back to SHBANG_RT (captured locals like tradeFilter)
    if [[ -z $value && -n ${SHBANG_RT[$path]:-} ]]; then
      value=${SHBANG_RT[$path]}
    fi
    result="${result/"\${${path}}"/"${value}"}"
  done

  printf '%s' "$result"
}

# ---------- expand handlers ----------

declare -A EXPAND_HANDLERS=(
  [parser.for_each]=expand_for_each
  [parser.pipe]=expand_pipe
  [parser.local]=expand_local
)

event_expand() {
  local -n ex_event=$1
  local fn=${EXPAND_HANDLERS[${ex_event[type]}]:-}
  [[ -n $fn ]] || return 0
  "$fn" ex_event
}

expand_for_each() {
  local -n ef_event=$1
  SHBANG_RT[_expand_selector]=${ef_event[selector]}
}

expand_local() {
  local -n el_event=$1
  local cmd
  cmd=$(render_vars "${el_event[cmd]}" "{}")
  local result
  result=$(bash -c "$cmd")
  SHBANG_RT[${el_event[capture]}]=$result
  log_debug "local: captured ${el_event[capture]}=${result}"
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
    user=$(jq -r 'if .user | type == "object" then .user.name else "deploy" end' <<< "$node_json")

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
