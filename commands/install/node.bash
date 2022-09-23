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
  INFO "installing nvm"
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
  # TODO better management
  if ! nvm install "$NODE_VERSION_REQUIRED"; then
    FATAL "failed to install node $NODE_VERSION_REQUIRED using nvm"
    exit 2
  fi
  funcreturn "$(nvm which "$NODE_VERSION_REQUIRED")" || ERROR "failed to capture installed node binary path"
}

_n_install_node() {
  if ! n install "$NODE_VERSION_REQUIRED"; then 
    FATAL "failed to install $NODE_VERSION_REQUIRED using n"
    exit 1
  fi
  funcreturn "$(nvm which "$NODE_VERSION_REQUIRED")" || ERROR "failed to capture installed node binary path"
}

_n() {
  INFO "using n to manage nodejs"
  _install_n
  _n_install_node
}

_nvm() {
  INFO "using nvm to manage nodejs"
  _install_nvm
  _nvm_install_node
}

_manual_install_node() {
  local archive_file_name="node-$NODE_VERSION_REQUIRED-linux-x64"
  local url="https://nodejs.org/dist/$NODE_VERSION_REQUIRED/$archive_file_name.tar.xz"
  INFO "downloading node $NODE_VERSION_REQUIRED installation archive"
  if ! (cd /tmp; curl -LO --fail "$url"); then
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

install_node() {
  local node_verison="${1?nodejs version string required}"

  local node_exists
  command_exists "node" && node_exists=1 || node_exists=0

  if ! ((INSTALL_NODE)) && ((node_exists)); then
    print_node_version_error_and_exit
  fi

  if ((node_exists)) && node -e "process.exit(process.version === 'v${node_verison}' ? 0 : 1)"; then
    SUCCESS "node version satisfied"
    return
  fi

  if ((N)); then
    _n
    return
  fi

  if ((NVM)); then
    _nvm
    return
  fi

  # default
  _manual_install_node
}
