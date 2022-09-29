#!/bin/bash

declare -gA __pipes=()
declare -g __PIPE_PREFIX="__rocketchatctl_pipe"

background_execute() {
  local id="${1?job id required}"

  shift

  __pipes["$id"]="/tmp/${__PIPE_PREFIX}_$RANDOM"
  mkfifo "${__pipes[$id]}"

  trap 'rm -f '"${__pipes[$id]}"'' 1 2 3

  __do() {
    DEBUG "starting background task $id"
    printf "$id: %s" "$(funcrun "$@")" > "${__pipes[$id]}"
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

  funcreturn "$(cat "${__pipes[$id]}")"
}
