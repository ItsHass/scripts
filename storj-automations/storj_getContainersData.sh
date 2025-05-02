#!/bin/bash

# Function to convert bytes to human-readable format
convert_bytes() {
    local bytes=$1
    if (( bytes >= 1099511627776 )); then
        echo "$(awk "BEGIN {printf \"%.2f TB\", $bytes/1099511627776}")"
    elif (( bytes >= 1073741824 )); then
        echo "$(awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}")"
    elif (( bytes >= 1048576 )); then
        echo "$(awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}")"
    else
        echo "$bytes B"
    fi
}

# Get local IP starting with 192
LOCAL_IP=$(hostname -I | awk '{for(i=1;i<=NF;i++) if ($i ~ /^192\./) print $i; exit}')

# Find all storagenode containers
containers=$(docker ps --filter "ancestor=storjlabs/storagenode" --format "{{.Names}}")

for container in $containers; do
    echo "Processing container: $container"

    # Extract ADDRESS
    address=$(docker inspect "$container" | grep -oP '"ADDRESS=\K[^"]+')
    domain=${address%%:*}
    port=${address##*:}

    # Extract WALLET
    wallet=$(docker inspect "$container" | grep -oP '"WALLET=\K[^"]+')

    # Get external IP by resolving domain
    external_ip=$(getent ahosts "$domain" | awk '{ print $1; exit }')

    # Get host port that starts with 14 (typically 14002)
    host_port=$(docker inspect "$container" | grep -A10 '"Ports": {' | grep '"HostPort": "14' | head -n1 | grep -oP '\d+')

    # Combine local IP and port
    api_url="http://$LOCAL_IP:$host_port"

    # Curl sno API
    sno_json=$(curl -s "$api_url/api/sno/")
    satellites_json=$(curl -s "$api_url/api/sno/satellites")

    # Extract values from sno_json
    nodeID=$(echo "$sno_json" | jq -r '.nodeID')
    node_wallet=$(echo "$sno_json" | jq -r '.wallet')
    quicStatus=$(echo "$sno_json" | jq -r '.quicStatus')
    lastQuicPingedAt=$(echo "$sno_json" | jq -r '.lastQuicPingedAt')
    lastPinged=$(echo "$sno_json" | jq -r '.lastPinged')
    version=$(echo "$sno_json" | jq -r '.version')

    # Extract and convert atRestTotalBytes
    atRestTotalBytes=$(echo "$satellites_json" | jq -r '.storageDaily[0].atRestTotalBytes')
    avg_hdd_usage=$(convert_bytes "$atRestTotalBytes")

    # Post to PHP endpoint
    curl -s -X POST http://your-server.com/storj_update.php \
        --data-urlencode "storjID=$nodeID" \
        --data-urlencode "wallet=$node_wallet" \
        --data-urlencode "local_ipaddress=$LOCAL_IP" \
        --data-urlencode "external_host=$domain" \
        --data-urlencode "external_port=$port" \
        --data-urlencode "external_ipaddress=$external_ip" \
        --data-urlencode "avg_hdd_usage=$avg_hdd_usage" \
        --data-urlencode "lastcontact=$lastPinged"
done
