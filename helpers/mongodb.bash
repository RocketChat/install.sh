#!/bin/bash

_source "b-log/b-log.sh"
_source "helpers/lib.bash"

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
  mongo --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1
}

_install_m() {
  [[ -d ~/.local/bin ]] || mkdir ~/.local/bin -p
  curl -Lo ~/.local/bin/m "$M_BIN_URL" --fail || {
    FATAL "failed to install m. you can try using manual install method instead"
    exit 2
  }
  SUCCESS "successfully installed mongodb version manager (m)"
}

_m_install_mongodb() {
  # @returns install path
  local mongodb_version="${1?mongodb version must be passed}"
  m "$mongodb_version" || {
    FATAL "failed to install mongodb version $mongodb_version; exiting ..."
    exit 2
  }
  funcreturn "$HOME/.local/bin"
}

_deb_setup_repo() {
  local key_url="https://www.mongodb.org/static/pgp/server-$MONGO_VERSION.asc"
  local key_file="/usr/share/keyrings/mongodb-org-$MONGO_VERSION.gpg"
  local repo_file="/etc/apt/sources.list.d/mongodb-org-$MONGO_VERSION.list"

  DEBUG "key_url: $key_url"
  DEBUG "key_file: $key_file"
  DEBUG "repo_file: $repo_file"

  delare -A repo=
  repo=([ubuntu]="multiverse" [debian]="main")

  local repo_url="deb [ arch=amd64 signed-by=$key_file ] https://repo.mongodb.org/apt/$DISTRO $DISTRO_CODENAME/mongodb-org/$MONGO_VERSION ${repo[$DISTRO]}"

  DEBUG "repo_url: $repo_url"

  INFO "saving repository data to file"

  curl -fsSL "$key_url" | sudo gpg --dearmor -o "$key_file"

  echo "$repo_url" | sudo tee "$repo_file" > /dev/null
}

_rpm_setup_repo() {
  local yum_mongo_url="https://repo.mongodb.org/yum/redhat/$DISTRO_VERSION/mongodb-org/$MONGO_VERSION/x86_64/"
  local yum_key="https://www.mongodb.org/static/pgp/server-$MONGO_VERSION.asc"
  INFO "saving repository data to file"
  cat << EOF | sudo tee -a "/etc/yum.repos.d/mongodb-org-$MONGO_VERSION.repo"
[mongodb-org-$MONGO_VERSION]
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

  case "$DISTRO" in
    debian | ubuntu)
      _deb_setup_repo
                      ;;
    centos)
      _rpm_setup_repo
                      ;;
  esac

  local mongodb_version="${1?mongodb version must be passed}"
  install_pkg "mongodb-org" || {
    FATAL "failed to install mongodb version $mongodb_version; exiting ..."
    exit 2
  }
  funcreturn "$(dirname "$(which mongod)")"
}

configure_mongodb() {
  # assume yq installed
  local _bin_path="${1?mongodb binary path must be provided}"

  function _mongo {
    "${_bin_path%/}/mongo" "$@"
  }

  local replicaset_name="rs0"
  yq -i e ".replication.replSetName = $replicaset_name" "/etc/mongod.conf" ||
    ERROR "failed to edit mognodb config; following steps may fail as well"
  if [[ $(systemctl is-active mongo) != "active" ]]; then
    WARN "mongodb not running, starting now"
    systemctl enable --now mongo > /dev/null || ERROR "failed to start up mongodb" \
      "this may result in unexpected behaviour in Rocket.Chat startup"
    SUCCESS "mongodb successfully started"
  fi

  local mongo_response_json=
  if ! mongo_response_json="$(
    _mongo --quiet --eval "printjson(rs.initiate({_id: '$replicaset_name', members: [{ _id: 0, host: 'localhost:27017' }]}))"
  )"; then
    FATAL "failed to initiate replicaset; Rocket.Chat won't work without replicaset enabled. exiting ..."
    exit 3
  fi

  if ! (($(jq .ok -r <<< "$mongo_response_json"))); then
    ERROR "$(jq .err -r <<< "$mongo_response_json")"
    FATAL "failed to initiate replicaset; Rocket.Chat won't work without replicaset enabled"
    exit 3
  fi

  export MONGO_URL="mongodb://localhost:27017/rocketchat?replicaSet=$replicaset_name"
  export MONGO_OPLOG_URL="mongodb://localhost:27017/local?replicaSet=$replicaset_name"
  DEBUG "MONGO_URL: $MONGO_URL"
  DEBUG "MONGO_OPLOG_URL: $MONGO_OPLOG_URL"
  SUCCESS "mongodb successfully configured"
}

install_mongodb() {
  # @returns install path
  local \
    OPTARG \
    _opt \
    m \
    mongodb_version \
    _bin_path

  while getopts "mv:" _opt; do
    case "$_opt" in
      m)
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
    _install_m
    mongodb_bin_path="$(funcrun _m_install_mongodb "$mongodb_version")"
  else
    INFO "manually installing mongodb"
    mongodb_bin_path="$(funcrun _manual_install_mongodb "$mongodb_version")"
  fi
  _debug "mongodb_bin_path"

  configure_mongodb "$mongodb_bin_path"
  funcreturn "$mongodb_bin_path"
}
