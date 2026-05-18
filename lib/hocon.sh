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

# If ctx path ends in .hocon, convert and return a temp JSON path.
# Otherwise return the path unchanged.  Caller owns cleanup of any temp file.
resolve_ctx() {
  local ctx=$1
  if [[ $ctx == *.hocon ]]; then
    hocon_to_json "$ctx"
  else
    printf '%s' "$ctx"
  fi
}
