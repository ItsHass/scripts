#!/bin/bash

# --- CONFIG ---
POST_URL="https://xxxxxxxxxxxx/_n8n_files/storj_getContainersData.php"
SUDO_PASS="xxxxxxxxxxx"

# --- FUNCTIONS ---
install_if_missing() {
    for pkg in "$@"; do
        if ! command -v "$pkg" &> /dev/null; then
            echo "$pkg not found. Installing..."
            echo "$SUDO_PASS" | sudo -S apt-get update -qq
            echo "$SUDO_PASS" | sudo -S apt-get install -y "$pkg"
        fi
    done
}

convert_bytes() {
    local bytes=$1
    if awk "BEGIN {exit !($bytes >= 1099511627776)}"; then
        awk "BEGIN {printf \"%.2f TB\", $bytes/1099511627776}"
    elif awk "BEGIN {exit !($bytes >= 1073741824)}"; then
        awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}"
    elif awk "BEGIN {exit !($bytes >= 1048576)}"; then
        awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}"
    else
        echo "$bytes B"
    fi
}

# --- CHECK DEPENDENCIES ---
install_if_missing docker jq curl awk getent

# --- GET LOCAL IP ---
LOCAL_IP=$(hostname -I | awk '{for(i=1;i<=NF;i++) if ($i ~ /^192\./) print $i; exit}')

# --- FIND STORAGENODE CONTAINERS ---
containers=$(docker ps --filter "ancestor=storjlabs/storagenode" --format "{{.Names}}")

for container in $containers; do
    echo "Processing container: $container"

    # Extract ADDRESS
    address=$(docker inspect "$container" | grep -oP '"ADDRESS=\K[^\"]+')
    domain=${address%%:*}
    port=${address##*:}

    # Extract WALLET
    wallet=$(docker inspect "$container" | grep -oP '"WALLET=\K[^\"]+')

    # Resolve external IP
    external_ip=$(getent ahosts "$domain" | awk '{ print $1; exit }')

    # Get HostPort that starts with 14
    host_port=$(docker inspect "$container" | grep -A10 '"Ports": {' | grep '"HostPort": "14' | head -n1 | grep -oP '\d+')

    # Form API URL
    api_url="http://$LOCAL_IP:$host_port"

    # Get node info
    sno_json=$(curl -s "$api_url/api/sno/")
    satellites_json=$(curl -s "$api_url/api/sno/satellites")

    # Extract sno values
    nodeID=$(echo "$sno_json" | jq -r '.nodeID')
    node_wallet=$(echo "$sno_json" | jq -r '.wallet')
    quicStatus=$(echo "$sno_json" | jq -r '.quicStatus')
    lastQuicPingedAt=$(echo "$sno_json" | jq -r '.lastQuicPingedAt')
    lastPinged=$(echo "$sno_json" | jq -r '.lastPinged')
    version=$(echo "$sno_json" | jq -r '.version')

    # Extract and convert storage size
    atRestTotalBytes=$(echo "$satellites_json" | jq -r '.storageDaily[0].atRestTotalBytes')
    avg_hdd_usage=$(convert_bytes "$atRestTotalBytes")

    # POST to PHP
    curl -s -X POST "$POST_URL" \
        -d "storjID=$nodeID" \
        -d "wallet=$node_wallet" \
        -d "local_ipaddress=$LOCAL_IP" \
        -d "external_host=$domain" \
        -d "external_port=$port" \
        -d "external_ipaddress=$external_ip" \
        -d "avg_hdd_usage=$avg_hdd_usage" \
        -d "lastcontact=$lastPinged" \
        -d "quicStatus=$quicStatus" \
        -d "lastQuicPingedAt=$lastQuicPingedAt" \
        -d "lastPinged=$lastPinged" \
        -d "version=$version"

echo "
Completed: $container"
done
