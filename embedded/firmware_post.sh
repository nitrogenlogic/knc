#!/bin/bash
# Post-installation actions for depth controller firmware
# (C)2012-2016 Mike Bourgeous

echo "Installing..."
(for f in `seq 1 45`; do sleep 4; echo .; done) 2>/dev/null &
prog_pid=$!

exec 2>&1


#######################################################################
# Remove files from old locations
rm -f /usr/local/bin/knd


#######################################################################
# Install gems for web UI
cd /opt/nitrogenlogic/gem_repo
gem generate_index > /dev/null || true

cd /opt/nitrogenlogic/knc
gem install --no-doc bundler > /dev/null || true
bundle install > /dev/null || true # TODO: Use bundle --deployment


#######################################################################
# Add startup lines to inittab (pre-systemd)
grep knd_monitor.sh /etc/inittab > /dev/null 2>&1 || echo "3:23:respawn:/bin/openvt -f -w -c 3 -- /opt/nitrogenlogic/knd/knd_monitor.sh" >> /etc/inittab
grep knc_monitor.sh /etc/inittab > /dev/null 2>&1 || echo "4:23:respawn:/bin/openvt -f -w -c 4 -- /opt/nitrogenlogic/knc/knc_monitor.sh" >> /etc/inittab


#######################################################################
# Enable services (systemd)
if [ -x "$(which systemctl)" ]; then
	systemctl enable knd.service > /dev/null || true
	systemctl enable knc.service > /dev/null || true
fi


#######################################################################
# Retune VM system for faster flushing (TODO: Move to base image)
echo "vm.dirty_expire_centisecs = 350" > /etc/sysctl.d/nl_vm.conf
echo "vm.dirty_background_ratio = 5" >> /etc/sysctl.d/nl_vm.conf
/usr/sbin/service procps restart > /dev/null


#######################################################################
# Update library cache
/sbin/ldconfig


#######################################################################
# Make sure ruby is ruby1.9.1, if ruby1.9.1 exists (for old controllers)
if [ -x /usr/bin/ruby1.9.1 ]; then
	rm -f /usr/bin/ruby
	ln -sf /usr/bin/ruby1.9.1 /usr/bin/ruby
fi


#######################################################################
# Make sure everything is written to flash
/bin/sync


#######################################################################
# Make sure all systems are running.
/sbin/telinit q

echo "Restarting the depth controller web interface.  Please wait 15-30 seconds."
pgrphack sh -c '
(
	sleep 2
	kill $prog_pid > /dev/null 2>&1

	service knc restart
	service knd restart
	killall /opt/nitrogenlogic/knd/knd
	killall knd_monitor.sh
	killall knc_monitor.sh

	PIDS=$(ps -eo pid= -o command= | grep -E "ruby.*(knc|client).rb" | grep -v grep | sed -e "s/^ *//" | cut -d " " -f 1)
	kill -TERM $PIDS 2>/dev/null
	sleep 5
	kill -KILL $PIDS 2>/dev/null
) & < /dev/null > /dev/null 2>&1
' < /dev/null > /dev/null 2>&1 &
