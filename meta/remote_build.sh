#!/bin/bash
# Build KNC's Ruby addons on a remote host

# FIXME: this probably won't work and is probably obsolete.

if [ "$1" = "" ]; then
	echo "Specify compilation host as first parameter."
	exit
fi

if [ ! -z "$2" ]; then
	case "$2" in
		neon)
			EXTRACFLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -ftree-vectorize"
			;;
	esac
fi

LOCAL_HOST=$(hostname).local
REMOTE_HOST=$1
USER=$(id -un)
REMOTE_PATH=src/$(basename `pwd`)
REMOTE_ARCH=$(ssh ${USER}@${REMOTE_HOST} uname -m)

echo Building on/for $REMOTE_ARCH

set -e -x


# Agent forwarding is so the remote host can connect back to this one using ssh
ssh -A ${USER}@${REMOTE_HOST} <<EOF
set -e -x
schedtool -v -N \$\$
renice -n 1 \$\$
export RUBY=ruby
if [ ! -d ~/$REMOTE_PATH/.git ]; then
	mkdir -p ~/$REMOTE_PATH
	cd ~/$REMOTE_PATH/..
	pwd
	echo git clone ssh://${USER}@${LOCAL_HOST}$(pwd)
	git clone ssh://${USER}@${LOCAL_HOST}$(pwd)
fi
cd ~/$REMOTE_PATH
git fetch --all
git reset --hard origin/$(git branch | grep '^\*' | cut -d ' ' -f 2)
gem install bundler
bundle install --deployment
EOF

echo Copying files to $REMOTE_ARCH/

mkdir -p "$REMOTE_ARCH"
scp -r "${USER}@${REMOTE_HOST}:~/$REMOTE_PATH/vendor" "$REMOTE_ARCH"
