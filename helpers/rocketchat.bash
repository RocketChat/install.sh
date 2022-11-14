#!/bin/bash

_source "b-log/b-log.sh"
_source "helpers/lib.bash"

export RELEASE_INFO_JSON=
export COMPATIBLE_MONGODB_VERSIONS_JSON=

verify_release() {
	# @description make sure the version passed is right
	# @params version
	# @exits on error
	local release="${1?release version must be passed}"
	INFO "verifying passed version ($release) if it exists"
	local release_info_endpoint="https://releases.rocket.chat/$release/info"
	DEBUG "release_info_endpoint: $release_info_endpoint"
	if ! RELEASE_INFO_JSON="$(curl -s "$release_info_endpoint")"; then
		FATAL "failed to resolve release information ($release)"
		exit 1
	fi
	DEBUG "RELEASE_INFO_JSON: $RELEASE_INFO_JSON"
	if [[ "$release" != "latest" ]] && ! jq > /dev/null '.tag' -er <<< "$RELEASE_INFO_JSON"; then
		FATAL "specified release $release not found"
		exit 2
	fi
	local compatible_mongodb_versions=
	compatible_mongodb_versions="$(jq '.compatibleMongoVersions // empty' -c <<< "$RELEASE_INFO_JSON")"
	[[ -z "$compatible_mongodb_versions" ]] && WARN "i can't detect the supported mongodb versions for the version you selected." \
		"this means you're trying to install a very old version of Rocket.Chat, which is not recommended." \
		"please install a newer version of, check https://github.com/RocketChat/Rocket.Chat/releases for more information." \
		"for now falling back to mongodb 3.6"
	COMPATIBLE_MONGODB_VERSIONS_JSON="${compatible_mongodb_versions:-["3.6"]}"
	DEBUG "COMPATIBLE_MONGODB_VERSIONS_JSON: $COMPATIBLE_MONGODB_VERSIONS_JSON"
}

get_required_node_version() {
	# @description parse release_info_json to get the required nodejs version
	# @returns required nodejs version for current rocketchat version
	funcreturn "$(jq '.nodeVersion // "12.22.9"' -r <<< "$RELEASE_INFO_JSON")"
}

is_mongodb_version_supported() {
	# @description is passed version part of compatibleMongoVersions?
	# @returns true | false
	local version="${1?mongodb version must be non-empty}"
	jq > /dev/null -er '. | index('\""$version"\"')' <<< "$COMPATIBLE_MONGODB_VERSIONS_JSON"
}

get_supported_mongodb_versions_str() {
	# @nofuncrun
	jq -r '. | join(", ")' <<< "$COMPATIBLE_MONGODB_VERSIONS_JSON"
}

get_latest_supported_mongodb_version() {
	# @nofuncrun
	funcreturn "$(jq 'sort_by(.) | reverse | .[0]' -r <<< "$COMPATIBLE_MONGODB_VERSIONS_JSON")"
}

configure_mongodb_for_rocketchat() {
	local \
		_opt \
		OPTARG \
		replicaset_name \
		mongo_response_json
	while getopts "r:" _opt; do
		case "$_opt" in
			r)
				replicaset_name="$OPTARG"
				_debug "replicaset_name"
				;;
			*) ERROR "unknown option" ;;
		esac
	done
	sudo sed -i "s/^#replication:/replication:\n  replSetName: ${replicaset_name:-rs0}/" /etc/mongod.conf ||
		ERROR "failed to edit mognodb config; following steps may fail as well"
	if [[ $(sudo systemctl is-active mongod) != "active" ]]; then
		WARN "mongodb not running, starting now"
		sudo systemctl enable --now mongod > /dev/null || ERROR "failed to start up mongodb" \
			"this may result in unexpected behaviour in Rocket.Chat startup"
		SUCCESS "mongodb successfully started"
	else
		sudo systemctl restart mongod > /dev/null
	fi
	if ! mongo_response_json="$(
		mongo --quiet --eval "printjson(rs.initiate({_id: '$replicaset_name', members: [{ _id: 0, host: 'localhost:27017' }]}))"
	)"; then
		FATAL "failed to initiate replicaset; Rocket.Chat won't work without replicaset enabled. exiting ..."
		exit 1
	fi
	_debug "mongo_response_json"
	if ! (($(jq .ok -r <<< "$mongo_response_json"))); then
		ERROR "$(jq .err -r <<< "$mongo_response_json")"
		FATAL "failed to initiate replicaset; Rocket.Chat won't work without replicaset enabled"
		exit 1
	fi
	SUCCESS "mongodb successfully configured"
}

