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
  command -v "$1" &> /dev/null
}

am_i_root() {
  [[ $(id -u) -eq 0 ]]
}

funcreturn() {
  echo "$@"
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
