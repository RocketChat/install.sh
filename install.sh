#!/bin/bash

local -r ROCKETCHATCTL_DOWNLOAD_URL="https://raw.githubusercontent.com/RocketChat/install.sh/master/rocketchatctl"
local -r ROCKETCHATCTL_DIRECTORY="/usr/local/bin"

[ ${EUID} -ne 0 ] && (echo "This script must be run as root. Cancelling" >&2; exit 1;)
if [ ! -f "$ROCKETCHATCTL_DIRECTORY/rocketchatctl" ]; then
    curl -L $ROCKETCHATCTL_DOWNLOAD_URL -o /tmp/rocketchatctl
    if  [ $? != 0 ]; then
        echo "Error downloading rocketchatctl."
        exit 1
    else
        mv /tmp/rocketchatctl $ROCKETCHATCTL_DIRECTORY/
        chmod 755 $ROCKETCHATCTL_DIRECTORY/rocketchatctl
    fi
    $ROCKETCHATCTL_DIRECTORY/rocketchatctl install $@
else
    echo "You already have rocketchatctl installed, use rocketchatctl to manage your RocketChat installation."
    echo "Run rocketchatctl help for more info."
    exit 1
fi
