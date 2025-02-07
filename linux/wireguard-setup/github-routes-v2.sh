#!/bin/bash

# commands
# add
# del 


# Define the Ethernet gateway and interface
GATEWAY="<ETHERNET_GATEWAY>"
INTERFACE="enp0s3"  # Adjust if using a different Ethernet interface
LOG_FILE="/etc/wireguard/github-routes.log"

# Fetch GitHub IPs
GITHUB_IPS=$(curl -s https://api.github.com/meta | jq -r '.git[], .web[]')

if [ -z "$GITHUB_IPS" ]; then
    echo "Error: Failed to fetch GitHub IPs." >&2
    exit 1
fi

validate_route() {
    local ip="$1"
    ip route get "$ip" 2>/dev/null | grep -q "via $GATEWAY dev $INTERFACE"
}

if [ "$1" = "add" ]; then
    echo "Adding GitHub routes via $GATEWAY on $INTERFACE..."

    # Save the current routes before adding new ones
    echo "$GITHUB_IPS" > "$LOG_FILE"

    for IP in $GITHUB_IPS; do
        # Convert CIDR to single IP (if needed)
        IP_ADDR=$(echo "$IP" | cut -d'/' -f1)

        if validate_route "$IP_ADDR"; then
            echo "Route for $IP_ADDR already exists. Skipping."
        else
            echo "Adding route for $IP_ADDR..."
            ip route add "$IP_ADDR" via "$GATEWAY" dev "$INTERFACE"
        fi
    done

elif [ "$1" = "del" ]; then
    echo "Removing GitHub routes..."
    for IP in $GITHUB_IPS; do
        IP_ADDR=$(echo "$IP" | cut -d'/' -f1)
        if validate_route "$IP_ADDR"; then
            echo "Removing route for $IP_ADDR..."
            ip route del "$IP_ADDR" via "$GATEWAY" dev "$INTERFACE"
        else
            echo "Route for $IP_ADDR not found. Skipping."
        fi
    done

elif [ "$1" = "remove" ]; then
    echo "Emergency: Removing old GitHub routes from $LOG_FILE..."
    if [ -f "$LOG_FILE" ]; then
        OLD_IPS=$(cat "$LOG_FILE")
        for IP in $OLD_IPS; do
            IP_ADDR=$(echo "$IP" | cut -d'/' -f1)
            if validate_route "$IP_ADDR"; then
                echo "Removing route for $IP_ADDR..."
                ip route del "$IP_ADDR" via "$GATEWAY" dev "$INTERFACE"
            else
                echo "Route for $IP_ADDR not found. Skipping."
            fi
        done
        rm -f "$LOG_FILE"
    else
        echo "No previous routes found to remove."
    fi
fi
