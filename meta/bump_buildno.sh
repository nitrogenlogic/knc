#!/bin/bash
# Increments the build number used for .nlfw firmware images.
# (C)2012 Mike Bourgeous

set -e

function usage()
{
	echo "Usage: $0 arch [message]"
	echo "Example arch: x86_64, armv5tel"
	exit 1
}

[ -z "$1" ] && usage

BUILDNO_FILE=meta/buildno-$1
if [ -f "$BUILDNO_FILE" ]; then 
	BUILDNO=`cat "$BUILDNO_FILE"`
else
	echo "Unknown architecture $1 (create meta/buildno-$1)" 1>&2
	exit
fi
BUILDNO=$(($BUILDNO + 1))
echo -n $BUILDNO > $BUILDNO_FILE
echo -n $BUILDNO

MSG="Increment $1 build number to $BUILDNO"
if [ -n "$2" ]; then
	MSG="$MSG - $2"
fi
git commit --allow-empty -m "$MSG" $BUILDNO_FILE 1>&2
