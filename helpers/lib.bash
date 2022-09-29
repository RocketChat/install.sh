#! /usr/bin/env bash

_source "messages/en.bash"
_source "b-log/b-log.sh"

{
  # shellcheck disable=2155
  if ! declare -g __func_returns="$(mktemp -t rocketchatctl__func_returnsXXXXXXXXXX)"; then
    FATAL "failed to pipe function output"
    exit 10
  fi

  exec 3> "$__func_returns"
  exec 4>&1
}

_debug() {
  # @description helper for variable debug messages
  # @params variable name
  local \
    _var_name \
    _var_value
  _var_name="${1?variable name must be passed}"
  _var_value="$(eval printf "\$\"$_var_name\"")"
  B_LOG_print_message "${LOG_LEVEL_DEBUG}" "${_var_name}: ${_var_value}"
}

# @public
# just syntactic sugar
is() {
  [[ $2 == "in" ]] || print_wrong_is_utility_usage

  # shellcheck disable=SC2155
  local check="$(printf '%s[%s]' "$3" "$1")"

  [[ -v $check ]]
}

command_exists() {
  command -v "$1" &> /dev/null
}

am_i_root() {
  [[ $(id -u) -eq 0 ]]
}

funcreturn() {
  echo "$@" >&3
}

funcrun() {
  eval "$*" >&4
  # wish I knew of a better way :/
  tail -1 "$__func_returns"
}

is_dir_accessible() {
  local dir="${1?must pass a directory path}"
  if ! [[ -d "$dir" ]]; then
    ERROR "$dir is not a directory; failing"
    return 1
  fi

  local \
    uid \
    gid \
    dir_owner_uid \
    dir_owner_gid \
    dir_perm_oct

  uid="$(id -u)"
  gid="$(id -g)"

  dir_owner_uid="$(stat -f "%u" "$dir")"
  dir_owner_gid="$(stat -f "%g" "$dir")"
  dir_perm_oct="$(stat -f "%Lp" "$dir")"

  if {
    ((uid == dir_owner_uid))   && (((dir_perm_oct / 100) == 7))
  }   ||
    {
      ((gid == dir_owner_gid))   && ((((dir_perm_oct % 100) / 10) == 7))
    }; then
    return 0
  fi

  # thanks bash; what I actually mean is ==7
  return $((((dir_perm_oct % 100) % 10) != 7))
}
