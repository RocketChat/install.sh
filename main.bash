#!/bin/bash

# TODO: better way of handling errors than ERROR::{exit 1;}

_source() {
  source "$(dirname "$(realpath "$0")")"/${1?path is required}
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

exec 3>&1

LOG_LEVEL_ALL

LOG_LEVELS+=("250" "SUCCESS" "$B_LOG_DEFAULT_TEMPLATE" "\e[1;32m" "\e[0m")

# redirect fix
FATAL()    { B_LOG_print_message "${LOG_LEVEL_FATAL}" "$@" >&3; }
ERROR()    { B_LOG_print_message "${LOG_LEVEL_ERROR}" "$@" >&3; }
WARN()     { B_LOG_print_message "${LOG_LEVEL_WARN}" "$@" >&3; }
NOTICE()   { B_LOG_print_message "${LOG_LEVEL_NOTICE}" "$@" >&3; }
INFO()     { B_LOG_print_message "${LOG_LEVEL_INFO}" "$@" >&3; }
DEBUG()    { B_LOG_print_message "${LOG_LEVEL_DEBUG}" "$@" >&3; }
TRACE()    { B_LOG_print_message "${LOG_LEVEL_TRACE}" "$@" >&3; }

SUCCESS() {
  # don't look at the log
  # i want FUNCNAME to be just right
  B_LOG_print_message 250 "${*?message required}" >&3
}

entrypoint "$@"
