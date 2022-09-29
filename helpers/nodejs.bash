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
  DEBUG "setting NVM_DIR to /opt/nvm"
  if (sudo mkdir /opt/nvm && sudo chown "$(id -u)":"$(id -g)" /opt/nvm) 2> /dev/null; then
    export NVM_DIR="/opt/nvm"
  else
    WARN "failed to create /opt/nvm; installing nvm in $HOME/.nvm"
    export NVM_DIR="$HOME/.nvm"
  fi
  _debug "NVM_DIR"
  if ! curl -so- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash; then
    FATAL "failed to install nvm; halting installation"
    exit 1
  fi
  SUCCESS "successfully installed nvm"
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
  _nvm() {
    BASH_ENV="$NVM_DIR/nvm.sh" bash -c "nvm $*"
  }
  if ! _nvm install "$node_version"; then
    FATAL "failed to install node $node_version using nvm"
    exit 2
  fi
  funcreturn "$(dirname "$(_nvm which "$node_version")")" || {
    ERROR "failed to capture installed node binary path"
    WARN "falling back on /usr/local/bin/node"
    funcreturn "/usr/local/bin"
  }
}

_n_install_node() {
  local node_version="${1?node version must be passed}"
  if ! n install "$node_version"; then
    FATAL "failed to install $node_version using n"
    exit 1
  fi
  funcreturn "$(dirnane "$(n which "$node_version")")" || {
    ERROR "failed to capture installed node binary path"
    WARN "falling back on /usr/local/bin/node"
    funcreturn "/usr/local/bin"
  }
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
  _debug "archive_file_name"

  local url="https://nodejs.org/dist/$node_version/$archive_file_name.tar.xz"
  _debug "url"

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
  # TODO handle directory creation better
  sudo mkdir /opt/nodejs
  tar -xJf /tmp/"$archive_file_name".tar.xz -C /opt/nodejs || {
    FATAL "failed to extract archive; nodejs install failed"
    FATAL "cannot move on with installation without a valid node binary; exiting..."
    exit 5
  }

  local new_path="/opt/nodejs/$archive_file_name/bin"
  _debug "new_path"

  _append_to_shellrc "$new_path"
  export PATH="$new_path:$PATH"

  funcreturn "${new_path}/bin"
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

        _debug "node_version"
                              ;;
      y)
        install_node=1

        _debug "install_node"
                              ;;
      n)
        n=1

        _debug "n"
                   ;;
      b)
        nvm=1

        _debug "nvm"
                     ;;
      *)
        ERROR "unknown option"
                               ;;
    esac
  done

  node_version="${node_version?nodejs version string required}"

  command_exists "node" && node_exists=1 || node_exists=0
  _debug "node_exists"

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
