#!/bin/bash

# Define the Ethernet gateway and interface
GATEWAY="<ETHERNET_GATEWAY>"
INTERFACE="eth0"  # Adjust if using a different Ethernet interface
LOG_FILE="/etc/wireguard/github-routes.log"

# Fetch GitHub IPs
GITHUB_IPS=$(curl -s https://api.github.com/meta | jq -r '.git[], .web[]')

if [ "$1" = "add" ]; then
    echo "Adding GitHub routes via $GATEWAY on $INTERFACE..."
    
    # Save the current routes before adding new ones
    echo "$GITHUB_IPS" > "$LOG_FILE"

    for IP in $GITHUB_IPS; do
        ip route add "$IP" via "$GATEWAY" dev "$INTERFACE"
    done

elif [ "$1" = "del" ]; then
    echo "Removing GitHub routes..."
    for IP in $GITHUB_IPS; do
        ip route del "$IP" via "$GATEWAY" dev "$INTERFACE"
    done

elif [ "$1" = "remove" ]; then
    echo "Emergency: Removing old GitHub routes from $LOG_FILE..."
    if [ -f "$LOG_FILE" ]; then
        OLD_IPS=$(cat "$LOG_FILE")
        for IP in $OLD_IPS; do
            ip route del "$IP" via "$GATEWAY" dev "$INTERFACE"
        done
        rm -f "$LOG_FILE"
    else
        echo "No previous routes found to remove."
    fi
fi
