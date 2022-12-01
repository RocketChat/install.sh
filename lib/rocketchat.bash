#!/bin/bash

[[ -n "${__SOURCE_GUARD_ROCKETCHAT+@@@}" ]] && return
export __SOURCE_GUARD_ROCKETCHAT=

source "$(dirname "$(realpath "$0")")"/lib/lib.bash

export __RELEASE_INFO_JSON=
export __COMPATIBLE_MONGODB_VERSIONS_JSON=

# @details
# checks if the provided version string is valid or not
# then saves the information in __RELEASE_INFO_JSON state
# @return 1 if invalid version
verify_release() {
	local release="${1?release version must be passed}"
	INFO "verifying passed version ($release) if it exists"
	local release_info_endpoint="https://releases.rocket.chat/$release/info"
	DEBUG "release_info_endpoint: $release_info_endpoint"
	if ! __RELEASE_INFO_JSON="$(curl -s "$release_info_endpoint")"; then
		FATAL "failed to resolve release information ($release)"
		return 1
	fi
	DEBUG "__RELEASE_INFO_JSON: $__RELEASE_INFO_JSON"
	if [[ "$release" != "latest" ]] && ! jq >/dev/null '.tag' -er <<<"$__RELEASE_INFO_JSON"; then
		FATAL "specified release $release not found"
		return 1
	fi
	local compatible_mongodb_versions=
	compatible_mongodb_versions="$(jq '.compatibleMongoVersions // empty' -c <<<"$__RELEASE_INFO_JSON")"
	[[ -z "$compatible_mongodb_versions" ]] && WARN "i can't detect the supported mongodb versions for the version you selected." \
		"this means you're trying to install a very old version of Rocket.Chat, which is not recommended." \
		"please install a newer version of, check https://github.com/RocketChat/Rocket.Chat/releases for more information." \
		"for now falling back to mongodb 3.6"
	__COMPATIBLE_MONGODB_VERSIONS_JSON="${compatible_mongodb_versions:-["3.6"]}"
	DEBUG "__COMPATIBLE_MONGODB_VERSIONS_JSON: $__COMPATIBLE_MONGODB_VERSIONS_JSON"
}

_get_archive_filename() {
	basename "$(jq .key -r <<<"$__RELEASE_INFO_JSON")"
}

_get_current_release() {
	jq .tag -r <<<"$__RELEASE_INFO_JSON"
}

# @details
# parse release_info_json to get the required nodejs version
# @return required node version for the current rocketchat version
get_required_node_version() {
	funcreturn "$(jq '.nodeVersion // "12.22.9"' -r <<<"$__RELEASE_INFO_JSON")"
}

is_mongodb_version_supported() {
	local version="${1?mongodb version must be non-empty}"
	jq >/dev/null -er '. | index('\""$version"\"')' <<<"$__COMPATIBLE_MONGODB_VERSIONS_JSON"
}

get_supported_mongodb_versions_str() {
	jq -r '. | join(", ")' <<<"$__COMPATIBLE_MONGODB_VERSIONS_JSON"
}

get_latest_supported_mongodb_version() {
	funcreturn "$(jq 'sort_by(.) | reverse | .[0]' -r <<<"$__COMPATIBLE_MONGODB_VERSIONS_JSON")"
}

# @details
# change mongodb configuration
# restart mongodb
# @param replicaset_name
configure_mongodb_for_rocketchat() {
	elevate_privilege
	local \
		replicaset_name \
		mongo_response_json
	replicaset_name="${1:-rs0}"
	DEBUG "replicaset_name: $replicaset_name"
	if [[ "$(yq '.replication.replSetName' /etc/mongod.conf)" == "$replicaset_name" ]]; then
		DEBUG "skipping relicaset config, already set as $replicaset_name"
	else
		yq -i '.replication.replSetName = strenv(replicaset_name)' /etc/mongod.conf ||
			ERROR "failed to edit mognodb config; following steps may fail as well"
	fi
	if [[ "$(systemctl is-active mongod)" != "active" ]]; then
		WARN "mongodb not running, starting now"
		systemctl enable --now mongod &>/dev/null || ERROR "failed to start up mongodb" \
			"this may result in unexpected behaviour in Rocket.Chat startup"
		SUCCESS "mongodb successfully started"
	else
		systemctl restart mongod &>/dev/null || ERROR "failed to restart mongodb" \
			"Rocket.Chat might not successfully start up"
	fi
	if ! is_mongod_ready; then
		FATAL "timed out waiting for mongodb to start up"
		return 1
	fi
	if ! mongo_response_json="$(
		mongo --quiet --eval "JSON.stringify(rs.initiate({_id: '$replicaset_name', members: [{ _id: 0, host: 'localhost:27017' }]}))"
	)"; then
		ERROR "$mongo_response_json"
		FATAL "failed to initiate replicaset; Rocket.Chat won't work without replicaset enabled. exiting ..."
		return 1
	fi
	DEBUG "mongo_response_json: $mongo_response_json"
	if ! (($(jq .ok -r <<<"$mongo_response_json"))); then
		ERROR "$(jq .errmsg -r <<<"$mongo_response_json")"
		FATAL "failed to initiate replicaset; Rocket.Chat won't work without replicaset enabled"
		return 1
	fi
	SUCCESS "mongodb successfully configured"
}

