#!/usr/bin/env bash

# Path to the HOCON-to-JSON converter jar.
# Override with HOCON_JAR env var; default matches Dockerfile install path.
: "${HOCON_JAR:=/usr/local/lib/hocon.jar}"

# Convert a HOCON file to a temp JSON file; prints the temp path to stdout.
# Caller is responsible for cleanup: rm "$tmp"
hocon_to_json() {
  local src=$1
  [[ -f $HOCON_JAR ]] \
    || die "HOCON jar not found: $HOCON_JAR  (set HOCON_JAR env var or supply HOCON_JAR_URL at image build time)"
  local tmp
  tmp=$(mktemp /tmp/shbang-ctx-XXXXXX.json)
  java -jar "$HOCON_JAR" "$src" > "$tmp" \
    || { rm -f "$tmp"; die "HOCON conversion failed: $src"; }
  printf '%s' "$tmp"
}

# Download a URL to a temp file; prints the temp path to stdout.
# Supports http/https. For GitLab private repos set GITLAB_TOKEN env var.
# Caller is responsible for cleanup.
fetch_ctx() {
  local url=$1
  local ext=json
  [[ $url == *.hocon* ]] && ext=hocon
  local tmp
  tmp=$(mktemp "/tmp/shbang-ctx-XXXXXX.${ext}")

  local -a curl_args=(-fL)
  if [[ -n ${GITLAB_TOKEN:-} ]]; then
    curl_args+=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
  elif [[ -n ${CTX_TOKEN:-} ]]; then
    curl_args+=(-H "Authorization: Bearer ${CTX_TOKEN}")
  fi

  shbang_curl "${curl_args[@]}" "$url" -o "$tmp" \
    || { rm -f "$tmp"; die "failed to fetch ctx: $url"; }

  printf '%s' "$tmp"
}

# Resolve ctx to a local file path, eagerly.
# - URL (http/https): downloaded immediately regardless of file type —
#   works for .json, .hocon, or anything else stored in GitLab/http
#   Set GITLAB_TOKEN or CTX_TOKEN for auth.
# - .hocon (local or downloaded): then converted to JSON via hocon.jar
# - anything else: returned as-is
# Caller owns cleanup of any temp files (bin/sh.bang tracks _ctx_tmp).
resolve_ctx() {
  local ctx=$1
  local downloaded=

  # Download if URL — always eager, never lazy
  if [[ $ctx == http://* || $ctx == https://* ]]; then
    downloaded=$(fetch_ctx "$ctx")
    ctx=$downloaded
  fi

  # Convert HOCON → JSON if needed
  if [[ $ctx == *.hocon ]]; then
    local json_tmp
    json_tmp=$(hocon_to_json "$ctx")
    [[ -n $downloaded ]] && rm -f "$downloaded"
    printf '%s' "$json_tmp"
    return
  fi

  printf '%s' "$ctx"
}

# Resolve a resources map (associative array by nameref) into SHBANG_RT.
# Each entry: name → file://path | http(s)://url
# After resolution SHBANG_RT[name] holds the local filesystem path,
# ready for render_vars to substitute ${name} in pipe lines.
resolve_resources() {
  local -n rr_map=$1
  local name uri scheme path

  log_info "gathering resources — the whole shebang (${#rr_map[@]} declared)..."

  for name in "${!rr_map[@]}"; do
    uri=${rr_map[$name]}
    log_info "  $name = $uri"

    if [[ $uri == file://* ]]; then
      scheme=file
      path=${uri#file://}
      # keep relative paths relative — avoids MSYS absolute path mangling on Windows
      if [[ $path == /* ]]; then
        [[ -f $path ]] || die "resource '$name': file not found: $path"
      else
        [[ -f $path ]] || die "resource '$name': file not found: $path (relative to $PWD)"
      fi
      log_debug "  $name → local $path"
      SHBANG_RT[$name]=$path

    elif [[ $uri == http://* || $uri == https://* ]]; then
      scheme=http
      log_info "  fetching $name from $uri ..."
      local ext="${uri##*.}"
      local tmp
      tmp=$(mktemp "/tmp/shbang-res-XXXXXX.${ext}")
      log_debug "  $name: temp file $tmp"
      shbang_curl -fL "$uri" -o "$tmp" \
        || { rm -f "$tmp"; die "resource '$name': fetch failed: $uri  (try -vvvv for curl details)"; }
      local size
      size=$(wc -c < "$tmp" 2>/dev/null || echo '?')
      log_info "  $name fetched (${size} bytes) → $tmp"
      log_debug "  $name → $tmp"
      SHBANG_RT[$name]=$tmp
      # track for cleanup
      SHBANG_RT[_res_tmp_${name}]=$tmp

    else
      die "resource '$name': unsupported scheme: $uri"
    fi
  done

  log_info "resources ready."
}
