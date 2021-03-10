#!/bin/bash
# Copy previously-remote_built client to firmware build directory

if [ "$1" = "" ]; then
	echo "Specify target architecture (e.g. nofp) as first parameter."
	exit 1
fi

set -e

ARCH=$1
case $ARCH in
	nofp)
		REMOTE_ARCH=armv5tel
		DEBIAN_ARCH=armel
		;;
	neon)
		REMOTE_ARCH=armv7l
		DEBIAN_ARCH=armel
		;;
	*)
		echo "Unsupported architecture '$ARCH'"
		exit 1
		;;
esac

FWNAME=depth

CROSS_BASE=$HOME/devel/crosscompile
CROSS_DIR=$CROSS_BASE/cross-root-arm-$ARCH-$RELEASE-$FWNAME/
PREFIX=$CROSS_DIR/opt/nitrogenlogic/knc/

echo "Copying files for $REMOTE_ARCH"
rm -rf "${PREFIX}"
mkdir -vp "$CROSS_DIR/var/lib/knc/"
mkdir -vp "$CROSS_DIR/etc/systemd/system/"
cp -vR Gemfile Gemfile.lock embedded/appinfo.txt knc.rb src/ vendor/ .bundle/ \
	embedded/knc_monitor.sh wwwdata/ "${PREFIX}"
cp -vR embedded/systemd/* "${CROSS_DIR}/etc/systemd/system/"
