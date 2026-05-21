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

  local -a curl_args=(-fsSL "$url" -o "$tmp")
  if [[ -n ${GITLAB_TOKEN:-} ]]; then
    curl_args+=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
  elif [[ -n ${CTX_TOKEN:-} ]]; then
    curl_args+=(-H "Authorization: Bearer ${CTX_TOKEN}")
  fi

  curl "${curl_args[@]}" \
    || { rm -f "$tmp"; die "failed to fetch ctx: $url"; }

  printf '%s' "$tmp"
}

# Resolve ctx to a local JSON file path, eagerly.
# - URL (http/https): downloaded immediately, GITLAB_TOKEN/CTX_TOKEN used if set
# - .hocon (local or downloaded): converted to JSON via hocon.jar
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
