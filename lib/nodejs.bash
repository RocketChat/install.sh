#!/bin/bash

[[ -n "${__SOURCE_GUARD_NODEJS+@@@}" ]] && return
export __SOURCE_GUARD_NODEJS=

# HOW THE HECK DO I TEST THESE FUNCTIONS?:quiet
source "$(dirname "$(realpath "$0")")"/bash-argsparse/argsparse.sh
source "$(dirname "$(realpath "$0")")"/b-log/b-log.sh

source "$(dirname "$(realpath "$0")")"/lib/lib.bash

# @brief run nvm through a new bash shell
# @details
# `source $NVM_DIR/nvm.sh has proven to be problematic
# @return 1 if BASH_ENV is empty
nvm() {
	[[ -z "$_BASH_ENV" ]] && return 1
	BASH_ENV="$_BASH_ENV" bash -c "nvm $*"
}

# @brief install n
# @details
# Installs n; if node or npm is not found in PATH
# this function fails verbosely.
# @return 0 if successful 1 if not
_install_n() {
	if ! command_exists node && ! command_exists npm; then
		FATAL "installing n requires some version of npm and nodejs already installed" \
			", can't move forward"
		return 1
	fi
	INFO "installing n"
	if command_exists n; then
		SUCCESS "n is already installed"
		return 0
	fi
	if ! sudo npm i n -g; then
		FATAL "failed to install n"
		return 1
	fi
	SUCCESS "successfully installed n"
}

# @brief install nvm
# @details
# Install the nvm script. But does not source it.
# Instead it adds a "wrapper" of sorts so that the following steps can call the
# command directly. This way each call will have a fresh environment.
# @param where to install the script
# @return 1 if unsuccessful
_install_nvm() {
	local nvm_dir="$1"
	DEBUG "nvm_dir: $nvm_dir"
	INFO "installing nvm"
	# my nvm function is not as long as the actual one :p
	if (($(type nvm | wc -l) == 4)); then
		nvm() { command nvm "@"; } # overwrite the BASH_ENV function as that's not needed anymore
		SUCCESS "nvm is already installed"
		return 0
	elif [[ -d "$nvm_dir" ]]; then
		export _BASH_ENV="$(path_join "$nvm_dir" "nvm.sh")"
		SUCCESS "nvm is already installed"
		return 0
	elif [[ -d "$HOME/.nvm" ]]; then
		export _BASH_ENV="$HOME/.nvm/nvm.sh"
		SUCCESS "nvm is already installed"
		return 0
	fi
	# TODO change version
	local cmd=(git clone --quiet https://github.com/nvm-sh/nvm --depth 1 -b "v0.39.1" "$nvm_dir")
	is_dir_accessible "$(dirname "$nvm_dir")" || cmd=(sudo "${cmd[@]}")
	if ! ("${cmd[@]}" && sudo chown -R "$(id -u)":"$(id -g)" "$nvm_dir"); then
		FATAL "failed to install nvm" \
			"can not move forward with the installation anymore"
		return 1
	fi
	DEBUG "setting temporary BASH_ENV for nvm commands"
	export _BASH_ENV="$(path_join "$nvm_dir" "nvm.sh")"
	SUCCESS "successfully installed nvm"
}

# @return path to installed nodejs binary
_nvm_install_nodejs() {
	local node_version="${1?node version is required}"
	if ! nvm install "$node_version"; then
		FATAL "failed to install $node_version using nvm"
		return 1
	fi
	funcreturn "$(dirname "$(nvm which "$node_version")")" && return
	ERROR "failed to capture installed node binary path"
	WARN "falling back on /usr/local/bin/node"
	funcreturn "/usr/local/bin"
}

# @return path to installed nodejs binary
_n_install_nodejs() {
	local node_version="${1?node version is required}"
	if ! n install "$node_version"; then
		FATAL "failed to install $node_version using n"
		return 1
	fi
	funcreturn "$(dirname "$(n which "$node_version")")" && return
	ERROR "failed to capture installed node binary path"
	WARN "falling back on /usr/local/bin/node"
	funcreturn "/usr/local/bin"
}

# @param node version, install path
_manual_install_nodejs() {
	local node_version="${1?node version is required}"
	local install_path="${2?install path required}"
	if command_exists node && node_confirm_version "$node_version"; then
		SUCCESS "existing node installation version satisfied"
		return 0
	fi
	local archive_file_name="node-v$node_version-linux-x64"
	DEBUG "archive_file_name: $archive_file_name"
	local url="https://nodejs.org/dist/v$node_version/$archive_file_name.tar.xz"
	DEBUG "url: $url"
	INFO "downloading node $node_version installation archive"
	if ! (
		cd /tmp
		curl -sLO --fail "$url"
	); then
		FATAL "failed to download nodejs archive"
		FATAL "cannot move on with installation without a valid node binary; exiting..."
		return 1
	fi
	INFO "installing nodejs in $install_path"
	# TODO handle directory creation better
	# FIXME you know what
	[[ -d "$install_path" ]] || sudo mkdir "$install_path"
	if ! tar -xJf "/tmp/$archive_file_name.tar.xz" -C "$install_path"; then
		FATAL "failed to extract archive; nodejs install failed"
		FATAL "cannot move on with installation without a valid node binary; exiting..."
		return 1
	fi
	local new_path="$(path_join "$install_path" "$(path_join "$archive_file_name" "bin")")"
	DEBUG "new_path: $new_path"
	funcreturn "$new_path"
}

install_nodejs() {
	local node_version="${1?node version is required}"
	# use_n and use_nvm should be available after top level parse_arguments
	if use_n; then
		if ! { _install_n && _n_install_nodejs "$node_version"; }; then
			FATAL "failed to install nodejs"
			return 1
		fi
		return 0
	fi
	if use_nvm; then
		if ! { _install_nvm "/opt/nvm" && _nvm_install_nodejs "$node_version"; }; then
			FATAL "failed to install nodejs"
			return 1
		fi
		return 0
	fi
	DEBUG "attempting manually installing nodejs v$node_version"
	_manual_install_nodejs "$node_version" "/opt/nodejs"
}
