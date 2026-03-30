#!/bin/bash
# fleet_logrotate_stagger.sh
# Stagger logrotate and cron.daily jobs across a fleet of Ubuntu 20.04 VMs to prevent synchronized I/O storms.
# Usage: Run as root on each VM (can be distributed via automation tools)

set -e

START_TIME="00:00"
END_TIME="03:00"

usage() {
    cat <<'EOF'
Usage:
  fleet_logrotate_stagger.sh [--start HH:MM] [--end HH:MM]

Options:
  --start HH:MM   Start of scheduling window (default: 00:00)
  --end HH:MM     End of scheduling window, exclusive (default: 03:00)
  -h, --help      Show this help

Notes:
  Designed for Ubuntu 20.04 cron/systemd defaults.
EOF
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "ERROR: run as root (use sudo)." >&2
        exit 1
    fi
}

valid_hhmm() {
    [[ "$1" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]
}

to_minutes() {
    local hh mm
    hh="${1%%:*}"
    mm="${1##*:}"
    echo $((10#$hh * 60 + 10#$mm))
}

while [ $# -gt 0 ]; do
    case "$1" in
        --start)
            START_TIME="${2:-}"
            shift 2
            ;;
        --end)
            END_TIME="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

if ! valid_hhmm "$START_TIME" || ! valid_hhmm "$END_TIME"; then
    echo "ERROR: --start/--end must be in HH:MM format (24h)." >&2
    exit 1
fi

require_root

START_MINUTES=$(to_minutes "$START_TIME")
END_MINUTES=$(to_minutes "$END_TIME")

if [ "$END_MINUTES" -le "$START_MINUTES" ]; then
    echo "ERROR: --end must be greater than --start (same-day window)." >&2
    exit 1
fi

WINDOW=$((END_MINUTES - START_MINUTES))
RANDOM_OFFSET=$((RANDOM % WINDOW))
TARGET_MINUTES=$((START_MINUTES + RANDOM_OFFSET))
TARGET_HOUR=$((TARGET_MINUTES / 60))
TARGET_MINUTE=$((TARGET_MINUTES % 60))

# For systemd logrotate.timer (if present)
if systemctl list-timers --all | grep -q logrotate.timer; then
    mkdir -p /etc/systemd/system/logrotate.timer.d
    cat > /etc/systemd/system/logrotate.timer.d/stagger.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* $(printf '%02d' "$TARGET_HOUR"):$(printf '%02d' "$TARGET_MINUTE")
EOF
    systemctl daemon-reload
    systemctl restart logrotate.timer
fi

# For cron.daily (if present)
if [ -f /etc/crontab ]; then
    # Replace hour+minute for cron.daily/anacron launcher entries.
    sed -i.bak "/cron\.daily/ s/^\([0-9]\+\)\s\+\([0-9]\+\)/$TARGET_MINUTE $TARGET_HOUR/" /etc/crontab
fi

echo "Logrotate/cron.daily staggered to $(printf '%02d' "$TARGET_HOUR"):$(printf '%02d' "$TARGET_MINUTE") within ${START_TIME}-${END_TIME}."
