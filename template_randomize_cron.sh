#!/bin/bash
# template_randomize_cron.sh
# Inject into golden image or cloud-init to randomize log rotation on first boot (Ubuntu 20.04+)
# Usage: Add to VM template or as a cloud-init script

set -e

# Only run on first boot
FLAG_FILE="/var/lib/logrotate_randomized.flag"
if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

# Randomize between 0 and 359 minutes (12:00 AM to 6:00 AM)
RANDOM_MINUTES=$((RANDOM % 360))
HOUR=$((RANDOM_MINUTES / 60))
MINUTE=$((RANDOM_MINUTES % 60))

# For systemd logrotate.timer (if present)
if systemctl list-timers --all | grep -q logrotate.timer; then
    sudo mkdir -p /etc/systemd/system/logrotate.timer.d
    echo -e "[Timer]\nOnCalendar=*-*-* $(printf '%02d' $HOUR):$(printf '%02d' $MINUTE)" | \
        sudo tee /etc/systemd/system/logrotate.timer.d/randomize.conf > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl restart logrotate.timer
fi

# For cron.daily (if present)
if [ -f /etc/crontab ]; then
    sudo sed -i.bak "/cron.daily/ s/^\([0-9]\+\)\s\([0-9]\+\)/$MINUTE $HOUR/" /etc/crontab
fi

touch "$FLAG_FILE"
echo "Logrotate/cron.daily randomized to $HOUR:$MINUTE (first boot only)."
