#!/bin/bash

[ -n "${__SOURCE_GUARD_LIB+@@@}" ] && return
export __SOURCE_GUARD_LIB=

shopt -s expand_aliases

source "bash-argsparse/argsparse.sh"

command_exists() {
	local command="${1?command must be passed}"
	command -v "$command" &>/dev/null
}

# shellcheck disable=2154,2142
#	(parse_arguments is referenced but not assigned)
#	(aliases can't use positional arguments, use a function)
alias parse_arguments='
	argsparse_parse_options "$@";
	local __argument_identifier __argument_identifier_stripped __argument_identifier_value;
	local __eval_option_string
	for __argument_identifier in "${!program_options[@]}"; do
		__argument_identifier_stripped="${__argument_identifier//-/_}"
		__argument_identifier_value="${program_options[${__argument_identifier}]}"
		if argsparse_has_option_property "$__argument_identifier" value; then
			__eval_option_string+="local ${__argument_identifier_stripped}=${__argument_identifier_value};"
			continue
		fi
		__eval_option_string+="function $__argument_identifier_stripped { (($__argument_identifier_value)); };"
	done
	[[ -n "$__eval_option_string" ]] && eval "$__eval_option_string"
'

check_option_type_semver() {
	local value="${1?version string required}"
	[[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
