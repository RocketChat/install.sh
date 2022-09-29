#!/bin/bash

_source "messages/en.bash"
_source "b-log/b-log.sh"
_source "helpers/rocketchat.bash"
_source "helpers/mongodb.bash"
_source "helpers/nodejs.bash"

# All following functions are going to reuse these variables

run_install() {
  local root_url=
  local port=
  local webserver=
  local letsencrypt_email=
  local release=
  local use_mongo=
  local mongo_version=
  local bind_loopback=
  local reg_token=
  local install_node=
  local n=
  local nvm=
  local m=

  local rocketchat_directory=

  local node_version_required=
  local node_path=

  local release_info_endpoint=
  local release_info_json=

  local install_node_arg=
  while [[ -n "$1" ]]; do
    case "$1" in
      --root-url)
        root_url="$2"
        shift 2

        DEBUG "root_url: $root_url"
        ;;
      --port)
        port="$2"
        shift 2

        DEBUG "port: $port"
        ;;
      --webserver)
        webserver="$2"
        shift 2

        DEBUG "webserver: $webserver"
        ;;
      --letsencrypt-email)
        letsencrypt_email="$2"
        shift 2

        DEBUG "letsencrypt_email: $letsencrypt_email"
        ;;
      --version | --release)
        release="$2"
        shift 2

        DEBUG "release: $release"
        ;;
      --install-node)
        install_node=1
        shift

        install_node_arg="-y "

        DEBUG "install_node $install_node"
        ;;
      --use-mongo)
        use_mongo=1
        shift

        DEBUG "use_mongo: $use_mongo"
        ;;
      --mongo-version)
        # shellcheck disable=SC2206
        local mongod_version=(${2//./ })
        [[ -n "${mongod_version[2]}" ]] && NOTICE "patch number in mongodb version string will be ignored"
        mongo_version="${mongod_version[0]}.${mongod_version[1]}"
        shift 2

        DEBUG "mongo_version: $mongo_version"
        DEBUG "MONGO_[MAJOR, MINOR, PATCH(IGNORED)]: ${mongod_version[*]}"
        ;;
      --use-m)
        m=1
        shift

        DEBUG "m: $m"
        ;;
      --bind-loopback)
        # TODO: default set this to true if webserver != none
        bind_loopback=1
        shift

        DEBUG "bind_loopback: $bind_loopback"
        ;;
      --reg-token)
        reg_token="$2"
        shift 2

        DBEUG "reg_token: ${reg_token+*****}"
        ;;
      --use-n)
        n=1
        shift

        install_node_arg+="-n "

        DEBUG "n: $n"
        ;;
      --use-nvm)
        nvm=1
        shift

        install_node_arg+="-b "

        DEBUG "nvm: $nvm"
        ;;
      *)
        print_unknown_command_argument
        ;;
    esac
  done

  # shellcheck disable=2155
  verify_release "${release:-latest}"

  # shellcheck disable=2155
  local node_version_required="$(funcrun get_required_node_version)"
  DEBUG "node_version_required: $node_version_required"

  # shellcheck disable=2155
  local node_bin_path="$(funcrun install_node -v "$node_version_required" "$install_node_arg")"
  DEBUG "node_bin_path: $node_bin_path"

  if command_exists "mongod"; then

    INFO "detecting existing mongodb installation"

    is_mongod_ready || {
      FATAL "failed to connect to mongodb; required to check configuration" \
        "please make sure installed mongodb server is running before runnning this script"
      exit 2
    }

    local local_mongod_version="$(funcrun get_current_mongodb_version)"
    if is_mongodb_version_supported "$local_mongod_version"; then
      if ! ((use_mongo)); then
        FATAL "installed mongodb version isn't supported." \
          " supported versions are $(get_supported_mongodb_versions_str)." \
          " use --use-mongo option to ignore this"
        exit 2
      fi
      WARN "your installed version isn't supported; Rocket.Chat may not work as expected"
      WARN "supported versions are $(funcrun get_supported_mongodb_versions_str)."
    fi
    # TODO decide if this needs to be a FATAL error
    is_storage_engine_wiredTiger || WARN "you are currently not using wiredTiger storage engine."
  elif [[ -n "$mongo_version" ]]; then
    DEBUG "mongo_version: $mongo_version"
    # mongo version was passed
    is_mongodb_version_supported "$mongo_version" ||
      FATAL "mongodb version $mongo_version is not supported by Rocket.Chat version $release" \
        "either pass a supported version from ($(get_supported_mongodb_versions_str)) or" \
        "don't mention a mongodb version"
    exit 2
  else
    DEBUG "installing latest mongodb version for Rocket.Chat release $release"
    mongo_version="$(funcrun get_latest_supported_mongodb_version)"
    DEBUG "mongo_version: $mongo_version"
    install_mongodb "$mongo_version"
  fi

  # we have node and mongodb installed at this point
  install_rocketchat "$release"
}