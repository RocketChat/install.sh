#!/bin/bash

# TODO: better way of handling errors than ERROR::{exit 1;}


# TODO change this
source "./messages/en.bash"
source "./commands/install/install.bash"

handle_arguments() {
  case "$1" in
    "--help" | "-h") show_long_help; exit 0 ;;
    "install") run_install ;;
    "check-update" | "check-updates") ;;
    "update") ;;
    "upgrade-rocketchatctl") ;;
    "configure") ;;
    "backup") ;;
    *) print_unknown_command_argumen ;;
  esac

}

# TODO add --dry-run option

main() {
  (($(id -u))) && ERROR "you must use a non root account to run this script"

  is_host_supported

  init_host

}
