#!/usr/bin/env bash

_source "b-log/b-log.sh"
_source "messages/en.bash"
_source "helpers/lib.bash"

{
  [[ -r /etc/os-release ]] || print_no_release_information_file_found_error

  # shellcheck disable=SC1091
  source /etc/os-release
  declare -g DISTRO="$ID"
  declare -g DISTRO_VERSION="$VERSION_ID"
  declare -g DISTRO_CODENAME="${VERSION_CODENAME:-}"
}

# @private
check_ubuntu() {
  case "$DISTRO_VERSION" in
    18.04 | 18.10 | 19.04 | 19.19 | 20.04 | 20.10 | 21.04 | 21.10 | 22.04) ;;
    *) print_distro_not_supported_error_and_exit "$DISTRO_VERSION" ;;
  esac
}

# @private
check_debian() {
  case "$DISTRO_VERSION" in
    9 | 10 | 11) ;;
    *) print_distro_not_supported_error_and_exit "$DISTRO_VERSION" ;;
  esac
}

# @private
check_centos() {
  case "$DISTRO_VERSION" in
    7 | 8) ;;
    *) print_distro_not_supported_error_and_exit "$DISTRO_VERSION" ;;
  esac
}

# @public
is_host_supported() {
  INFO "checking if host is supported or not"
  declare -A host_check=(
        [ubuntu]=check_ubuntu
        [centos]=check_centos
        [debian]=check_debian
  )
  is "$DISTRO" in host_check || print_distro_not_supported_error_and_exit "$DISTRO"
  SUCCESS "detected host ($DISTRO) is supported"
  eval "${host_check[$DISTRO]}"
}

install_pkg() {
  # TODO refactor?
  local cmd=
  case "$DISTRO" in
    debian | ubuntu)
      cmd="apt install -y"
      ;;
    centos)
      local _cmd=
      command_exists "dnf" && _cmd="dnf" || _cmd="yum"
      cmd="$_cmd install -y"
      ;;
  esac
  DEBUG "using install_command \"$cmd\""
  $cmd "$@"
}
