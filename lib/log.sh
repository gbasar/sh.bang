#!/usr/bin/env bash

# Log functions emit structured events through the event system.
# BASH_SOURCE[1]:BASH_LINENO[0] captures the caller's location, not this file.

log_info()  { _emit_raw log.info  "${BASH_SOURCE[1]}:${BASH_LINENO[0]}" message "$*"; }
log_debug() { _emit_raw log.debug "${BASH_SOURCE[1]}:${BASH_LINENO[0]}" message "$*"; }
log_trace() { _emit_raw log.trace "${BASH_SOURCE[1]}:${BASH_LINENO[0]}" message "$*"; }
log_wire()  { _emit_raw log.wire  "${BASH_SOURCE[1]}:${BASH_LINENO[0]}" message "$*"; }

# die bypasses the event system — direct stderr only — to avoid any risk of
# recursion if the event system itself is broken.
die() {
  printf '[sh.bang:error] %s\n' "$*" >&2
  exit 1
}
