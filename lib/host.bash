#!/bin/bash

[[ -n "${__SOURCE_GUARD_HOST+@@@}" ]] && return
export __SOURCE_GUARD_HOST=

source "$(dirname "$(realpath "$0")")"/lib/lib.bash

{
	[[ -r /etc/os-release ]] || {
		FATAL "no release information file found; cannot move forward"
		exit 1 # abruptly exit
	}
	# shellcheck disable=SC1091
	. /etc/os-release
	declare -xg DISTRO="$ID"
	declare -xg DISTRO_VERSION="$VERSION_ID"
	declare -xg DISTRO_CODENAME="${VERSION_CODENAME:-}"
}

# @private
check_ubuntu() {
	case "$DISTRO_VERSION" in
	18.04 | 18.10 | 19.04 | 19.19 | 20.04 | 20.10 | 21.04 | 21.10 | 22.04) ;;
	*) FATAL "ubuntu version ($DISTRO_VERSION) is not currently supported" && return 1 ;;
	esac
}

# @private
check_debian() {
	case "$DISTRO_VERSION" in
	9 | 10 | 11) ;;
	*) FATAL "debian version ($DISTRO_VERSION) is not currently supported" && return 1 ;;
	esac
}

# @private
check_centos() {
	case "$DISTRO_VERSION" in
	7 | 8) ;;
	*) FATAL "centos version ($DISTRO_VERSION) is not currently supported" && return 1 ;;
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
	# FIXME
	is "$DISTRO" in host_check || print_distro_not_supported_error_and_exit "$DISTRO"
	SUCCESS "detected host ($DISTRO) is supported"
	eval "${host_check[$DISTRO]}"
}

pkm() {
	elevate_privilege
	local cmd=
	case "$DISTRO" in
	debian | ubuntu)
		cmd="apt"
		;;
	centos)
		command_exists "dnf" && cmd="dnf" || cmd="yum"
		;;
	esac
	DEBUG "using install_command \"$cmd $*\""
	"$cmd" "$@"
}
