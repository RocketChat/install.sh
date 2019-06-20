#!/bin/bash

readonly ROCKETCTL_DOWNLOAD_URL=""
readonly ROCKETCTL_DIRECTOTRY="/usr/local/bin"

[ ${EUID} -ne 0 ] && echo "This script must be run as root. Cancelling" >&2; exit 1;
if [ -z $ROCKETCTL_DIRECTOTRY/rocketctl ]; then
    curl -L $ROCKETCTL_DOWNLOAD_URL -o /tmp/rocketctl
    if  [ $? != 0 ]; then
        echo "Error downloading rocketctl."
        exit 1
    else
        mv /tmp/rocketctl $ROCKETCTL_DIRECTOTRY/
        chmod 755 $ROCKETCTL_DIRECTOTRY/rocketctl
    fi
    $ROCKETCTL_DIRECTOTRY/rocketctl install
else
    echo "RocketChat server already installed, use rocketctl to manage your RocketChat installation"
    exit 1
fi
