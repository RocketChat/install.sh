#!/bin/bash

_source "b-log/b-log.sh"

M_BIN_URL="https://raw.githubusercontent.com/aheckmann/m/master/bin/m"

get_current_mongodb_storage_engine() {
  mongo --quiet --eval 'db.serverStatus().storageEngine.name'
}

get_current_mongodb_version() {
  mongo --quiet --eval 'db.version.split(".").splice(0, 2).join(".")'
}

is_storage_engine_wiredTiger() {
  [[ "wiredTiger" == "$(get_current_mongodb_storage_engine)" ]]
}

is_mongod_ready() {
  mongo --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1
}

_install_m() {
  curl -Lo ~/.local/bin/m "$M_BIN_URL" --fail || {
    FATAL "failed to install m. you can try using manual install method instead"
    exit 2
  }
}

_m_install_mongodb() {
  m "$MONGO_VERSION" || {
    FATAL "failed to install mongodb version $MONGO_VERSION; exiting ..."
    exit 2
  }
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
  install_pkg "mongodb-org" || {
    FATAL "failed to install mongodb version $MONGO_VERSION; exiting ..."
    exit 2
  }
}

configure_mongodb() {
  # assume yq installed
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
    mongo --quiet --eval "printjson(rs.initiate({_id: '$replicaset_name', members: [{ _id: 0, host: 'localhost:27017' }]}))"
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
  if ((M)); then
    INFO "using m for mongodb"
    _install_m
    _m_install_mongodb
  else
    INFO "manually installing mongodb"
    _manual_install_mongodb
  fi

  configure_mongodb
}
