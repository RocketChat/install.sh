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
  compatible_mongodb_versions="$(jq '.compatibleMongoVersions // empty' -r <<< "$RELEASE_INFO_JSON")"
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
  local node_required_version=
  node_required_version="$(jq '.nodeVersion // "12.22.9"' -r <<< "$RELEASE_INFO_JSON")"
  funcreturn "$node_required_version"
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
  jq 'sort_by(.) | reverse | .[0]' -r <<< "$COMPATIBLE_MONGODB_VERSIONS_JSON"
}

configure_rocketchat() {
  # @exits on error
  INFO "creating rocketchat system user for background service"
  if ! { sudo useradd -M rocketchat && sudo usermod -L rocketchat; }; then
    WARN "failed to create user rocketchat"
    INFO "this isn't a critical error, falling back to root owned process" \
      "although you should take care of it. use 'rocketchatctl doctor' to make an attempt at fixing"
  else
    # FIXME
    sudo chown -R rocketchat:rocketchat /
  fi
  cat << EOF | sudo > /dev/null tee /lib/systemd/system/rocketchat.service
[Unit]
Description=The Rocket.Chat server
After=network.target remote-fs.target nss-lookup.target mongod.service
[Service]
ExecStart=$NODE_BIN /opt/Rocket.Chat/main.js
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=rocketchat
User=$(grep -Eq ^rocketchat /etc/passwd && printf "rocketchat" || printf "root")
Environment=MONGO_URL=$MONGO_URL
Environment=MONGO_OPLOG_URL=$MONGO_OPLOG_URL
Environment=ROOT_URL=$ROOT_URL
Environment=PORT=$PORT
Environment=BIND_IP=$BIND_IP
Environment=DEPLOY_PLATFORM=rocketchatctl
Environment=REG_TOKEN=$REG_TOKEN
[Install]
WantedBy=multi-user.target
EOF
  EOF
}

insatll_rocketchat() {
  # @description installs passed Rocket.Chat version
  # @exits on ERROR
  local \
    OPTARG \
    _opt \
    release \
    where

  while getopts "v:w:" _opt; do
    case "$_opt" in
      v)
        release="$OPTARG"
                          ;;
      w)
        where="$OPTARG"
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

  $run_cmd mkdir "$where"

  INFO "downloading Rocket.Chat"
  if ! $run_cmd curl -Lo "$archive_file" "https://releases.rocket.chat/$release/download" --retry; then
    FATAL "failed to download rocketchat archive; exiting..."
    exit 5
  fi

  INFO "extracting archive"
  if ! $run_cmd tar xzf "$archive_file" --strip-components=1 -C "$where"; then
    FATAL "unable to extract rocketchat archive; exiting ..."
    exit 6
  fi

  INFO "installing nodejs modules"
  npm i --production ||
    ERROR "failed to install all nodejs modules; Rocket.Chat may not work as expected"
}
