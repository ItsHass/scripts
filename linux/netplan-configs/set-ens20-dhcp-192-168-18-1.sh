#!/bin/bash

# Path to your Netplan configuration file
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"

# Define the ens20 configuration with the exact required indentation
ENS20_CONFIG="
    ens20:
      dhcp4: true
      nameservers:
        addresses: [192.168.18.1]
"

# Function to check if ens20 configuration exists
check_ens20_in_netplan() {
    grep -q "ens20:" "$NETPLAN_FILE"
}

# Function to insert ens20 configuration with correct indentation
add_ens20_to_netplan() {
    echo "Adding ens20 configuration to Netplan..."

    # Insert ens20 configuration under ethernets section with precise indentation
    awk -v config="$ENS20_CONFIG" '
        BEGIN {added=0}
        /^(\s*)ethernets:/ {
            print;
            if (!added) {
                print config;
                added=1;
            }
            next
        }
        {print}
    ' "$NETPLAN_FILE" > /tmp/netplan_config.yaml && sudo mv /tmp/netplan_config.yaml "$NETPLAN_FILE"
}

# Main script logic
echo "Checking Netplan configuration for ens20..."

if check_ens20_in_netplan; then
    echo "Interface ens20 is already configured in Netplan. Skipping configuration."
else
    add_ens20_to_netplan
    echo "Applying Netplan configuration..."
    sudo netplan apply
    echo "Netplan configuration applied successfully."
fi

# Reset the ens20 interface
echo "Resetting ens20 interface..."
sudo ip link set ens20 down
sudo ip link set ens20 up

# Wait a few seconds to ensure DHCP assignment is completed
sleep 5

# Check and display IP and MAC address of ens20
echo "Checking IP and MAC address for ens20..."
if ip a show ens20 | grep -q "inet "; then
    IP_ADDRESS=$(ip -4 addr show ens20 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    MAC_ADDRESS=$(ip link show ens20 | awk '/ether/ {print $2}')
    echo "ens20 is now active."
    echo "Assigned IP Address: $IP_ADDRESS"
    echo "MAC Address: $MAC_ADDRESS"
else
    echo "Failed to obtain IP address. Please check the connection or DHCP server."
fi
