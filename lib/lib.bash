#!/bin/bash

[[ -n "${__SOURCE_GUARD_LIB+@@@}" ]] && return
export __SOURCE_GUARD_LIB=

# if testing most debug functions and func* functions are
# going to be overwritten.
# these redirects would conflict with bats.
# shellcheck disable=2155
[[ -z "${TEST_MODE+@@@}" ]] &&
	exec 4>&1 &&
	declare -g __func_returns="$(mktemp -p "${TMPDIR:-/tmp}" "__rocketchatctl__func_returnsXXXXX")" &&
	exec 3>"$__func_returns" &&
	trap 'rm -f '"'$__func_returns'"'' EXIT

# shellcheck disable=1094
source "$(dirname "$(realpath "$0")")"/bash-argsparse/argsparse.sh

command_exists() {
	command -v "$1" &>/dev/null
}

check_option_type_semver() {
	[[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
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
	DEBUG "uid: $uid"
	gid="$(id -g)"
	DEBUG "gid: $gid"
	dir_owner_uid="$(stat -c "%u" "$dir")"
	dir_owner_gid="$(stat -c "%g" "$dir")"
	dir_perm_oct="$(stat -c "%a" "$dir")"
	DEBUG "dir_owner_uid: $dir_owner_uid"
	DEBUG "dir_owner_gid: $dir_owner_gid"
	DEBUG "dir_perm_oct: $dir_perm_oct"
	if {
		((uid == dir_owner_uid)) && (((dir_perm_oct / 100) == 7))
	} ||
		{
			((gid == dir_owner_gid)) && ((((dir_perm_oct % 100) / 10) == 7))
		}; then
		return 0
	fi
	# thanks bash; what I actually mean is ==7
	return $((((dir_perm_oct % 100) % 10) != 7))
}

path_join() {
	printf "%s/%s" "${1%/}" "$2"
}

funcrun() {
	eval "$*" >&4
	# wish I knew of a better way :/
	tail -1 "$__func_returns"
}

funcreturn() {
	echo "$@" >&3
}

path_append() {
	local ifs="$IFS" path
	IFS=:
	for path in $PATH; do
		[[ "$path" == "$1" ]] && return
	done
	IFS="$ifs"
	export PATH="${1}:$PATH"
}

sudo() {
	command sudo -E env PATH="$PATH" "$@"
}

node_confirm_version() {
	node -e "process.exit(/${1:-.+}/.test(process.version) ? 0 : 1)"
}
