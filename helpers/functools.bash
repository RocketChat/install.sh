#!/bin/bash

{
  # shellcheck disable=2155
  if ! declare -g __func_returns="$(mktemp -t rocketchatctl__func_returnsXXXXXXXXXX)"; then
    FATAL "failed to pipe function output"
    exit 10
  fi

  exec 3> "$__func_returns"
  exec 4>&1
}

funcreturn() {
  echo "$@" >&3
}

funcrun() {
  eval "$*" >&4
  # wish I knew of a better way :/
  tail -1 "$__func_returns"
}
