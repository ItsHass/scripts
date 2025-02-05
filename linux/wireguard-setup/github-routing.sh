#!/bin/bash

# Define the Ethernet gateway and interface
GATEWAY="<ETHERNET_GATEWAY>"
INTERFACE="enp0s3"  # Adjust if using a different Ethernet interface
LOG_FILE="/etc/wireguard/github-routes.log"

# Fetch GitHub IPs and filter for IPv4 only
GITHUB_IPS=$(curl -s https://api.github.com/meta | jq -r '.git[], .web[]' | grep -P '^\d+\.\d+\.\d+\.\d+$')

if [ "$1" = "add" ]; then
    echo "Adding GitHub IPv4 routes via $GATEWAY on $INTERFACE..."
    
    # Save the current routes before adding new ones
    echo "$GITHUB_IPS" > "$LOG_FILE"

    for IP in $GITHUB_IPS; do
        # Check if the route exists before trying to add it
        ip route show "$IP" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            ip route add "$IP" via "$GATEWAY" dev "$INTERFACE" || true
        else
            echo "Route for $IP already exists. Skipping."
        fi
    done

elif [ "$1" = "del" ]; then
    echo "Removing GitHub IPv4 routes..."
    for IP in $GITHUB_IPS; do
        ip route del "$IP" via "$GATEWAY" dev "$INTERFACE" || true
    done

elif [ "$1" = "remove" ]; then
    echo "Emergency: Removing old GitHub IPv4 routes from $LOG_FILE..."
    if [ -f "$LOG_FILE" ]; then
        OLD_IPS=$(cat "$LOG_FILE")
        for IP in $OLD_IPS; do
            ip route del "$IP" via "$GATEWAY" dev "$INTERFACE" || true
        done
        rm -f "$LOG_FILE"
    else
        echo "No previous routes found to remove."
    fi
fi
