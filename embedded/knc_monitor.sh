#!/bin/bash
# (C)2012 Mike Bourgeous

stty rows 152 cols 105

mkdir -p /var/lib/knc
chown -R `id -u` /var/lib/knc
chmod -R u+rw /var/lib/knc

# Set path to find do_firmware
export PATH=$PATH:/usr/local/bin

cd /opt/nitrogenlogic/knc
while true; do nice -n 1 /opt/nitrogenlogic/knc/knc.rb; sleep 1; done
