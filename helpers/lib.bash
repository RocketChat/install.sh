#! /usr/bin/env bash

source "../errors/errors.bash"

# @public
# just syntactic sugar
is() {
  [[ $2 == "in" ]] || print_wrong_is_utility_usage

  local check="$(printf '%s[%s]' $3 $1)"

  [[ -v $check ]]
}

command_exists() {
  &>/dev/null { command -v "$1" || type "$1" }
}
