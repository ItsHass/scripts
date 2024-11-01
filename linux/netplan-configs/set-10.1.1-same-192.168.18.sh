#!/bin/bash

# Path to your Netplan configuration file
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"

# Retrieve the IP and interface name for the 192.168.18.x IP
IP_192_INTERFACE=$(ip -4 addr show | grep -oP '(?<=^| )ens\d+.*inet 192\.168\.18\.\d+' | awk '{print $1}')
IP_192=$(ip -4 addr show dev "$IP_192_INTERFACE" | grep -oP '(?<=inet\s)192\.168\.18\.\d+')
LAST_OCTET=$(echo "$IP_192" | awk -F '.' '{print $4}')

# Retrieve the IP and interface name for the 10.1.1.x IP
IP_10_INTERFACE=$(ip -4 addr show | grep -oP '(?<=^| )ens\d+.*inet 10\.1\.1\.\d+' | awk '{print $1}')
IP_10=$(ip -4 addr show dev "$IP_10_INTERFACE" | grep -oP '(?<=inet\s)10\.1\.1\.\d+')

# Display current setup and proposed change for verification
echo "Detected Interface with IP 192.168.18.x: $IP_192_INTERFACE | IP Address: $IP_192"
echo "Detected Interface with IP 10.1.1.x: $IP_10_INTERFACE | IP Address: $IP_10"
echo "Proposed change: Update $IP_10_INTERFACE IP from $IP_10 to 10.1.1.$LAST_OCTET"

# Get user confirmation
read -p "Do you want to proceed with the changes? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborting script as per user request."
    exit 1
fi

# Function to update the Netplan configuration
update_netplan_ip() {
    echo "Updating Netplan configuration for $IP_10_INTERFACE to use IP 10.1.1.$LAST_OCTET"

    # Use awk to update the 10.1.1.x IP address with the new one, preserving structure
    awk -v new_ip="10.1.1.$LAST_OCTET" '
        BEGIN {updated=0}
        /'"$IP_10_INTERFACE"'/ {
            print;
            next
        }
        /addresses:/ {
            if (!updated && /10\.1\.1\./) {
                sub(/10\.1\.1\.\d+/, new_ip);
                updated=1;
            }
        }
        {print}
    ' "$NETPLAN_FILE" > /tmp/netplan_config.yaml && sudo mv /tmp/netplan_config.yaml "$NETPLAN_FILE"
}

# Update the Netplan configuration
update_netplan_ip

# Apply the Netplan configuration
echo "Applying Netplan configuration..."
sudo netplan apply
echo "Netplan configuration applied successfully."

# Reset the 10.1.1.x interface
echo "Resetting $IP_10_INTERFACE interface..."
sudo ip link set "$IP_10_INTERFACE" down
sudo ip link set "$IP_10_INTERFACE" up

# Display all ens interfaces and their assigned IPv4 addresses
echo "Displaying all ens interfaces and their assigned IPv4 addresses..."
ip -4 addr show | grep -oP '(^|\s)ens\d+.*inet \d+\.\d+\.\d+\.\d+' | awk '{print "Interface:", $1, "| IP Address:", $3}'