configure_rocketchat() {
	# @exits on error
	local \
		_opt \
		OPTARG \
		non_root_user \
		bind_loopback \
		database \
		mongo_url \
		oplog_url \
		port \
		root_url \
		reg_token \
		replicaset_name \
		where
	while getops "u:bd:p:r:e:s:w:" _opt; do
		case "$_opt" in
			u)
				non_root_user="$OPTARG"
				_debug "non_root_user"
				;;
			b)
				bind_loopback=1
				_debug "bind_loopback"
				;;
			d)
				database="$OPTARG"
				_debug "database"
				;;
			p)
				port="$OPTARG"
				_debug "port"
				;;
			r)
				root_url="$OPTARG"
				_debug "root_url"
				;;
			e)
				reg_token="$OPTARG"
				_debug "reg_token"
				;;
			s)
				replicaset_name="$OPTARG"
				_debug "replicaset_name"
				;;
			w)
				where="$OPTARG"
				_debug "where"
				;;
			*) ERROR "unknown option" ;;
		esac
	done
	INFO "creating rocketchat system user for background service"
	if ! { sudo useradd -M "$non_root_user" && sudo usermod -L "$non_root_user"; }; then
		WARN "failed to create user rocketchat"
		INFO "this isn't a critical error, falling back to root owned process" \
			"although you should take care of it. use 'rocketchatctl doctor' to make an attempt at fixing"
	else
		# FIXME
		sudo chown -R "$non_root_user:$non_root_user" "$where"
	fi
	mongo_url="mongodb://localhost:27017/$database?replicaSet=$replicaset_name"
	oplog_url="mongodb://localhost:27017/local?replicaSet=$replicaset_name"
	_debug "mongo_url"
	_debug "oplog_url"
	cat << EOF | sudo > /dev/null tee /lib/systemd/system/rocketchat.service
[Unit]
Description=The Rocket.Chat server
After=network.target remote-fs.target nss-lookup.target mongod.service
[Service]
ExecStart=$(which node) $(path_join "$where" main.js)
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
	EOF
	sudo systemctl daemon-reload
	sudo systemctl enable --now rocketchat > /dev/null || FATAL "failed to start Rocket.Chat"
}

install_rocketchat() {
	# @description installs passed Rocket.Chat version
	# @exits on ERROR
	# expect node in current top path is the one required
	local \
		OPTARG \
		_opt \
		release \
		where
	while getopts "v:w:" _opt; do
		case "$_opt" in
			v)
				release="$OPTARG"
				_debug "release"
				;;
			w)
				where="$OPTARG"
				_debug "where"
				;;
			*) ERROR "unknown argument passed" ;;
		esac
	done
	release="${release?must pass a release version}"
	where="${where?must pass destination}"
	# shellcheck disable=SC2155
	DEBUG "destination: $where"
	local parent_dir="$(dirname "${where}")"
	DEBUG "parent_dir: $parent_dir"
	local run_cmd=
	if is_dir_accessible "$parent_dir"; then
		DEBUG "$parent_dir not accessible"
		DEBUG "falling back to using sudo"
		run_cmd="sudo"
	fi
	local archive_file="$where/rocket.chat.$release.tar.gz"
	$run_cmd mkdir "$where" -p
	INFO "downloading Rocket.Chat"
	if ! $run_cmd curl -fsSLo "$archive_file" "https://releases.rocket.chat/$release/download"; then
		FATAL "failed to download rocketchat archive; exiting..."
		exit 1
	fi
	INFO "extracting archive"
	if ! $run_cmd tar xzf "$archive_file" --strip-components=1 -C "$where"; then
		FATAL "unable to extract rocketchat archive; exiting ..."
		exit 1
	fi
	INFO "installing nodejs modules"
	(
		cd "$(path_join "$where" programs/server)" &&
			npm i --production ||
			ERROR "failed to install all nodejs modules; Rocket.Chat may not work as expected"
	) &&
		SUCCESS "node modules successfully installed"
}
