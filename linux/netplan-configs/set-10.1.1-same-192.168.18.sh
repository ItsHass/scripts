#!/bin/bash

# Path to your Netplan configuration file
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"

# Retrieve the interface and IP for 192.168.18.x
IP_192_INFO=$(ip -4 addr show | grep "192.168.18")
IP_192_INTERFACE=$(echo "$IP_192_INFO" | awk '{print $NF}')
IP_192=$(echo "$IP_192_INFO" | grep -oP '(?<=inet\s)192\.168\.18\.\d+')
LAST_OCTET=$(echo "$IP_192" | awk -F '.' '{print $4}')

# Retrieve the interface and IP for 10.1.1.x
IP_10_INFO=$(ip -4 addr show | grep "10.1.1")
IP_10_INTERFACE=$(echo "$IP_10_INFO" | awk '{print $NF}')
IP_10=$(echo "$IP_10_INFO" | grep -oP '(?<=inet\s)10\.1\.1\.\d+')

# Check if both interfaces were found
if [ -z "$IP_192_INTERFACE" ] || [ -z "$IP_10_INTERFACE" ]; then
    echo "Error: Could not find interfaces with IP ranges 192.168.18.x or 10.1.1.x."
    echo "IP_192_INTERFACE: '$IP_192_INTERFACE'"
    echo "IP_10_INTERFACE: '$IP_10_INTERFACE'"
    exit 1
fi

# Display current setup and proposed change for verification
echo "Detected Interface with IP 192.168.18.x: $IP_192_INTERFACE | IP Address: $IP_192"
echo "Detected Interface with IP 10.1.1.x: $IP_10_INTERFACE | IP Address: $IP_10"
echo "Proposed change: Update $IP_10_INTERFACE IP from $IP_10 to 10.1.1.$LAST_OCTET"

# Get user confirmation
read -p "Do you want to proceed with the changes? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborting script as per user request."
    exit 0
fi

# Function to update the Netplan configuration
update_netplan_ip() {
    echo "Updating Netplan configuration for $IP_10_INTERFACE to use IP 10.1.1.$LAST_OCTET"

    # Create a temporary file with elevated permissions
    {
        awk -v iface="$IP_10_INTERFACE" -v new_ip="10.1.1.$LAST_OCTET" '
            BEGIN {updated=0}
            $0 ~ iface {
                print; next
            }
            /addresses:/ && /10\.1\.1\./ && !updated {
                sub(/10\.1\.1\.\d+/, new_ip);
                updated=1
            }
            {print}
        ' "$NETPLAN_FILE"
    } | sudo tee /tmp/netplan_config.yaml > /dev/null

    # Check if the temporary file was created successfully
    if [ ! -f /tmp/netplan_config.yaml ]; then
        echo "Error: Failed to create /tmp/netplan_config.yaml. Check your permissions."
        exit 1
    fi

    # Move the temporary file to the Netplan configuration directory
    sudo mv /tmp/netplan_config.yaml "$NETPLAN_FILE"
}

# Update the Netplan configuration
update_netplan_ip

# Apply the Netplan configuration
echo "Applying Netplan configuration..."
sudo netplan apply
if [ $? -ne 0 ]; then
    echo "Error: Failed to apply Netplan configuration."
    exit 1
fi
echo "Netplan configuration applied successfully."

# Reset the 10.1.1.x interface
echo "Resetting $IP_10_INTERFACE interface..."
sudo ip link set "$IP_10_INTERFACE" down
sudo ip link set "$IP_10_INTERFACE" up

# Display all ens interfaces and their assigned IPv4 addresses
echo "Displaying all ens interfaces and their assigned IPv4 addresses..."
ip -4 addr show | grep -oP '(^|\s)ens\d+.*inet \d+\.\d+\.\d+\.\d+' | awk '{print "Interface:", $1, "| IP Address:", $3}'
