#!/bin/bash

_source "helpers/lib.bash"

_append_to_shellrc() {
  local new_path="${1?path required}"
  case "$(basename "$SHELL")" in
    fish)
        echo > ~/.config/fish/conf.d/_rocket.chat.nodejs.path.fish \
             "export PATH=$new_path:\$PATH"
      ;;
    bash)
        echo > ~/.bashrc \
             "export PATH=$new_path:\$PATH"
      ;;
    zsh)
        echo > ~/.zshrc \
             "export PATH=$new_path:\$PATH"
      ;;
    *)
      WARN "unknown shell environment detected; update path by $new_path"
      ;;
  esac
}

_install_nvm() {
  # https://github.com/nvm-sh/nvm#installation
  INFO "nstalling nvm"
  if ! curl -so- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash; then
    FATAL "failed to install nvm; halting installation"
    exit 1
  fi
  SUCCESS "successfully installed nvm"
  DEBUG "sourcing nvm.sh"
  # shellcheck disable=SC1091
  source "$HOME/.nvm/nvm.sh"
}

_install_n() {
  if ! command_exists "npm"; then
    FATAL "pre-installed node/npm required for using n"
    exit 1
  fi
  INFO "installing n"
  npm i n -g
}

_nvm_install_node() {
  # @returns node binary path
  local node_version="${1?node version must be passed}"
  # TODO better management
  if ! nvm install "$node_version"; then
    FATAL "failed to install node $node_version using nvm"
    exit 2
  fi
  funcreturn "$(nvm which "$node_version")" || {
    ERROR "failed to capture installed node binary path"
    WARN "defaulting to /usr/local/bin/node"
    funcreturn "/usr/local/bin/node"
  }
}

_n_install_node() {
  local node_version="${1?node version must be passed}"
  if ! n install "$node_version"; then
    FATAL "failed to install $node_version using n"
    exit 1
  fi
  # FIXME check n which
  funcreturn "/usr/local/bin/node"
}

_n() {
  local node_version="${1?node version must be passed}"
  INFO "using n to manage nodejs"
  _install_n
  _n_install_node "$node_version"
}

_nvm() {
  local node_version="${1?node version must be passed}"
  INFO "using nvm to manage nodejs"
  _install_nvm
  _nvm_install_node "$node_version"
}

_manual_install_node() {
  # @returns node binary path
  local node_version="${1?node version must be passed}"
  local archive_file_name="node-$node_version-linux-x64"
  local url="https://nodejs.org/dist/$node_version/$archive_file_name.tar.xz"
  INFO "downloading node $node_version installation archive"
  if ! (
        cd /tmp
                 curl -LO --fail "$url"
  ); then
    FATAL "failed to download nodejs archive"
    FATAL "cannot move on with installation without a valid node binary; exiting..."
    exit 5
  fi
  INFO "installing nodejs in /opt/nodejs"
  sudo mkdir /opt/nodejs
  tar -xJf /tmp/"$archive_file_name".tar.xz -C /opt/nodejs || {
    FATAL "failed to extract archive; nodejs install failed"
    FATAL "cannot move on with installation without a valid node binary; exiting..."
    exit 5
  }

  local new_path="/opt/nodejs/$archive_file_name/bin"
  _append_to_shellrc "$new_path"
  export PATH="$new_path:$PATH"

  funcreturn "${archive_file_name}/bin/node"
}

# change usage of globals
install_node() {
  # @returns node binary path
  local \
    OPTARG \
    _opt \
    node_version \
    node_exists \
    install_node \
    n \
    nvm

  while getopts "v:ynb" _opt; do
    case "$_opt" in
      v)
        node_version="$OPTARG"
                               ;;
      y)
        install_node=1
                       ;;
      n)
        n=1
            ;;
      b)
        nvm=1
              ;;
      *)
        ERROR "unknown option"
                               ;;
    esac
  done

  node_version="${node_version?nodejs version string required}"

  command_exists "node" && node_exists=1 || node_exists=0

  if ! ((install_node)) && ((node_exists)); then
    print_node_version_error_and_exit
  fi

  if ((node_exists)) && node -e "process.exit(process.version === 'v${node_version}' ? 0 : 1)"; then
    SUCCESS "node version satisfied"
    return
  fi

  if ((n)); then
    _n "$node_version"
    return
  fi

  if ((nvm)); then
    _nvm "$node_version"
    return
  fi

  # default
  _manual_install_node "$node_version"
}
