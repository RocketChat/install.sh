#!/bin/bash

# TODO: better way of handling errors than ERROR::{exit 1;}

_source() {
  source "$(dirname "$(realpath "$0")")"/"${1?path is required}"
}

# TODO change this
_source "messages/en.bash"
_source "commands/install/install.bash"
_source "helpers/host.bash"
_source "helpers/lib.bash"
_source "b-log/b-log.sh"

handle_arguments() {
  case "$1" in
    "--help" | "-h")
         show_long_help
         exit 0
                ;;
    "install") run_install ;;
    "check-update" | "check-updates") ;;
    "update") ;;
    "upgrade-rocketchatctl") ;;
    "configure") ;;
    "backup") ;;
    *) print_unknown_command_argument ;;
  esac

}

# TODO add --dry-run option

entrypoint() {
  if ! am_i_root; then
    FATAL "you must use a non-root account for this script to work"
    exit 1
  fi

  SUCCESS "using non-root user"

  is_host_supported

  run_install "$@"

}

LOG_LEVEL_ALL

entrypoint "$@"
