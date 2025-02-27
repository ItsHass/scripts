#!/bin/bash

# Define the Ethernet gateway and interface
GATEWAY="<ETHERNET_GATEWAY>"
INTERFACE="enp0s3"  # Adjust if using a different Ethernet interface
LOG_FILE="/etc/wireguard/github-routes.log"

# Install required dependencies if missing
install_dependencies() {
    local missing=()
    for cmd in curl jq sipcalc; do
        if ! command -v $cmd &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Installing missing dependencies: ${missing[*]}..."
        if [ -f /etc/debian_version ]; then
            sudo apt update && sudo apt install -y "${missing[@]}"
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y "${missing[@]}"
        else
            echo "Unsupported OS. Please install: ${missing[*]}"
            exit 1
        fi
    fi
}

# Fetch GitHub IPs
fetch_github_ips() {
    local ips
    ips=$(curl -s https://api.github.com/meta | jq -r '.git[], .web[]')
    
    if [ -z "$ips" ]; then
        echo "Error: Failed to fetch GitHub IPs." >&2
        exit 1
    fi

    # Fetch objects.githubusercontent.com IPs dynamically
    local objects_ips
    objects_ips=$(dig +short objects.githubusercontent.com | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')

    echo "$ips"
    echo "$objects_ips"
}

# Expand CIDR ranges into individual IPs
expand_cidr() {
    local cidr="$1"
    sipcalc "$cidr" | awk '/Usable range/ {start=$4; end=$6} END {
        split(start, s, ".");
        split(end, e, ".");
        for (a=s[1]; a<=e[1]; a++)
            for (b=s[2]; b<=e[2]; b++)
                for (c=s[3]; c<=e[3]; c++)
                    for (d=s[4]; d<=e[4]; d++)
                        print a"."b"."c"."d;
    }'
}

validate_route() {
    local ip="$1"
    ip route get "$ip" 2>/dev/null | grep -q "via $GATEWAY dev $INTERFACE"
}

manage_routes() {
    local action="$1"
    local ips="$2"

    for IP in $ips; do
        if [[ "$IP" == */* ]]; then
            expanded_ips=$(expand_cidr "$IP")
        else
            expanded_ips="$IP"
        fi

        for ip_addr in $expanded_ips; do
            if [[ "$action" == "add" ]]; then
                if validate_route "$ip_addr"; then
                    echo "Route for $ip_addr already exists. Skipping."
                else
                    echo "Adding route for $ip_addr..."
                    ip route add "$ip_addr" via "$GATEWAY" dev "$INTERFACE"
                fi
            elif [[ "$action" == "del" ]]; then
                if validate_route "$ip_addr"; then
                    echo "Removing route for $ip_addr..."
                    ip route del "$ip_addr" via "$GATEWAY" dev "$INTERFACE"
                else
                    echo "Route for $ip_addr not found. Skipping."
                fi
            fi
        done
    done
}

# Main logic
install_dependencies
GITHUB_IPS=$(fetch_github_ips)

if [ "$1" = "add" ]; then
    echo "Adding GitHub routes via $GATEWAY on $INTERFACE..."
    echo "$GITHUB_IPS" > "$LOG_FILE"
    manage_routes "add" "$GITHUB_IPS"

elif [ "$1" = "del" ]; then
    echo "Removing GitHub routes..."
    manage_routes "del" "$GITHUB_IPS"

elif [ "$1" = "remove" ]; then
    echo "Emergency: Removing old GitHub routes from $LOG_FILE..."
    if [ -f "$LOG_FILE" ]; then
        OLD_IPS=$(cat "$LOG_FILE")
        manage_routes "del" "$OLD_IPS"
        rm -f "$LOG_FILE"
    else
        echo "No previous routes found to remove."
    fi
else
    echo "Usage: $0 {add|del|remove}"
fi
