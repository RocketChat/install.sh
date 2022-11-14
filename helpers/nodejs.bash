#!/bin/bash

_source "helpers/lib.bash"

_install_nvm() {
	# https://github.com/nvm-sh/nvm#installation
	INFO "nstalling nvm"
	DEBUG "setting NVM_DIR to /opt/nvm"
	if (sudo mkdir /opt/nvm && sudo chown "$(id -u)":"$(id -g)" /opt/nvm) 2> /dev/null; then
		export NVM_DIR="/opt/nvm"
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
_n_or_nvm_install_node() {
	local manager="${1?node version manager is required}"
	local node_version="${2?node version is required}"
	if ! "$manager" install "$node_version"; then
		FATAL "failed to install $node_version using $manager"
		exit 1
	fi
	if funcreturn "$(dirname "$("$manager" which "$node_version")")"; then
		ERROR "failed to capture installed node binary path"
		WARN "falling back on /usr/local/bin/node"
		funcreturn "/usr/local/bin"
	fi
}

_nvm_install_node() {
	_n_or_nvm_install_node "nvm" "${1}"
}

_n_install_node() {
	_n_or_nvm_install_node "n" "${1}"
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
	if command_exists "node"; then
		node_exists=1
	else
		local _node
		if ((n)); then
			if command_exists n && _node="$(dirname "$(n which "$node_version" 2> /dev/null)")"; then
				path_environment_append "$_node"
				node_exists=1
			fi
		elif ((nvm)); then
			local nvm_dir
			{ [[ -f /opt/nvm/nvm.sh ]] && nvm_dir=/opt/nvm; } ||
				{ [[ -f $HOME/.nvm/nvm.sh ]] && nvm_dir=$HOME/.nvm; }
			if [[ -n "$nvm_dir" ]] && _node="$(dirname "$(BASH_ENV="$nvm_dir/nvm.sh" bash -c "nvm which $node_version" 2> /dev/null)")"; then
				path_environment_append "$_node"
				node_exists=1
			fi
		fi
	fi
	_debug "node_exists"
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
