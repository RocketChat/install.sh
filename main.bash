#!/bin/bash

# TODO: better way of handling errors than ERROR::{exit 1;}

_source() {
  # shellcheck disable=1090
  source "$(dirname "$(realpath "$0")")"/"${1?path is required}"
}

# TODO change this
_source "messages/en.bash"
_source "commands/install.bash"
_source "helpers/host.bash"
_source "helpers/lib.bash"
_source "b-log/b-log.sh"

handle_arguments() {
  case "$1" in
    "--help" | "-h")
         show_long_help
         exit 0
                ;;
    "install")
      is_host_supported
      shift
      run_install "$@"
                       ;;
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
  # TODO change this
  if ! am_i_root; then
    FATAL "you must use a non-root account for this script to work"
    exit 1
  fi

  SUCCESS "using non-root user"

  handle_arguments "$@"
}

# shellcheck disable=2015
[[ -n "$DEBUG" ]] &&
  LOG_LEVEL_DEBUG ||
  LOG_LEVEL_INFO

LOG_LEVELS+=("250" "SUCCESS" "$B_LOG_DEFAULT_TEMPLATE" "\e[1;32m" "\e[0m")

SUCCESS() {
  # don't look at the log
  # i want FUNCNAME to be just right
  B_LOG_print_message 250 "${*?message required}" >&3
}

entrypoint "$@"
