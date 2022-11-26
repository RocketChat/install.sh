#!/bin/bash

[[ -n "${__GUARD_SOURCE_MONGODB+@}" ]] && return
export __GUARD_SOURCE_MONGODB=

source "b-log/b-log.sh"
source "helpers/lib.bash"

M_BIN_URL="https://raw.githubusercontent.com/aheckmann/m/master/bin/m"

get_current_mongodb_storage_engine() {
	funcreturn "$(mongo --quiet --eval 'db.serverStatus().storageEngine.name')"
}

get_current_mongodb_version() {
	funcreturn "$(mongo --quiet --eval 'db.version.split(".").splice(0, 2).join(".")')"
}

is_storage_engine_wiredTiger() {
	[[ "wiredTiger" == "$(funcrun get_current_mongodb_storage_engine)" ]]
}

is_mongod_ready() {
	local max_attempt=30 \
		current=0
	while ((current < max_attempt)); do
		(("$(mongo 2> /dev/null --quiet --eval 'db.adminCommand({ ping: 1 }).ok')" == 1)) && return 0
		((current++))
		sleep 1
	done
	return 1
}

_install_m() {
	# @returns m path
	local \
		m_dir \
		m_bin
	m_dir="$HOME/.local/bin"
	[[ -d "$m_dir" ]] || mkdir "$m_dir" -p
	m_bin="$(path_join "$m_dir" m)"
	if ! curl -fsSLo "$m_bin" "$M_BIN_URL" --fail; then
		FATAL "failed to install m. you can try using manual install method instead"
		exit 1
	fi
	chmod u+x "$m_bin"
	SUCCESS "successfully installed mongodb version manager (m)"
	funcreturn "$m_dir"
}

_m_install_mongodb() {
	# @returns install path
	local \
		mongodb_version \
		m_bin
	mongodb_version="${1?mongodb version must be passed}"
	m_bin="$(funcrun _install_m)"
	_debug "m_bin"
	path_environment_append "$m_bin"
	if ! m "$mongodb_version"; then
		FATAL "failed to install mongodb version $mongodb_version; exiting ..."
		exit 1
	fi
	# m returns path without binary name appended
	funcreturn "$(m which "$mongodb_version")"
}

_deb_setup_repo() {
	local mongodb_version="${1?mongodb version required}"
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
	curl -fsSL "$key_url" | sudo gpg --dearmor -o "$key_file"
	echo "$repo_url" | sudo tee "$repo_file" > /dev/null
}

_rpm_setup_repo() {
	local mongodb_version="${1?mongodb version required}"
	local yum_mongo_url="https://repo.mongodb.org/yum/redhat/$DISTRO_VERSION/mongodb-org/$mongodb_version/x86_64/"
	local yum_key="https://www.mongodb.org/static/pgp/server-$mongodb_version.asc"
	INFO "saving repository data to file"
	cat << EOF | sudo tee -a "/etc/yum.repos.d/mongodb-org-$mongodb_version.repo"
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

_manual_install_mongodb() {
	# @returns install path
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
		exit 1
	fi
	funcreturn "$(dirname "$(which mongod)")"
}

install_mongodb() {
	# @returns install path
	local \
		OPTARG \
		_opt \
		m \
		mongodb_version
	while getopts "mv:" _opt; do
		case "$_opt" in
			m)
				# use m?
				m=1
				_debug "m"
				;;
			v)
				mongodb_version="$OPTARG"
				_debug "mongodb_version"
				;;
			*) ERROR "unknown option" ;;
		esac
	done
	if ((m)); then
		INFO "using m for mongodb"
		_m_install_mongodb "$mongodb_version"
		return
	fi
	INFO "manually installing mongodb"
	_manual_install_mongodb "$mongodb_version"
}
