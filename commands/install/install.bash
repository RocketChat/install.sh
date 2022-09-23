#!/bin/bash

_source "messages/en.bash"
_source "b-log/b-log.sh"
_source "commands/install/node.bash"
_source "commands/install/mongodb.bash"
_source "helpers/rocketchat.bash"
_source "helpers/mongodb.bash"

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

RELEASE_INFO_ENDPOINT=
RELEASE_INFO_JSON=

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

  # shellcheck disable=2155
  verify_release "${RELEASE:-latest}"

  # shellcheck disable=2155
  local node_version_required="$(get_required_node_version)"
  DEBUG "node_version_required: $node_version_required"

  # shellcheck disable=2155
  local node_bin_path="$(install_node "$node_version_required")"
  DEBUG "node_bin_path: $node_bin_path"

  if command_exists "mongod"; then

    INFO "detecting existing mongodb installation"

    mongo --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1 || {
      FATAL "failed to connect to mongodb; required to check configuration" \
        " please make sure installed mongodb server is running before runnning this script"
      exit 2
    }

    local local_mongod_version="$(get_current_mongodb_version)"
    if is_mongodb_version_supported "$local_mongod_version"; then
      if ! ((USE_MONGO)); then
        FATAL "installed mongodb version isn't supported." \
          " supported versions are $(get_supported_mongodb_versions_str)." \
          " use --use-mongo option to ignore this"
        exit 2
      fi
      WARN "your installed version isn't supported; Rocket.Chat may not work as expected"
      WARN "supported versions are $(get_supported_mongodb_versions_str)."
    fi
    is_storage_engine_wiredTiger || WARN "you are currently not using wiredTiger storage engine."
  elif [[ -n "$MONGO_VERSION" ]]; then
    DEBUG "MONGO_VERSION: $MONGO_VERSION"
    # mongo version was passed
    is_mongodb_version_supported "$MONGO_VERSION" ||
      FATAL "mongodb version $MONGO_VERSION is not supported by Rocket.Chat version $RELEASE" \
        "either pass a supported version from ($(get_supported_mongodb_versions_str)) or" \
        "don't mention a mongodb version"
    exit 2
  else
    DEBUG "installing latest mongodb version for Rocket.Chat release $RELEASE"
    MONGO_VERSION="$(get_latest_supported_mongodb_version)"
    DEBUG "MONGO_VERSION: $MONGO_VERSION"
    install_mongodb "$MONGO_VERSION"
  fi

}
