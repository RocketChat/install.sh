#!/usr/bin/env bash

source "../b-log/b-log.sh"
source "../errors/errors.bash"
source "./lib.bash"

# functions like an init() {} function
{
  [[ -r /etc/os-release ]] || print_no_release_information_file_found_error

  source /etc/os-release
  declare -g DISTRO="$ID"
  declare -g DISTRO_VERSION="$VERSION_ID"
  declare -g DISTRO_CODENAME="${VERSION_CODENAME:-}"
}

# @private
check_ubuntu() {
  case "$DISTRO_VERSION" in
    18.04 | 18.10 | 19.04 | 19.19 | 20.04 | 20.10 | 21.04 | 21.10 | 22.04) ;;
    *) print_distro_not_supported_error_and_exit $DISTRO_VERSION ;;
  esac
}

# @private
check_debian() {
  case "$DISTRO_VERSION" in
    9 | 10 | 11) ;;
    *) print_distro_not_supported_error_and_exit $DISTRO_VERSION ;;
  esac
}

# @private
check_centos() {
  case "$DISTRO_VERSION" in
    7 | 8) ;;
    *) print_distro_not_supported_error_and_exit $DISTRO_VERSION ;;
  esac
}

# @public
is_host_supported() {
  init_os_details
  declare -A host_check=(
    [ubuntu]=check_ubuntu 
    [centos]=check_centos 
    [debian]=check_debian
  )
  is $DISTRO in host_check || print_distro_not_supported_error_and_exit $DISTRO
  eval "${host_check[$DISTRO]}"
}
