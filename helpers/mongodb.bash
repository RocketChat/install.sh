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
  # @returns m path
  local m_dir="$HOME/.local/bin"
  [[ -d "$m_dir" ]] || mkdir "$m_dir"
  grep -Eq "(^$m_dir|[^:]:{1}$m_dir):" <<< "$PATH" || export PATH="$m_dir:$PATH"
  curl -Lo "$m_dir"/m "$M_BIN_URL" --fail || {
    FATAL "failed to install m. you can try using manual install method instead"
    exit 2
  }
  SUCCESS "successfully installed mongodb version manager (m)"
}

_m_install_mongodb() {
  # @returns install path

  local mongodb_version="${1?mongodb version must be passed}"

  _install_m

  m "$mongodb_version" || {
    FATAL "failed to install mongodb version $mongodb_version; exiting ..."
    exit 2
  }

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
                                         ;;
    centos)
      _rpm_setup_repo "$mongodb_version"
                                         ;;
  esac

  install_pkg "mongodb-org" || {
    FATAL "failed to install mongodb version $mongodb_version; exiting ..."
    exit 2
  }
  funcreturn "$(dirname "$(which mongod)")"
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
    _m_install_mongodb "$mongodb_version"
  else
    INFO "manually installing mongodb"
    _manual_install_mongodb "$mongodb_version"
  fi
}
