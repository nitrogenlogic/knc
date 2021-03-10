#!/bin/bash
# Call after running remote_build.sh.
# (C)2012 Mike Bourgeous

# FIXME: This will not work, but is left here so it can be fixed later.
# SystemD, TLS1.2+, and other changes to the web and to Debian have broken much
# of this build and firmware process.  Perhaps the firmware process should be
# abandoned entirely in favor of Debian packages, since no future controllers
# are likely to be built or sold.

if [ "$1" = "" ]; then
	echo "Specify target architecture (e.g. nofp) as first parameter."
	exit
fi

if [ "$UID" -ne 0 ]; then
	echo "Use fakeroot to run this script."
	exit 2
fi

set -e

ARCH=$1
FWNAME=depth

case $ARCH in
	nofp)
		REMOTE_ARCH=armv5tel
		;;
	neon)
		REMOTE_ARCH=armv7l
		;;
	*)
		echo "Unsupported architecture '$ARCH'"
		exit 1
		;;
esac

meta/local_copy.sh $ARCH

CROSS_BASE=$HOME/devel/crosscompile
CROSS_ROOT=$CROSS_BASE/cross-root-arm-$ARCH-$FWNAME

echo "Building firmware for $REMOTE_ARCH (use remote_build.sh first)"

BRANCH=`(git branch | grep '^\*' | cut -d ' ' -f 2) || echo -n 'master'`
if [ $BRANCH = "master" ]; then
	BRANCH=""
	MSG=""
else
	echo "On branch $BRANCH"
	MSG="for branch $BRANCH"
	BRANCH="$BRANCH-"
fi

BUILDNO=$(meta/bump_buildno.sh $REMOTE_ARCH "$MSG")
echo "New build number is ${BRANCH}$BUILDNO"

FILENAME=$FWNAME-$BRANCH$ARCH-$BUILDNO

mkdir -p $CROSS_ROOT/etc/knc
echo -n ${BRANCH}$BUILDNO > $CROSS_ROOT/etc/knc/build

chown -R root:root $CROSS_ROOT

# mk_sfx.sh and mk_firmware.sh are from nlutils
cd $CROSS_ROOT
mk_sfx.sh ../$FILENAME.palfw .
cat $OLDPWD/embedded/firmware_post.sh >> ../$FILENAME.palfw
mk_firmware.sh ../$FILENAME.palfw ../$FILENAME.nlfw $REMOTE_ARCH $FWNAME
cd -
printf "Built \033[1m$FILENAME.nlfw\033[0m\n"

mk_firmware.sh embedded/clean-depth.sh "${CROSS_BASE}/clean-depth.nlfw"
printf "Built \033[1m${CROSS_BASE}/clean-depth.nlfw\033[0m\n"

mk_firmware.sh embedded/depth-diagnostics.sh "${CROSS_BASE}/depth-diagnostics.nlfw"
printf "Built \033[1m${CROSS_BASE}/depth-diagnostics.nlfw\033[0m\n"
