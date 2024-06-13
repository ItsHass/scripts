#!/bin/bash

# Function to install WireGuard
install_wireguard() {
    sudo apt update
    sudo apt install -y wireguard
}

# Function to generate a new private and public key
generate_keys() {
    wg genkey | tee privatekey | wg pubkey > publickey
}

# Prompt user for necessary information
read -p "Enter the server's public key: " server_public_key
read -p "Enter the server's endpoint (e.g., your_server_ip:51820): " endpoint
read -p "Enter the allowed IPs (e.g., 0.0.0.0/0, ::/0): " allowed_ips
read -p "Enter the client's private key (or leave blank to generate new one): " client_private_key

# If the client did not provide a private key, generate a new one
if [ -z "$client_private_key" ]; then
    generate_keys
    client_private_key=$(cat privatekey)
    client_public_key=$(cat publickey)
    echo "Generated new private key: $client_private_key"
    echo "Generated new public key: $client_public_key"
else
    client_public_key=$(echo "$client_private_key" | wg pubkey)
fi

# Create WireGuard configuration file
wg_config="/etc/wireguard/wg0.conf"
sudo bash -c "cat > $wg_config <<EOL
[Interface]
PrivateKey = $client_private_key
Address = 10.8.0.1/24

[Peer]
PublicKey = $server_public_key
Endpoint = $endpoint
AllowedIPs = $allowed_ips
PersistentKeepalive = 21
EOL"

# Set correct permissions for the configuration file
sudo chmod 600 $wg_config

# Enable and start the WireGuard interface
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0

echo "WireGuard setup is complete!"
echo "Configuration file is located at $wg_config"
