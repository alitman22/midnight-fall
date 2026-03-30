#!/bin/bash
# template_randomize_cron.sh
# Inject into golden image or cloud-init to randomize log rotation on first boot (Ubuntu 20.04+)
# Usage: Add to VM template or as a cloud-init script

set -e

FLAG_FILE="/var/lib/logrotate_randomized.flag"
START_TIME="00:00"
END_TIME="06:00"
CRON_FILE="/etc/crontab"
INSTALL_FIRST_BOOT_UNIT=false

usage() {
    cat <<'EOF'
Usage:
  template_randomize_cron.sh [options] [cron_file]

Options:
  --start HH:MM                 Start of randomization window (default: 00:00)
  --end HH:MM                   End of randomization window, exclusive (default: 06:00)
  --cron-file PATH              Cron file to edit (default: /etc/crontab)
  --install-first-boot-unit     Install/enable a one-shot first-boot systemd service
  --flag-file PATH              Override one-time flag file path
  -h, --help                    Show this help

Notes:
  Designed for Ubuntu 20.04 templates using systemd timers and/or cron.
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

install_first_boot_unit() {
    local script_path unit_path
    script_path="$(readlink -f "$0")"
    unit_path="/etc/systemd/system/logrotate-randomize-firstboot.service"

    cat > "$unit_path" <<EOF
[Unit]
Description=Randomize logrotate schedule on first boot
After=network-online.target
ConditionPathExists=!$FLAG_FILE

[Service]
Type=oneshot
ExecStart=$script_path --start $START_TIME --end $END_TIME --cron-file $CRON_FILE --flag-file $FLAG_FILE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable logrotate-randomize-firstboot.service
    echo "Installed and enabled first-boot unit: logrotate-randomize-firstboot.service"
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
        --cron-file)
            CRON_FILE="${2:-}"
            shift 2
            ;;
        --install-first-boot-unit)
            INSTALL_FIRST_BOOT_UNIT=true
            shift
            ;;
        --flag-file)
            FLAG_FILE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "ERROR: unknown argument '$1'" >&2
            usage
            exit 1
            ;;
        *)
            # Backward-compatible positional cron file.
            CRON_FILE="$1"
            shift
            ;;
    esac
done

if ! valid_hhmm "$START_TIME" || ! valid_hhmm "$END_TIME"; then
    echo "ERROR: --start/--end must be in HH:MM format (24h)." >&2
    exit 1
fi

require_root

if [ "$INSTALL_FIRST_BOOT_UNIT" = true ]; then
    install_first_boot_unit
    exit 0
fi

# Only run once on a given VM instance.
if [ -f "$FLAG_FILE" ]; then
    echo "Already randomized on this VM; nothing to do."
    exit 0
fi

START_MINUTES=$(to_minutes "$START_TIME")
END_MINUTES=$(to_minutes "$END_TIME")

if [ "$END_MINUTES" -le "$START_MINUTES" ]; then
    echo "ERROR: --end must be greater than --start (same-day window)." >&2
    exit 1
fi

WINDOW=$((END_MINUTES - START_MINUTES))
RANDOM_OFFSET=$((RANDOM % WINDOW))
TARGET_MINUTES=$((START_MINUTES + RANDOM_OFFSET))
HOUR=$((TARGET_MINUTES / 60))
MINUTE=$((TARGET_MINUTES % 60))

# For systemd logrotate.timer (if present)
if systemctl list-timers --all | grep -q logrotate.timer; then
    mkdir -p /etc/systemd/system/logrotate.timer.d
    cat > /etc/systemd/system/logrotate.timer.d/randomize.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* $(printf '%02d' "$HOUR"):$(printf '%02d' "$MINUTE")
EOF
    systemctl daemon-reload
    systemctl restart logrotate.timer
fi

# For cron.daily (if present)
if [ -f "$CRON_FILE" ]; then
    sed -i.bak "/cron\.daily/ s/^\([0-9]\+\)\s\+\([0-9]\+\)/$MINUTE $HOUR/" "$CRON_FILE"
fi

mkdir -p "$(dirname "$FLAG_FILE")"
touch "$FLAG_FILE"
echo "Logrotate/cron.daily randomized to $(printf '%02d' "$HOUR"):$(printf '%02d' "$MINUTE") (first boot only)."