configure_rocketchat() {
	elevate_privilege
	local \
		_opt \
		non_root_user \
		bind_loopback \
		database \
		mongo_url \
		oplog_url \
		port \
		root_url \
		reg_token \
		replicaset_name \
		where \
		node_path
	OPTIND=0
	while getopts "u:bd:p:r:e:s:w:n:" _opt; do
		case "$_opt" in
		u)
			non_root_user="$OPTARG"
			DEBUG "non_root_user: $non_root_user"
			;;
		b)
			bind_loopback=1
			DEBUG "bind_loopback: $bind_loopback"
			;;
		d)
			database="$OPTARG"
			DEBUG "database: $database"
			;;
		p)
			port="$OPTARG"
			DEBUG "port: $port"
			;;
		r)
			root_url="$OPTARG"
			DEBUG "root_url: $root_url"
			;;
		e)
			reg_token="$OPTARG"
			DEBUG "reg_token: $reg_token"
			;;
		s)
			replicaset_name="$OPTARG"
			DEBUG "replicaset_name: $replicaset_name"
			;;
		w)
			where="$OPTARG"
			DEBUG "where: $where"
			;;
		n)
			node_path="$OPTARG"
			DEBUG "node_path: $node_path"
			;;
		*) ERROR "unknown option" ;;
		esac
	done
	INFO "creating rocketchat system user for background service"
	if ! { useradd -M "$non_root_user" && usermod -L "$non_root_user"; }; then
		WARN "failed to create user rocketchat"
		INFO "this isn't a critical error, falling back to root owned process" \
			"although you should take care of it. use 'rocketchatctl doctor' to make an attempt at fixing"
	else
		# FIXME
		chown -R "$non_root_user:$non_root_user" "$where"
	fi
	mongo_url="mongodb://localhost:27017/$database?replicaSet=$replicaset_name"
	oplog_url="mongodb://localhost:27017/local?replicaSet=$replicaset_name"
	cat <<EOF | tee >/dev/null /lib/systemd/system/rocketchat.service
[Unit]
Description=The Rocket.Chat server
After=network.target remote-fs.target nss-lookup.target mongod.service
[Service]
ExecStart=$(path_join "$node_path" node) $(path_join "$where" main.js)
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=rocketchat
User=$(grep -Eq "^$non_root_user" /etc/passwd && printf "%s" "$non_root_user" || printf "root")
Environment=MONGO_URL=$mongo_url
Environment=MONGO_OPLOG_URL=$oplog_url
Environment=ROOT_URL=$root_url
Environment=PORT=$port
Environment=BIND_IP=$( ((bind_loopback)) && printf "127.0.0.1" || printf "0.0.0.0")
Environment=DEPLOY_PLATFORM=$(basename "$0")
Environment=REG_TOKEN=$reg_token
[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload &>/dev/null
	systemctl enable --now rocketchat &>/dev/null
}

# @param
# where to install rocketchat
# @return
# path to the archive file
_download_rocketchat() {
	local where="${1?must pass destination}"
	local release="$(_get_current_release)"
	local archive_file="$(path_join "$where" "$(_get_archive_filename)")"
	[[ -d "$where" ]] || mkdir -p "$where"
	INFO "downloading Rocket.Chat"
	curl -fsSLo "$archive_file" "https://releases.rocket.chat/$release/download" && funcreturn "$archive_file"
}

# @param
# version of rocketchat
# where to install
install_rocketchat() {
	local \
		where \
		archive_file
	where="${1?must pass destination}"
	if ! is_dir_accessible "$where"; then
		elevate_privilege
	fi
	if ! archive_file="$(funcrun _download_rocketchat "$where")"; then
		FATAL "failed to download rocketchat archive"
		return 1
	fi
	INFO "extracting archive"
	if ! tar xzf "$archive_file" --strip-components=1 -C "$where"; then
		FATAL "unable to extract rocketchat archive; exiting ..."
		return 1
	fi
	INFO "installing nodejs modules"
	if (
		cd "$(path_join "$where" programs/server)" &&
			npm i --production
	); then
		SUCCESS "node modules successfully installed"
		return 0
	fi
	ERROR "failed to install all nodejs modules; Rocket.Chat may not work as expected"
	return 1
}
