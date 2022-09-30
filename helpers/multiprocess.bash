#!/bin/bash

_source "helpers/functool.bash"

declare -gA __pipes=()
declare -g __PIPE_PREFIX="___pipe"

# duplicate
is() {
	[[ $2 == "in" ]] || ERROR "noooo"

	# shellcheck disable=SC2155
	local check="$(printf '%s[%s]' "$3" "$1")"

	[[ -v $check ]]
}

atexit() {
  local command="${1?trap command required}"

  shift

  if (($# == 0)); then
    ERROR "signal required"
    return
  fi

  __trap_command() {
    local __signal="${1?signal required}"
    __extract() {
      local __command="${3}"
      [[ -z "$__command" ]] && return
      printf "%s;" "$__command"
    }
    eval "__extract $(trap -p "$__signal")"
    printf "%s" "$command"
  }
  for sig in "$@"; do
    # shellcheck disable=2064
    trap "$(__trap_command "$sig")" "$sig"
  done
}

background_execute() {
  local id="${1?job id required}"

  shift

  __pipes["$id"]="/tmp/${__PIPE_PREFIX}_$RANDOM"
  mkfifo "${__pipes[$id]}"

  local __cleanup_funcname="__cleanup_$RANDOM"
  eval "${__cleanup_funcname}() { rm -f ${__pipes["$id"]}; }"
  atexit "${__cleanup_funcname}" EXIT SIGINT

  __do() {
    DEBUG "starting background task $id"
    funcrun "$@" > "${__pipes[$id]}"
    DEBUG "background task $id completed"
  }

  __do "$@" &
}

background_read() {
  local id="${1?job id required}"
  if ! is "$id" in __pipes; then
    ERROR "unknown background task id $id"
    return
  fi

  __do() {
    DEBUG "reading from pipe ${__pipes["$id"]}"
    funcreturn "$(cat "${__pipes[$id]}")"
  }

  funcrun __do
}
