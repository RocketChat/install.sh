_append_to_shellrc() {
  local new_path="${1?path required}"
  case "$(basename $SHELL)" in
    fish)
      > ~/.config/fish/conf.d/_rocket.chat.nodejs.path.fish \
        echo "export PATH=$new_path:\$PATH"
      ;;
    bash)
      > ~/.bashrc \
        echo "export PATH=$new_path:\$PATH"
      ;;
    zsh)
      > ~/.zshrc \
        echo "export PATH=$new_path:\$PATH"
      ;; 
    *)
      WARN "unknown shell environment detected; update path by $new_path"
      ;;
  esac
}

_install_nvm() {
  # https://github.com/nvm-sh/nvm#installation
  INFO "installing nvm"
  >/dev/null curl -so- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash ||
    ERROR "failed to install nvm; halting installation"
  SUCCESS "successfully installed nvm"
}

_install_n() {
  command_exists "npm" || ERROR "pre-installed node/npm required for using n"
  INFO "installing n"
  npm i n -g
}

_nvm_install_node() {
  nvm install "$NODE_VERSION_REQUIRED" || ERROR "failed to install node $NODE_VERSION_REQUIRED using nvm"
  NODE_PATH="$(nvm which $NODE_VERSION_REQUIRED)" || ERROR "failed to capture installed node binary path"
}

_n_install_node() {
  n install "$NODE_VERSION_REQUIRED" || ERROR "failed to install $NODE_VERSION_REQUIRED using n"
  NODE_PATH="$(nvm which $NODE_VERSION_REQUIRED)" || ERROR "failed to capture installed node binary path"
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
  (cd /tmp; curl -LO --fail $url) || ERROR "failed to download nodejs archive"
  INFO "installing nodejs in /opt/nodejs"
  sudo mkdir /opt/nodejs
  tar -xJvf /tmp/$archive_file_name.tar.xz -C /opt/nodejs ||
    ERROR "failed to extract archive; nodejs install failed"

  local new_path="/opt/nodejs/$archive_file_name/bin"
  _append_to_shellrc $new_path
  export PATH="$new_path:$PATH"


  NODE_PATH="${archive_file_name}/bin/node"
}

install_node() {
  local node_exists
  command_exists "node" && node_exists=1 || node_exists=0

  if ! ((INSTALL_NODE)) && ((node_exists)); then
    print_node_version_error_and_exit
  fi
  
  if ((node_exists)) && node -pe "process.exit(process.version === '${NODE_VERSION_REQUIRED}' ? 0 : 1)"; then
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

