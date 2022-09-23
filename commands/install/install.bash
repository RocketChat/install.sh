#!/bin/bash

_source "messages/en.bash"
_source "b-log/b-log.sh"
_source "commands/install/node.bash"
_source "commands/install/mongodb.bash"

# All following functions are going to reuse these variables
ROOT_URL=
PORT=
WEBSERVER=
LETSENCRYPT_EMAIL=
RELEASE=
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

        DEBUG "ROOT_URL: $ROOT_URL"
        ;;
      --port)
        PORT="$2"
        shift 2

        DEBUG "PORT: $PORT"
        ;;
      --webserver)
        WEBSERVER="$2"
        shift 2

        DEBUG "WEBSERVER: $WEBSERVER"
        ;;
      --letsencrypt-email)
        LETSENCRYPT_EMAIL="$2"
        shift 2

        DEBUG "LETSENCRYPT_EMAIL: $LETSENCRYPT_EMAIL"
        ;;
      --version)
        RELEASE="$2"
        shift 2

        DEBUG "RELEASE: $RELEASE"
        ;;
      --install-node)
        INSTALL_NODE=1
        shift

        DEBUG "INSTALL_NODE $INSTALL_NODE"
        ;;
      --use-mongo)
        USE_MONGO=1
        shift

        DEBUG "USE_MONGO: $USE_MONGO"
        ;;
      --mongo-version)
        # shellcheck disable=SC2206
        local mongod_version=(${2//./ })
        [[ -n "${mongod_version[2]}" ]] && NOTICE "patch number in mongodb version string will be ignored"
        MONGO_VERSION="${mongod_version[0]}.${mongod_version[1]}"
        shift 2

        DEBUG "MONGO_VERSION: $MONGO_VERSION"
        DEBUG "MONGO_[MAJOR, MINOR, PATCH(IGNORED)]: ${mongod_version[*]}"
        ;;
      --use-m)
        M=1
        shift

        DEBUG "M: $M"
        ;;
      --bind-loopback)
        # TODO: default set this to true if webserver != none
        BIND_LOOPBACK=1
        shift

        DEBUG "BIND_LOOPBACK: $BIND_LOOPBACK"
        ;;
      --reg-token)
        REG_TOKEN="$2"
        shift 2

        DBEUG "REG_TOKEN: ${REG_TOKEN+*****}"
        ;;
      --use-n)
        N=1
        shift

        DEBUG "N: $N"
        ;;
      --use-nvm)
        NVM=1
        shift

        DEBUG "NVM: $NVM"
        ;;
      *)
        print_unknown_command_argument
        ;;
    esac
  done

  # background checks
  local info_endpoint=
  info_endpoint="https://releases.rocket.chat/${RELEASE:=latest}/info"
  DEBUG "info_endpoint: $info_endpoint"
  local release_info_json=
  if ! release_info_json="$(curl --silent "$info_endpoint")"; then
    FATAL "could not gather release information"
    exit 2
  fi
  DEBUG "release_info_json: $release_info_json"
  # TODO make this jq command better
  if [[ "$RELEASE" != "latest" ]] && ! jq > /dev/null '.tag' -er <<< "$release_info_json"; then
    FATAL "specified release $RELEASE not found"
    exit 5
  fi

  # defaults to the old times
  NODE_VERSION_REQUIRED="$(jq -r '.nodeVersion // "12.22.9"' <<< "$release_info_json")"
  DEBUG "NODE_VERSION_REQUIRED: $NODE_VERSION_REQUIRED"

  install_node

  # defaulting mongodb version to 4.2
  local mongodb_supported_versions_json="$(jq -r '.compatibleMongoVersions // ["4.2"]' <<< "$release_info_json")"
  DEBUG "mongodb_supported_versions_json: $mongodb_supported_versions_json"

  if command_exists "mongod"; then

    INFO "detecting existing mongodb installation"

    mongo --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1 || {
      FATAL "failed to connect to mongodb; required to check configuration" \
        " please make sure installed mongodb server is running before runnning this script"
      exit 2
    }

    local local_mongod_version="$(mongo --quiet --eval 'db.version().split(".").splice(0, 2).join(".")')"
    if ! jq > /dev/null '. | index('"$local_mongod_version"')' -e <<< "$mongodb_supported_versions_json"; then
      if ! ((USE_MONGO)); then
        FATAL "installed mongodb version isn't supported." \
          " supported versions are $(jq '. | join(", ")' <<< "$mongodb_supported_versions_json")." \
          " use --use-mongo option to ignore this"
        exit 2
      fi
      WARN "your installed version isn't supported; Rocket.Chat may not work as expected"
      WARN "supported versions are $(jq '. | join(", ")' <<< "$mongodb_supported_versions_json")."
    fi
    local storage_engine="$(mongo --quiet --eval 'db.serverStatus().storageEngine.name')"
    [[ "$storage_engine" == "wiredTiger" ]] ||
      WARN "you are currently using $storage_engine storage engine." \
        "using wiredTiger storage engine is recommended"
  elif [[ -n "$MONGO_VERSION" ]]; then
    DEBUG "MONGO_VERSION: $MONGO_VERSION"
    # mongo version was passed
    jq > /dev/null -e '. | index('"$MONGO_VERSION"')' <<< "$mongodb_supported_versions_json" ||
      FATAL "mongodb version $MONGO_VERSION is not supported by Rocket.Chat version $RELEASE" \
        "either pass a supported version from ($(jq '. | join(", ")' -r <<< "$mongodb_supported_versions_json")) or" \
        "don't mention a mongodb version"
    exit 2
  else
    DEBUG "installing latest mongodb version for Rocket.Chat release $RELEASE"
    MONGO_VERSION="$(jq -r 'sort_by(.) | reverse | .[0]' <<< "$mongodb_supported_versions_json")"
    DEBUG "MONGO_VERSION: $MONGO_VERSION"
    install_mongodb
  fi

}
