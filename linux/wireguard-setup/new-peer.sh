#!/bin/bash
clear

# Set variables
WG_N="wg0"
WG_CONF="/etc/wireguard/$WG_N.conf"
SERVER_PUBLIC_KEY=$(wg show $WG_N public-key)
SERVER_ENDPOINT="xx:51820"
WG_NETWORK="10.0.0.0/24"
PEER_IP=""
PEER_IP_32=""
PEER_NAME=""

# Step 1: Generate keys for the new peer
generate_keys() {
    echo "Generating keys for the new peer..."
    PEER_PRIVATE_KEY=$(wg genkey)
    PEER_PUBLIC_KEY=$(echo "$PEER_PRIVATE_KEY" | wg pubkey)
    echo "Private Key: $PEER_PRIVATE_KEY"
    echo "Public Key: $PEER_PUBLIC_KEY"
}

# Step 2: Find an available IP for the new peer
find_available_ip() {
    echo "Finding an available IP for the new peer..."
    USED_IPS=$(grep AllowedIPs $WG_CONF | awk '{print $3}' | cut -d'/' -f1)
    BASE_IP=$(echo $WG_NETWORK | cut -d'.' -f1-3)
    for i in {2..254}; do
        IP="$BASE_IP.$i"
        if ! echo "$USED_IPS" | grep -q "$IP"; then
            PEER_IP="$IP/24"
            PEER_IP_32="$IP/32"
            echo "Assigned IP: $PEER_IP"
            break
        fi
    done

    if [ -z "$PEER_IP" ]; then
        echo "No available IPs found in the range $WG_NETWORK."
        exit 1
    fi
}

# Step 3: Add the peer to the server configuration
add_peer_to_server() {
    echo "Adding the new peer to the server configuration..."
    echo "" >> $WG_CONF
    echo "[Peer]" >> $WG_CONF
    echo "PublicKey = $PEER_PUBLIC_KEY" >> $WG_CONF
    echo "AllowedIPs = $PEER_IP_32" >> $WG_CONF

    # Apply changes to the WireGuard interface
    wg set $WG_N peer "$PEER_PUBLIC_KEY" allowed-ips "$PEER_IP_32"
}

# Step 4: Create the peer configuration file
create_peer_config() {
    echo "Creating the configuration file for the new peer..."
    read -p "Enter a name for this peer (e.g., laptop, phone): " PEER_NAME
    PEER_CONF="$PEER_NAME-$WG_N.conf"

    cat <<EOF > $PEER_CONF
[Interface]
PrivateKey = $PEER_PRIVATE_KEY
Address = $PEER_IP
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 20
EOF

    echo "Peer configuration created: $PEER_CONF"
}

# Main script
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

echo "=== WireGuard Add Peer Script ==="

generate_keys
find_available_ip
add_peer_to_server
create_peer_config

echo "Peer setup complete. Share the $PEER_CONF file with the peer device."
