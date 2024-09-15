#!/bin/bash

# Variables
NETPLAN_DIR="/etc/netplan"
NETPLAN_FILE="$NETPLAN_DIR/00-installer-config.yaml"
INTERFACE="ens20"
BACKUP_FILE="$NETPLAN_FILE.bak"

# Check if the netplan file exists
if [ -f "$NETPLAN_FILE" ]; then
    echo "Netplan configuration file found: $NETPLAN_FILE"

    # Create a backup of the original file
    echo "Backing up the original configuration to $BACKUP_FILE"
    sudo cp "$NETPLAN_FILE" "$BACKUP_FILE"

    # Ensure 'version: 2' is at the top of the file and correctly formatted
    if ! grep -q "version: 2" "$NETPLAN_FILE"; then
        echo "Adding 'version: 2' and 'network:' structure."
        sudo sed -i '1s/^/network:\n  version: 2\n/' "$NETPLAN_FILE"
    fi

    # Check if the interface is already present in the file
    if grep -q "$INTERFACE" "$NETPLAN_FILE"; then
        echo "Interface $INTERFACE already exists in the configuration. Modifying it for DHCP."
        # Replace existing configuration for the interface with DHCP settings
        sudo sed -i "/$INTERFACE/,+2 s/dhcp4: .*/dhcp4: true/" "$NETPLAN_FILE"
    else
        echo "Adding interface $INTERFACE to the configuration."
        # Add the interface configuration if not present
        sudo tee -a "$NETPLAN_FILE" > /dev/null << EOL
  ethernets:
    $INTERFACE:
      dhcp4: true
EOL
    fi

    # Apply the netplan changes
    echo "Applying netplan configuration..."
    sudo netplan apply

    echo "DHCP configuration for $INTERFACE has been applied."
else
    echo "Netplan configuration file not found. Exiting."
    exit 1
fi
