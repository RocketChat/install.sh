#!/bin/bash

[[ -n "${__SOURCE_GUARD_LIB+@@@}" ]] && return
export __SOURCE_GUARD_LIB=

shopt -s expand_aliases

# if testing most debug functions and func* functions are
# going to be overwritten.
# these redirects would conflict with bats.
# shellcheck disable=2155,2120
__init_synchronous_communication() {
	[[ -z "${TEST_MODE+@@@}" ]] &&
		exec 4>&1 &&
		declare -g __func_returns="${1:-$(mktemp -p "${TMPDIR:-/tmp}" "__rocketchatctl__func_returnsXXXXX")}" &&
		exec 3>"$__func_returns" &&
		{ [[ -z "$1" ]] && trap 'rm -f '"'$__func_returns'"'' EXIT; }
}
__init_synchronous_communication

# shellcheck disable=1094
source "$(dirname "$(realpath "$0")")"/bash-argsparse/argsparse.sh
source "$(dirname "$(realpath "$0")")"/b-log/b-log.sh

command_exists() {
	command -v "$1" &>/dev/null
}

check_option_type_semver() {
	[[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

_get_last_existing_directory() {
	[[ -d "$1" ]] && funcreturn "$1" && return
	_get_last_existing_directory "$(dirname "$1")"
}

is_dir_accessible() {
	local dir="${1?must pass a directory path}"
	if [[ -f "$dir" ]]; then
		ERROR "$dir is a file; failing"
		return 1
	fi
	DEBUG "dir: $dir"
	dir="$(_get_last_existing_directory "$dir")"
	DEBUG "dir: $dir"
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

# shellcheck disable=2142
alias elevate_privilege='
        ((EUID)) && {
                local \
                        __opts \
                        __exported_funcs \
                        __environ \
                        __non_environ \
                        __sync_file
                __opts="$(mktemp)"
                __exported_funcs="$(mktemp)"
                __environ="$(mktemp)"
                __non_environ="$(mktemp)"
                __sync_file="${TMPDIR:-/tmp}/__elevated_${FUNCNAME[0]}_func_returns_$RANDOM"
                trap "rm -f $__opts $__exported_funcs $__environ $__non_environ" EXIT RETURN
                declare -x>"$__environ"
                declare +x>"$__non_environ"
                declare -Fx>"$__exported_funcs"
                shopt -p>"$__opts"
                command sudo bash -$- -c ". $__opts;. $__environ;. $__non_environ;. $__exported_funcs;__init_synchronous_communication $__sync_file;funcrun(){ eval $*; };${FUNCNAME[0]} $@" >&4
                tail -1 "$__sync_file" > $__func_returns
                return $?
        }
'
