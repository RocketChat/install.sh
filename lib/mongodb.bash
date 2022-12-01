#!/bin/bash

[[ -n "${__SOURCE_GUARD_MONODB+@@@}" ]] && return
export __SOURCE_GUARD_MONODB=

source "$(dirname "$(realpath "$0")")"/lib/lib.bash
source "$(dirname "$(realpath "$0")")"/lib/host.bash

export M_BIN_URL="https://raw.githubusercontent.com/aheckmann/m/master/bin/m"

get_current_mongodb_storage_engine() {
	funcreturn "$(mongo --quiet --eval 'db.serverStatus().storageEngine.name')"
}

get_current_mongodb_version() {
	funcreturn "$(mongo --quiet --eval 'db.version().split(".").splice(0, 2).join(".")')"
}

is_storage_engine_wiredTiger() {
	[[ "wiredTiger" == "$(funcrun get_current_mongodb_storage_engine)" ]]
}

is_mongod_ready() {
	local max_attempt=30 \
		current=0
	while ((current < max_attempt)); do
		(("$(mongo 2>/dev/null --quiet --eval 'db.adminCommand({ ping: 1 }).ok')" == 1)) && return 0
		current=$((current + 1))
		sleep 1
	done
	return 1
}

# @return mongodb install path
_install_m() {
	local \
		m_dir \
		m_bin
	m_dir="$HOME/.local/bin"
	m_bin="$m_dir/m"
	if command_exists m || [[ -x $m_bin ]]; then
		SUCCESS "m is already installed"
		funcreturn "$m_dir"
		return 0
	fi
	[[ -d "$m_dir" ]] || mkdir "$m_dir" -p
	if ! curl -fsSLo "$m_bin" "$M_BIN_URL" --fail; then
		FATAL "failed to install m. you can try using manual install method instead"
		return 1
	fi
	chmod u+x "$m_bin"
	SUCCESS "successfully installed mongodb version manager (m)"
	funcreturn "$m_dir"
}

# @return mongobd install path
_m_install_mongodb() {
	local \
		mongodb_version \
		m_bin
	mongodb_version="${1?mongodb version must be passed}"
	if ! command_exists m; then
		FATAL "asked to install using m, but m not found in PATH"
		return 1
	fi
	if ! yes | m "$mongodb_version"; then
		FATAL "failed to install mongodb version $mongodb_version; exiting ..."
		return 1
	fi
	# m returns path withou binary name appended
	funcreturn "$(m bin "$mongodb_version")"
}

_deb_setup_repo() {
	elevate_privilege
	local mongodb_version="${1?mongodb version required}"
	mongodb_version="${mongodb_version%.*}"
	local key_url="https://www.mongodb.org/static/pgp/server-$mongodb_version.asc"
	local key_file="/usr/share/keyrings/mongodb-org-$mongodb_version.gpg"
	local repo_file="/etc/apt/sources.list.d/mongodb-org-$mongodb_version.list"
	DEBUG "key_url: $key_url"
	DEBUG "key_file: $key_file"
	DEBUG "repo_file: $repo_file"
	declare -A repo=
	repo=([ubuntu]="multiverse" [debian]="main")
	local repo_url="deb [ arch=amd64 signed-by=$key_file ] https://repo.mongodb.org/apt/$DISTRO $DISTRO_CODENAME/mongodb-org/$mongodb_version ${repo[$DISTRO]}"
	DEBUG "repo_url: $repo_url"
	INFO "saving repository data to file"
	curl -fsSL "$key_url" | gpg --dearmor -o "$key_file"
	echo "$repo_url" | tee "$repo_file" >/dev/null
}

_rpm_setup_repo() {
	elevate_privilege
	local mongodb_version="${1?mongodb version required}"
	mongodb_version="${mongodb_version%.*}"
	local yum_mongo_url="https://repo.mongodb.org/yum/redhat/$DISTRO_VERSION/mongodb-org/$mongodb_version/x86_64/"
	local yum_key="https://www.mongodb.org/static/pgp/server-$mongodb_version.asc"
	INFO "saving repository data to file"
	cat <<EOF | tee >/dev/null "/etc/yum.repos.d/mongodb-org-$mongodb_version.repo"
[mongodb-org-$mongodb_version]
name=MongoDB Repository
baseurl=$yum_mongo_url
gpgcheck=1
enabled=1
gpgkey=$yum_key
EOF
	DEBUG "yum_mongo_url: $yum_mongo_url"
	DEBUG "yum_key: $yum_key"
}

# @returns install path
_manual_install_mongodb() {
	elevate_privilege
	local mongodb_version="${1?mongodb version must be passed}"
	case "$DISTRO" in
	debian | ubuntu)
		_deb_setup_repo "$mongodb_version"
		pkm update
		;;
	centos)
		_rpm_setup_repo "$mongodb_version"
		pkm check-update
		;;
	esac
	if ! pkm install -y "mongodb-org"; then
		FATAL "failed to install mongodb version $mongodb_version; exiting ..."
		return 1
	fi
	funcreturn "$(dirname "$(which mongod)")"
}

install_mongodb() {
	local mongodb_version="${1?mongodb version required}"
	# use_m should be available after top level parse_arguments
	if use_m; then
		local m_path
		m_path="$(_install_m)" || return 1
		path_append "$m_path"
		_m_install_mongodb "$mongodb_version" && return 0
		return 1
	fi
	_manual_install_mongodb "$mongodb_version" && return 0
	return 1
}
