# This Makefile is for meta/cross_build.sh and meta/make_pkg.sh to build
# releasable packages e.g. in an ARM QEMU chroot.

.PHONY: all install

all:
	gem install bundler --no-document
	bundle install --verbose --deployment

install:
	mkdir -vp /var/lib/knc/
	mkdir -vp /etc/systemd/system/
	mkdir -vp /opt/nitrogenlogic/knc/
	touch /var/lib/knc/.keep
	touch /opt/nitrogenlogic/knc/.keep
	cp -R Gemfile Gemfile.lock embedded/appinfo.txt knc.rb src/ vendor/ .bundle/ embedded/knc_monitor.sh wwwdata/ /opt/nitrogenlogic/knc/
	cp -vR embedded/systemd/* /etc/systemd/system/
