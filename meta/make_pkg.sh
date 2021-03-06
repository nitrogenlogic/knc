#!/bin/bash
# Script to generate a Debian package for knc.
# Copyright (C)2021 Mike Bourgeous.  Licensed under AGPLv3.

NAME="knc"
PKGNAME="knc"
DESCRIPTION="Kinematic Network Controller (UI for Nitrogen Logic Depth Camera Controllers)"
PKGDEPS="knd, libnlutils"

BASEDIR=$(readlink -m "$(dirname "$0")/..")
VER=$(grep VERSION "${BASEDIR}/src/nl/knc/version.rb" | egrep -o '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
REL=$(($(cat "$BASEDIR/meta/_RELEASE") + 1))
VERSION="$VER-$REL"

build_code()
{
	make
}

INSTALL_CMD="make install"


if [ -r /usr/local/share/nlutils/pkg_helper.sh ]; then
	. /usr/local/share/nlutils/pkg_helper.sh
elif [ -r /usr/share/nlutils/pkg_helper.sh ]; then
	. /usr/share/nlutils/pkg_helper.sh
else
	printf "\033[1;31mCan't find nlutils package helper script\033[0m\n"
	exit 1
fi


# Save bumped release number
printf "\nBuild complete; saving release number\n"
echo -n $REL > "$BASEDIR/meta/_RELEASE"
git commit -m "Build package $VERSION" "$BASEDIR/meta/_RELEASE"

# Remove temporary build output
rm -rf .bundle/ vendor/
