#!/bin/bash
# fleet_logrotate_stagger.sh
# Stagger logrotate and cron.daily jobs across a fleet of Ubuntu 20.04 VMs to prevent synchronized I/O storms.
# Usage: Run as root on each VM (can be distributed via automation tools)

set -e

# Spread jobs over a 3-hour window (0-179 minutes)
RANDOM_MINUTES=$((RANDOM % 180))

# For systemd logrotate.timer (if present)
if systemctl list-timers --all | grep -q logrotate.timer; then
    # Override the timer to a random minute after midnight
    sudo mkdir -p /etc/systemd/system/logrotate.timer.d
    echo -e "[Timer]\nOnCalendar=*-*-* 00:$(printf '%02d' $((RANDOM_MINUTES % 60)))" | \
        sudo tee /etc/systemd/system/logrotate.timer.d/stagger.conf > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl restart logrotate.timer
fi

# For cron.daily (if present)
if [ -f /etc/crontab ]; then
    # Find the cron.daily line and randomize its minute
    sudo sed -i.bak "/cron.daily/ s/^\([0-9]\+\)\s/$(($RANDOM_MINUTES % 60)) /" /etc/crontab
fi

echo "Logrotate and cron.daily jobs staggered by $RANDOM_MINUTES minutes after midnight."
