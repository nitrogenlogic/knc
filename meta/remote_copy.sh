#!/bin/bash
# Copy previously-remote_built client to given host name
# TODO: Remove in favor of copying firmware image directly

# FIXME: This will most likely not work on anything but a classic controller
# running impossible-to-update-or-replicate Debian Stretch, and probably won't
# work with the recent code reorganization.

if [ "$1" = "" ]; then
	echo "Specify installation host as first parameter."
	exit
fi

set -e

REMOTE_HOST=$1
REMOTE_USER=root
REMOTE_PATH=/opt/nitrogenlogic/knc/

FILES="embedded/appinfo.txt knc.rb src/ vendor/ embedded/knc_monitor.sh \
	wwwdata Gemfile Gemfile.lock"
ARCH_FILES="kinutils"

echo "Copying to $REMOTE_HOST.  Getting remote arch."
REMOTE_ARCH=$(ssh ${REMOTE_USER}@${REMOTE_HOST} uname -m)
echo "Remote arch is ${REMOTE_ARCH}."

echo "Creating remote directory."
ssh ${REMOTE_USER}@${REMOTE_HOST} mkdir -p $REMOTE_PATH/kinutils

echo "Copying files."
tar -zc $FILES | ssh ${REMOTE_USER}@${REMOTE_HOST} tar -zxvC ${REMOTE_PATH}

echo "Copying extension files."
tar -C $REMOTE_ARCH -zc ${ARCH_FILES} | ssh ${REMOTE_USER}@${REMOTE_HOST} tar -zxvC ${REMOTE_PATH}

echo "Restarting knc."
ssh ${REMOTE_USER}@${REMOTE_HOST} 'kill -TERM $(ps -eo pid= -o command= | grep -E "(ruby.*(knc|client).rb|bash.*knc_monitor.sh)" | grep -v grep | sed -e "s/^ *//" | cut -d " " -f 1) 2>/dev/null'
