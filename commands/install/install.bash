#!/bin/bash

source "../messages/en.bash"
source "../b-log/b-log.sh"
source "./node.bash"
source "./mongodb.bash"

# All following functions are going to reuse these variables
ROOT_URL=
PORT=
WEBSERVER=
LETSENCRYPT_EMAIL=
VERSION=
INSTALL_MONGO=
USE_MONGO=
MONGO_VERSION=
BIND_LOOPBACK=
REG_TOKEN=
INSTALL_NODE=
N=
NVM=
M=

NODE_VERSION_REQUIRED=
NODE_PATH=

run_install() {
  while [[ -n "$1" ]]; do
    case "$1" in
      --root-url)
        ROOT_URL="$2"
        shift 2
        ;;
      --port)
        PORT="$2"
        shift 2
        ;;
      --webserver)
        WEBSERVER="$2"
        shift 2
        ;;
      --letsencrypt-email)
        LETSENCRYPT_EMAIL="$2"
        shift 2
        ;;
      --version)
        VERSION="$2"
        shift 2
        ;;
      --install-node)
        INSTALL_NODE=1
        shift
        ;;
      --use-mongo)
        USE_MONGO=1
        shift
        ;;
      --use-m)
        M=1
        shift
        ;;
      --mongo-version)
        local mongod_version=(${2/\// })
        [[ -n "${mongod_version[2]}" ]] && NOTICE "patch number in mongodb version string will be ignored"
        MONGO_VERSION="${mongod_version[0]}:${mongod_version[1]}"
        shift 2
        ;;
      --use-m)
        M=1
        shift
        ;;
      --bind-loopback)
        # TODO: default set this to true if webserver != none
        BIND_LOOPBACK=1
        shift
        ;;
      --reg-token)
        REG_TOKEN="$2"
        shift 2
        ;;
      --use-n)
        N=1
        shift
        ;;
      --use-nvm)
        NVM=1
        shift
        ;;
      *)
        print_unknown_command_argument
        ;;
    esac
  done


  # background checks
  local release_info_json="$(curl --silent https://releases.rocket.chat/$VERSION/info)"
  if [[ -n "$VERSION" ]]; then
    printf $release_info_json | jq '.tag // (. | halt_error(1))' -r ||
      ERROR "specified release $VERSION not found"
  else
    VERSION="latest"
  fi


  NODE_VERSION_REQUIRED="$(jq -r .nodeVersion <<< $release_info_json)"

  install_node

  local mongodb_supported_versions_json="$(jq -r .compatibleMongoVersions <<< $release_info_json)"

  if command_exists "mongod"; then

    INFO "detecting existing mongodb installation"

    mongo --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1 ||
      ERROR "failed to connect to mongodb; required to check configuration" \
        " please make sure installed mongodb server is running before runnning this script"

    local local_mongod_version="$(mongo --quiet --eval 'db.version().split(".").splice(0, 2).join(".")')"
    if ! printf $mongodb_supported_versions_json | >/dev/null jq ". | index('$local_mongod_version')" -e; then
      if ! ((USE_MONGO)); then
        ERROR "installed mongodb version isn't supported." \
          " supported versions are $(jq '. | join(\', \') <<< $mongodb_supported_versions_json)." \
          " use --use-mongo option to ignore this"
      fi
      WARN "your installed version isn't supported; Rocket.Chat may not work as expected"
      WARN "supported versions are $(jq '. | join(\', \') <<< $mongodb_supported_versions_json)"
    fi
    local storage_engine="$(mongo --quiet --eval 'db.serverStatus().storageEngine.name')"
    [[ "$storage_engine" == "wiredTiger" ]] ||
      WARN "you are currently using $storage_engine storage engine." \
        "using wiredTiger storage engine is recommended"
  elif [[ -n "$MONGO_VERSION" ]]; then
    # mongo version was passed
    jq -e ". | index('$MONGO_VERSION')" <<< $mongodb_supported_versions_json || 
      ERROR "mongodb version $MONGO_VERSION is not supported by Rocket.Chat version $VERSION" \
        " either pass a supported version from ($(jq '. | join(\', \') <<< $mongodb_supported_versions_json)) or" \
        " don't mention a mongodb version"
  else
    install_mongodb
  fi


}

