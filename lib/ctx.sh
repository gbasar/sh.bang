#!/usr/bin/env bash

# Path to the HOCON-to-JSON converter jar.
# Override with HOCON_JAR env var; default matches Dockerfile install path.
: "${HOCON_JAR:=/usr/local/lib/hocon.jar}"

# Typesafe Config version used for the fat-jar build.
: "${TYPESAFE_CONFIG_VERSION:=1.4.3}"

# If HOCON_JAR is missing, download typesafe-config from Maven Central, compile
# HoconToJson.java, and package a fat jar.  Falls back to writing alongside the
# source when the default install path isn't writable (local dev).
_ensure_hocon_jar() {
  [[ -f $HOCON_JAR ]] && return 0

  log_info "HOCON jar not found at ${HOCON_JAR} — building from Maven Central..."

  command -v java  &>/dev/null || { log_info "  java not found; install a JDK or set HOCON_JAR"; return 1; }
  command -v javac &>/dev/null || { log_info "  javac not found (JRE only?); install a JDK or set HOCON_JAR"; return 1; }

  local target=$HOCON_JAR
  local target_dir; target_dir=$(dirname "$target")

  # Fall back to writing alongside source if install path isn't writable
  if [[ ! -w $target_dir ]]; then
    target="${SHBANG_HOME}/tools/hocon-to-json/hocon.jar"
    log_info "  ${target_dir} not writable — building to ${target}"
    HOCON_JAR=$target
  fi

  local url="https://repo1.maven.org/maven2/com/typesafe/config/${TYPESAFE_CONFIG_VERSION}/config-${TYPESAFE_CONFIG_VERSION}.jar"
  local dep_tmp fat_tmp
  dep_tmp=$(mktemp /tmp/shbang-typesafe-XXXXXX.jar)
  fat_tmp=$(mktemp -d /tmp/shbang-hocon-fat-XXXXXX)

  log_info "  downloading typesafe-config ${TYPESAFE_CONFIG_VERSION}..."
  if ! shbang_curl -fsSL "$url" -o "$dep_tmp"; then
    rm -rf "$dep_tmp" "$fat_tmp"
    log_info "  download failed"
    return 1
  fi

  log_info "  compiling HoconToJson.java..."
  if ! javac --release 17 -encoding UTF-8 -cp "$dep_tmp" \
       "${SHBANG_HOME}/tools/hocon-to-json/HoconToJson.java" -d "$fat_tmp" 2>/dev/null; then
    rm -rf "$dep_tmp" "$fat_tmp"
    log_info "  compile failed"
    return 1
  fi

  (cd "$fat_tmp" && jar xf "$dep_tmp" 2>/dev/null)
  if ! jar cfe "$HOCON_JAR" HoconToJson -C "$fat_tmp" .; then
    rm -rf "$dep_tmp" "$fat_tmp"
    log_info "  jar packaging failed"
    return 1
  fi

  rm -rf "$dep_tmp" "$fat_tmp"
  log_info "  HOCON jar ready: ${HOCON_JAR}"
}

# Convert a HOCON file to a temp JSON file; prints the temp path to stdout.
# Caller is responsible for cleanup: rm "$tmp"
hocon_to_json() {
  local src=$1
  _ensure_hocon_jar \
    || die "cannot build HOCON jar — install a JDK, check network access, or set HOCON_JAR"
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

  # Convert HOCON → JSON if needed (.hocon or .conf are both HOCON)
  if [[ $ctx == *.hocon || $ctx == *.conf ]]; then
    local json_tmp
    # hocon_to_json calls die() in a subshell — $() masks the exit code, so check explicitly
    json_tmp=$(hocon_to_json "$ctx") || exit $?
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
