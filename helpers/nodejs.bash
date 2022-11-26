#!/bin/bash

[[ -n "${__GUARD_SOURCE_NODEJS+-@}" ]] && return
export __GUARD_SOURCE_NODEJS=

source "helpers/lib.bash"

# shellcheck disable=2120
_install_nvm() {
	# https://github.com/nvm-sh/nvm#installation
	local nvm_dir="${1:-/opt/nvm}"
	_debug "nvm_dir"
	INFO "installing nvm"
	DEBUG "setting NVM_DIR to $nvm_dir"
	if (sudo mkdir "$nvm_dir" && sudo chown "$(id -u)":"$(id -g)" "$nvm_dir") 2> /dev/null; then
		export NVM_DIR="$nvm_dir"
	else
		WARN "failed to create /opt/nvm; installing nvm in $HOME/.nvm"
		export NVM_DIR="$HOME/.nvm"
	fi
	_debug "NVM_DIR"
	# TODO change hardcoded nvm version
	if ! curl -fSLso- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh |
		bash &> /dev/null; then
		FATAL "failed to install nvm; halting installation"
		exit 1
	fi
	SUCCESS "successfully installed nvm"
}

_install_n() {
	if ! command_exists "npm"; then
		FATAL "pre-installed node/npm required for using n"
		exit 1
	fi
	INFO "installing n"
	sudo npm i n -g &> /dev/null || FATAL "failed to install n, can't move on with the installation"
	SUCCESS "successfully installed n"
}

_n_install_node() {
	local node_version="${1?node version is required}"
	if ! n install "$node_version"; then
		FATAL "failed to install $node_version using n"
		exit 1
	fi
	funcreturn "$(dirname "$(n which "$node_version")")" && return
	ERROR "failed to capture installed node binary path"
	WARN "falling back on /usr/local/bin/node"
	funcreturn "/usr/local/bin"
}

_nvm_install_node() {
	local node_version="${1?node version is required}"
	_nvm() { BASH_ENV="$NVM_DIR/nvm.sh" bash -c "nvm $*"; }
	if ! _nvm install "$node_version"; then
		FATAL "failed to install $node_version using nvm"
		exit 1
	fi
	funcreturn "$(dirname "$(_nvm which "$node_version")")" && return
	ERROR "failed to capture installed node binary path"
	WARN "falling back on /usr/local/bin/node"
	funcreturn "/usr/local/bin"
}

_n_handle() {
	local node_version="${1?node version must be passed}"
	INFO "using n to manage nodejs"
	_install_n
	_n_install_node "$node_version"
}

_nvm_handle() {
	local node_version="${1?node version must be passed}"
	INFO "using nvm to manage nodejs"
	_install_nvm
	_nvm_install_node "$node_version"
}

_manual_install_node() {
	# @returns node binary path
	local node_version="${1?node version must be passed}"
	local archive_file_name="node-v$node_version-linux-x64"
	_debug "archive_file_name"
	local url="https://nodejs.org/dist/v$node_version/$archive_file_name.tar.xz"
	_debug "url"
	INFO "downloading node $node_version installation archive"
	if ! (
		cd /tmp
		curl -sLO --fail "$url"
	); then
		FATAL "failed to download nodejs archive"
		FATAL "cannot move on with installation without a valid node binary; exiting..."
		exit 1
	fi
	INFO "installing nodejs in /opt/nodejs"
	# TODO handle directory creation better
	# FIXME you know what
	[[ -d /opt/nodejs ]] || sudo mkdir /opt/nodejs
	if ! tar -xJf "/tmp/$archive_file_name.tar.xz" -C /opt/nodejs; then
		FATAL "failed to extract archive; nodejs install failed"
		FATAL "cannot move on with installation without a valid node binary; exiting..."
		exit 1
	fi
	local new_path="/opt/nodejs/$archive_file_name/bin"
	_debug "new_path"
	funcreturn "$new_path"
}

check_node_exists_and_fix_path_for_script() {
	local \
		node_version \
		_node \
		nvm_dir
	node_version="${1?node version must be passed}"
	_debug "node_version"
	if command_exists "node"; then
		return 0
	fi
	# if using n, expect it (n) to be in PATH
	if command_exists n && _node="$(dirname "$(n which "$node_version" 2> /dev/null)")"; then
		path_environment_append "$_node"
		return 0
	fi
	if command_exists nvm && _node="$(dirname "$(nvm which "$node_version" 2> /dev/null)")"; then
		path_environment_append "$_node"
		return 0
	fi
	# in case nvm source is not in bashrc/zshrc or similar
	local nvm_dir
	# it's either the custom nvm_dir rocketchatctl sets or the default
	{ [[ -f /opt/nvm/nvm.sh ]] && nvm_dir=/opt/nvm; } || { [[ -f $HOME/.nvm/nvm.sh ]] && nvm_dir=$HOME/.nvm; }
	if [[ -n "$nvm_dir" ]] && _node="$(dirname "$(BASH_ENV="$nvm_dir/nvm.sh" bash -c "nvm which $node_version" 2> /dev/null)")"; then
		path_environment_append "$_node"
		return 0
	fi
	# sorry, no node
	return 1
}

# change usage of globals
install_node() {
	# @returns node binary path
	local \
		OPTARG \
		_opt \
		node_version \
		node_exists=0 \
		install_node \
		n \
		nvm
	OPTIND=0
	# -v version, -y install_node, -n use n, -b use nvm
	while getopts "v:ynb" _opt; do
		case "$_opt" in
			v)
				node_version="$OPTARG"
				_debug "node_version"
				;;
			y)
				install_node=1
				_debug "install_node"
				;;
			n)
				n=1
				_debug "n"
				;;
			b)
				nvm=1
				_debug "nvm"
				;;
			*)
				ERROR "unknown option"
				;;
		esac
	done
	node_version="${node_version?nodejs version string required}"
	# FIXME
	check_node_exists_and_fix_path_for_script "$node_version" && node_exists=1
	if ! ((install_node)) && ((node_exists)); then
		print_node_version_error_and_exit
	fi
	if ((node_exists)) && node -e "process.exit(process.version === 'v${node_version}' ? 0 : 1)"; then
		SUCCESS "node version satisfied"
		funcreturn "$(dirname "$(which node)")"
		return
	fi
	if ((n)); then
		_n_handle "$node_version"
		return
	fi
	if ((nvm)); then
		_nvm_handle "$node_version"
		return
	fi
	# default
	_manual_install_node "$node_version"
}
