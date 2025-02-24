#!/bin/bash

# Install Netdata if not installed
if ! command -v netdata &>/dev/null; then
    wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh && sh /tmp/netdata-kickstart.sh --stable-channel
fi

# Define the Netdata configuration directory
NETDATA_CONF_DIR="/etc/netdata"
STREAM_CONF="$NETDATA_CONF_DIR/stream.conf"

# Ensure the directory exists
if [ ! -d "$NETDATA_CONF_DIR" ]; then
    echo "[ERROR] Netdata config directory $NETDATA_CONF_DIR not found!"
    exit 1
fi

# Run edit-config from /etc/netdata
(
    cd "$NETDATA_CONF_DIR" || exit 1
    ./edit-config stream.conf <<EOF
exit
EOF
)

# Ensure the stream.conf file exists after running edit-config
if [ ! -f "$STREAM_CONF" ]; then
    echo "[ERROR] $STREAM_CONF not found after running edit-config!"
    exit 1
fi

# Backup the original file before making changes
cp "$STREAM_CONF" "$STREAM_CONF.bak"

# Use awk to update values only within the [stream] section
awk '
BEGIN { in_section = 0; }
{
    if ($0 ~ /^\[stream\]/) { in_section = 1; }
    else if ($0 ~ /^\[/) { in_section = 0; }

    if (in_section == 1) {
        if ($1 == "enabled") $3 = "yes";
        if ($1 == "destination") $3 = "netdata.lan:19999";
        if ($1 == "api" && $2 == "key") $4 = "9e24521d-1c88-4000-a301-82163689e9ad";
    }

    print $0;
}' "$STREAM_CONF.bak" > "$STREAM_CONF"

# Restart Netdata to apply changes
systemctl restart netdata

echo "Netdata stream.conf updated (only within [stream] section) and Netdata restarted successfully!"
