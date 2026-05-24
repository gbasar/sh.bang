#!/usr/bin/env bash
# All terminal color/formatting for sh.bang output.
# Escape codes only — no business logic here.

# palette
C_RESET='\e[0m'
C_LABEL='\e[1;36m'       # cyan bold       — section headers
C_LOCAL='\e[1;32m'       # green bold       — $ local sigil
C_LOCAL_DIM='\e[2m'      # dim              — local cmd text
C_SCP='\e[1;34m'         # blue bold        — scp verb
C_SSH='\e[1;35m'         # magenta bold     — ssh verb
C_HOST='\e[1;32m'        # green bold       — @host
C_PATH='\e[2;3m'         # dim italic       — :path
C_REMOTE='\e[2m'         # dim              — remote output prefix
C_ERROR='\e[1;31m'       # red bold         — error lines in remote output

fmt_label() {
  printf "${C_LABEL}[ %s ]${C_RESET}\n" "$1"
}

fmt_local() {
  printf "  ${C_LOCAL}\$${C_RESET}  ${C_LOCAL_DIM}%s → %s${C_RESET}\n" "$1" "$2"
}

fmt_scp() {
  local arrow=$1 host=$2 path=$3 args=$4
  printf "  ${C_SCP}scp %s${C_RESET}  ${C_HOST}@%s${C_RESET}${C_PATH}:%s${C_RESET}  %s\n" \
    "$arrow" "$host" "$path" "$args"
}

fmt_ssh() {
  local host=$1 path=$2 args=$3
  printf "  ${C_SSH}ssh →${C_RESET}  ${C_HOST}@%s${C_RESET}${C_PATH}:%s${C_RESET}  %s\n" \
    "$host" "$path" "$args"
}

# Colorize a stream of remote output lines (piped via sed/awk).
# Usage: some_cmd 2>&1 | fmt_remote_output
fmt_remote_output() {
  local line
  while IFS= read -r line; do
    if [[ $line =~ ^(ssh:|scp:|Warning:|Error:) ]]; then
      printf "${C_ERROR}    | %s${C_RESET}\n" "$line"
    else
      printf "${C_REMOTE}    | ${C_RESET}%s\n" "$line"
    fi
  done
}
