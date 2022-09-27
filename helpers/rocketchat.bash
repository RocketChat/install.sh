#!/bin/bash

_source "b-log/b-log.sh"
_source "helpers/lib.bash"

export RELEASE_INFO_JSON=
export COMPATIBLE_MONGODB_VERSIONS_JSON=

verify_release() {
  # @description make sure the version passed is right
  # @params version
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
  # @params
  local node_required_version=
  node_required_version="$(jq '.nodeVersion // "12.22.9"' -r <<< "$RELEASE_INFO_JSON")"
  funcreturn "$node_required_version"
}

is_mongodb_version_supported() {
  # @description is passed version part of compatibleMongoVersions?
  local version="${1?mongodb version must be non-empty}"
  jq > /dev/null -er '. | index('"$version"')'
}

get_supported_mongodb_versions_str() {
  jq -r '. | join(", ")' <<< "$COMPATIBLE_MONGODB_VERSIONS_JSON"
}

get_latest_supported_mongodb_version() {
  jq 'sort_by(.) | reverse | .[0]' -r <<< "$COMPATIBLE_MONGODB_VERSIONS_JSON"
}

configure_rocketchat() {
  echo
}

insatll_rocketchat() {
  local release="${1?must pass a release version}"
  local where="${2?must pass destination}"
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
  if ! $run_cmd curl -Lo "$archive_file" "https://releases.rocket.chat/$release/download" --retry ; then
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
    ERROR "failed to install all nodejs modules; exiting..."

}
