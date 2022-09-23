#! /usr/bin/env bash

_source "messages/en.bash"

# @public
# just syntactic sugar
is() {
  [[ $2 == "in" ]] || print_wrong_is_utility_usage

  # shellcheck disable=SC2155
  local check="$(printf '%s[%s]' "$3" "$1")"

  [[ -v $check ]]
}

command_exists() {
  command -v "$1" &>/dev/null
}

am_i_root() {
  [[ $(id -u) -eq 0 ]]
}
