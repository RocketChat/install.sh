#!/bin/bash

[ -n "${__SOURCE_GUARD_NODEJS+@@@}" ] && return
export __SOURCE_GUARD_NODEJS=

source "bash-argsparse/argsparse.sh"

source "lib/lib.bash"
source "b-log/b-log.sh"

_install_n() {
	# responsibility of checking for node and npm is of the caller's
	INFO "installing n"
	if ! sudo npm i n -g; then
		FATAL "failed to install n"
		return 1
	fi
	SUCCESS "successfully installed n"
}

_install_nvm() {
	:
}

_nvm_install_nodejs() {
	:
}

_n_install_nodejs() {
	:
}

_manual_install_nodejs() {
	:
}

install_nodejs() {
	local node_version=
	argsparse_use_option use-nvm "use nvm for installing nodejs"
	argsparse_use_option use-n "use n for installing nodejs"
	argsparse_use_option node-version: "required nodejs version" mandatory type:semver
	parse_arguments
	if use_n; then
		_install_n
		_n_install_nodejs "$node_version"
		return
	fi
	if use_nvm; then
		_install_nvm
		_nvm_install_nodejs "$node_version"
		return
	fi
	_manual_install_nodejs "$node_version"
}
