#!/bin/bash

source "./b-log/b-log.sh"

M_BIN_URL="https://raw.githubusercontent.com/aheckmann/m/master/bin/m"

_install_m() {
  curl -Lo ~/.local/bin/m $M_BIN_URL --fail || ERROR "failed to install m. you can try using manual install method instead"
}

_m_install_mongodb() {
  m $MONGO_VERSION
}

_deb_setup_repo() {
  local key_url="https://www.mongodb.org/static/pgp/server-$MONGO_VERSION.asc"
  local key_file="/usr/share/keyrings/mongodb-org-$MONGO_VERSION.gpg"
  local repo_file="/etc/apt/sources.list.d/mongodb-org-$MONGO_VERSION.list"

  DEBUG "key_url: $key_url"
  DEBUG "key_file: $key_file"
  DEBUG "repo_file: $repo_file"

  declare -A repo=([ubuntu]=multiverse [debian]=main)

  local repo_url="deb [ arch=amd64 signed-by=$key_file ] https://repo.mongodb.org/apt/$DISTRO $DISTRO_CODENAME/mongodb-org/$MONGO_VERSION ${repo[$DISTRO]}"

  DEBUG "repo_url: $repo_url"

  INFO "saving repository date to file"

  curl -fsSL "$key_url" | sudo gpg --dearmor -o "$key_file"

  printf $repo_url > $repo_file
}

_rpm_setup_repo() {
  local yum_mongo_url="https://repo.mongodb.org/yum/redhat/$DISTRO_VERSION/mongodb-org/$MONGO_VERSION/x86_64/"
  local yum_key="https://www.mongodb.org/static/pgp/server-$MONGO_VERSION.asc"
  INFO "saving repository data to file"
  cat << EOF | sudo tee -a /etc/yum.repos.d/mongodb-org-$MONGO_VERSION.repo
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
  install_pkg "mongodb-org"
}

install_mongodb() {
  if ((M)); then
    INFO "using m for mongodb"
    _install_m
    _m_install_mongodb
    return
  fi

  INFO "manually installing mongodb" 
  _manual_install_mongodb
}

