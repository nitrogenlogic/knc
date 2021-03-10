#!/bin/sh
# Script to prepare a Depth Camera Controller for shipping.  This clears knc
# logs and configuration files, and knd zones.  Run after testing is complete,
# before running clean-device.nlfw.
# (C)2012 Mike Bourgeous

# Stop applications
echo "Stopping device-specific applications (switching to runlevel 4)"
/sbin/init 4
sleep 1

echo "Killing KNC and KND"
killall knd_monitor.sh || true
killall /opt/nitrogenlogic/knd/knd || true
killall knc_monitor.sh || true
kill -TERM $(ps -eo pid= -o command= | grep -E "ruby.*(knc|client).rb" | grep -v grep | sed -e "s/^ *//" | cut -d " " -f 1)
sleep 5
killall -KILL knd_monitor.sh 2>/dev/null || true
killall -KILL /opt/nitrogenlogic/knd/knd 2>/dev/null || true
killall -KILL knc_monitor.sh 2>/dev/null || true
(kill -KILL $(ps -eo pid= -o command= | grep -E "ruby.*(knc|client).rb" | grep -v grep | sed -e "s/^ *//" | cut -d " " -f 1)) 2>/dev/null
sleep 1

# Remove KNC files
echo "Deleting KNC log and configuration"
rm -f /var/lib/knc/config.json /var/lib/knc/eventlog.json /var/lib/knc/rules.json

# Remove KND files
echo "Deleting KND zones"
rm -f /var/lib/knd/zones.knd
