#! /usr/bin/env bash

_source "messages/en.bash"
_source "b-log/b-log.sh"
_source "bash_concurrent/multiprocess.bash"

_debug() {
	# @description helper for variable debug messages
	# @params variable name
	local \
		_var_name \
		_var_value \
		_var_str \
		_var_name="${1?variable name must be passed}"
	if declare 2> /dev/null -p "$_var_name" | grep -Eq '^declare -a'; then
		# shellcheck disable=2016
		_var_str='${'"$_var_name"'[@]}'
	else
		_var_str="\$$_var_name"
	fi
	_var_value="$(eval echo -n "$_var_str")"
	B_LOG_print_message "${LOG_LEVEL_DEBUG}" "${_var_name}: ${_var_value}"
}

# @public
# just syntactic sugar
is() {
	[[ $2 == "in" ]] || print_wrong_is_utility_usage # FIXME move away from error methods 
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
	_debug "uid"
	gid="$(id -g)"
	_debug "gid"
	dir_owner_uid="$(stat -c "%u" "$dir")"
	dir_owner_gid="$(stat -c "%g" "$dir")"
	dir_perm_oct="$(stat -c "%a" "$dir")"
	_debug "dir_owner_uid"
	_debug "dir_owner_gid"
	_debug "dir_perm_oct"
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

path_join() {
	local \
		left \
		right
	left="${1?path required}"
	right="${2?path required}"
	printf "%s/%s" "${left%/}" "$right"
}

path_environment_append() {
	local _path="$1"
	[[ -z "$_path" ]] && return
	[[ "$PATH" == ?(*:)"$_path"?(:*) ]] || export PATH="$_path:$PATH"
}

