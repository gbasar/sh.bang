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
    value=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -r ".${path} // empty" <<< "$node_json" 2>/dev/null || true)
    # 2. fall back to full context JSON (top-level fields like runtime.javaHome)
    # No MSYS_NO_PATHCONV here — the file path needs MSYS conversion on Windows
    # (ctx may be a /tmp/... temp file that jq can only reach via its Windows path)
    if [[ -z $value ]]; then
      value=$(jq -r ".${path} // empty" "${SHBANG_RT[ctx]}" 2>/dev/null || true)
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
  [parser.resource]=expand_resource
  [parser.for_each]=expand_for_each
  [parser.pipe]=expand_pipe
)

# Accumulate resource declarations during parse; resolved lazily before first pipe.
declare -A _RESOURCES=()
_RESOURCES_RESOLVED=false

expand_resource() {
  local -n er_event=$1
  _RESOURCES[${er_event[name]}]=${er_event[uri]}
}

_ensure_resources_resolved() {
  [[ $_RESOURCES_RESOLVED == true ]] && return 0
  _RESOURCES_RESOLVED=true
  if (( ${#_RESOURCES[@]} > 0 )); then
    resolve_resources _RESOURCES
  fi
}

event_expand() {
  local -n ex_event=$1
  local fn=${EXPAND_HANDLERS[${ex_event[type]}]:-}
  [[ -n $fn ]] || return 0
  "$fn" ex_event
}

expand_for_each() {
  local -n ef_event=$1
  _ensure_resources_resolved
  local selector
  selector=$(render_vars "${ef_event[selector]}" "{}")
  SHBANG_RT[_expand_selector]=$selector
}

expand_pipe() {
  local -n ep_event=$1

  local selector=${SHBANG_RT[_expand_selector]:-}

  # No for_each in scope — run once against the full context (bare pipe)
  local jq_path node_json_src
  if [[ -z $selector ]]; then
    jq_path=
    node_json_src=bare
  else
    jq_path=$(selector_to_jq "$selector")
    node_json_src=ctx
  fi

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
    local path
    if [[ $host_path == *:* ]]; then path=${host_path#*:}; else path=""; fi

    # @local — queue for in-order execution on this machine
    if [[ $prefix == @ && $host == local ]]; then
      local capture=""
      if [[ $args =~ (.*)[[:space:]]-\>[[:space:]]([^[:space:]]+)$ ]]; then
        args=${BASH_REMATCH[1]}
        capture=${BASH_REMATCH[2]}
      fi
      local local_cmd="$args"
      [[ -n $path ]] && local_cmd="cd ${path} && ${args}"
      _CMD_QUEUE+=("$(jq -cn \
        --arg type    "cmd.local" \
        --arg cmd     "$local_cmd" \
        --arg capture "$capture" \
        '{type:$type,cmd:$cmd,capture:$capture}')")
      continue
    fi

    local cmd_type
    case $prefix in
      @)
        case $verb in
          send|fetch) cmd_type=cmd.scp ;;
          *)          cmd_type=cmd.ssh ;;
        esac ;;
      *)  log_debug "expand: unknown subject prefix in: $subject"; continue ;;
    esac

    # Serialise to JSON and push onto the queue — no nested emit_kv needed
    # MSYS_NO_PATHCONV+MSYS2_ARG_CONV_EXCL prevent Git Bash from converting
    # Linux paths (e.g. /tmp) passed as --arg values to Windows equivalents.
    _CMD_QUEUE+=("$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -cn \
      --arg type    "$cmd_type" \
      --arg user    "$user"     \
      --arg host    "$host"     \
      --arg path    "$path"     \
      --arg verb    "$verb"     \
      --arg args    "$args"     \
      '{type:$type,user:$user,host:$host,path:$path,verb:$verb,args:$args}')")

  done < <(
    if [[ $node_json_src == bare ]]; then
      echo '{}'
    else
      jq -c "$jq_path" "${SHBANG_RT[ctx]}"
    fi
  )
}
