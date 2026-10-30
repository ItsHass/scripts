
#!/usr/bin/env bash
#
# Netplan Network Setup Wizard
# Ubuntu Server - DHCP / Static IPv4
#

set -Eeuo pipefail

CONFIG_DIR="/etc/netplan"
CONFIG_FILE="$CONFIG_DIR/99-network-wizard.yaml"
BACKUP_DIR="/root/netplan-backups/$(date +%Y%m%d-%H%M%S)"

# Require root
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script using sudo."
    exit 1
fi

if ! command -v netplan >/dev/null 2>&1; then
    echo "ERROR: Netplan is not installed."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: Python3 is required for IP validation."
    exit 1
fi

mkdir -p "$CONFIG_DIR"

clear

echo "======================================"
echo "       NETPLAN NETWORK WIZARD"
echo "======================================"
echo
echo "Current network configuration:"
ip -brief address
echo

# Discover interfaces
mapfile -t INTERFACES < <(
    ip -o link show | awk -F': ' '{print $2}' |
    sed 's/@.*//' | grep -v '^lo$'
)

if [[ ${#INTERFACES[@]} -eq 0 ]]; then
    echo "No network interfaces found."
    exit 1
fi

echo "Available network interfaces:"
echo

for i in "${!INTERFACES[@]}"; do
    printf "  %s) %s\n" "$((i+1))" "${INTERFACES[$i]}"
done

echo

read -rp "Select interface [1]: " SELECTION
SELECTION=${SELECTION:-1}

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] ||
   (( SELECTION < 1 || SELECTION > ${#INTERFACES[@]} )); then
    echo "Invalid interface selection."
    exit 1
fi

INTERFACE="${INTERFACES[$((SELECTION-1))]}"

echo
echo "Selected interface: $INTERFACE"
echo
echo "Network configuration:"
echo "  1) DHCP (Automatic)"
echo "  2) Static IPv4"
echo

read -rp "Select configuration [1]: " MODE
MODE=${MODE:-1}

if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then
    echo "Invalid selection."
    exit 1
fi

# Detect existing renderer
RENDERER="networkd"

if grep -RhE '^[[:space:]]*renderer:[[:space:]]*' "$CONFIG_DIR"/*.yaml "$CONFIG_DIR"/*.yml 2>/dev/null |
   grep -q 'NetworkManager'; then
    RENDERER="NetworkManager"
fi

echo
echo "Network renderer: $RENDERER"
echo

# Validate IP addresses using Python's standard library
valid_ip() {
    python3 -c '
import ipaddress, sys
try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    sys.exit(1)
' "$1" 2>/dev/null
}

valid_cidr() {
    python3 -c '
import ipaddress, sys
try:
    ipaddress.IPv4Interface(sys.argv[1])
except ValueError:
    sys.exit(1)
' "$1" 2>/dev/null
}

# DHCP configuration
if [[ "$MODE" == "1" ]]; then
    NETWORK_MODE="dhcp4: true"

    echo "DHCP selected."
    echo

else
    # Static IP configuration
    echo "Enter your static network settings:"
    echo

    while true; do
        read -rp "IP address with CIDR (e.g. 192.168.1.50/24): " IP_ADDRESS
        if valid_cidr "$IP_ADDRESS"; then
            break
        fi
        echo "Invalid IPv4 address or CIDR."
    done

    while true; do
        read -rp "Default gateway (e.g. 192.168.1.1): " GATEWAY
        if valid_ip "$GATEWAY" &&
           python3 -c '
import ipaddress, sys
if ipaddress.ip_address(sys.argv[1]).version != 4: sys.exit(1)
' "$GATEWAY" 2>/dev/null; then
            break
        fi
        echo "Invalid IPv4 gateway."
    done

    read -rp "DNS servers, comma separated [1.1.1.1,8.8.8.8]: " DNS
    DNS=${DNS:-1.1.1.1,8.8.8.8}

    read -rp "DNS search domain (optional): " SEARCH_DOMAIN

    IFS=',' read -ra DNS_SERVERS <<< "$DNS"

    for DNS_SERVER in "${DNS_SERVERS[@]}"; do
        DNS_SERVER=$(echo "$DNS_SERVER" | xargs)
        if ! valid_ip "$DNS_SERVER"; then
            echo "Invalid DNS server: $DNS_SERVER"
            exit 1
        fi
    done

    NETWORK_MODE="dhcp4: false"
fi

echo
echo "======================================"
echo "         CONFIGURATION SUMMARY"
echo "======================================"
echo "Interface : $INTERFACE"
echo "Mode      : $([[ "$MODE" == "1" ]] && echo DHCP || echo Static)"
echo "Renderer  : $RENDERER"

if [[ "$MODE" == "2" ]]; then
    echo "IP        : $IP_ADDRESS"
    echo "Gateway   : $GATEWAY"
    echo "DNS       : $DNS"
    echo "Search    : ${SEARCH_DOMAIN:-None}"
fi

echo

read -rp "Continue and create configuration? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Backup existing configuration
mkdir -p "$BACKUP_DIR"

cp -a "$CONFIG_DIR/." "$BACKUP_DIR/"

echo
echo "Backup created: $BACKUP_DIR"

# Disable existing YAML configurations to avoid conflicting settings
mkdir -p "$BACKUP_DIR/disabled"

shopt -s nullglob
for FILE in "$CONFIG_DIR"/*.yaml "$CONFIG_DIR"/*.yml; do
    [[ -f "$FILE" ]] || continue
    mv "$FILE" "$BACKUP_DIR/disabled/"
done
shopt -u nullglob

# Restore configuration if generation fails
restore_config() {
    echo
    echo "Restoring original Netplan configuration..."

    rm -f "$CONFIG_DIR"/*.yaml "$CONFIG_DIR"/*.yml

    cp -a "$BACKUP_DIR/." "$CONFIG_DIR/"

    netplan generate || true

    echo "Original configuration restored."
}

# Generate YAML
{
    echo "network:"
    echo "  version: 2"
    echo "  renderer: $RENDERER"
    echo "  ethernets:"
    echo "    $INTERFACE:"
    echo "      $NETWORK_MODE"

    if [[ "$MODE" == "2" ]]; then
        echo "      addresses:"
        echo "        - $IP_ADDRESS"

        echo "      routes:"
        echo "        - to: default"
        echo "          via: $GATEWAY"

        echo "      nameservers:"
        echo "        addresses:"

        for DNS_SERVER in "${DNS_SERVERS[@]}"; do
            DNS_SERVER=$(echo "$DNS_SERVER" | xargs)
            echo "          - $DNS_SERVER"
        done

        if [[ -n "$SEARCH_DOMAIN" ]]; then
            if [[ ! "$SEARCH_DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                echo "Invalid DNS search domain."
                restore_config
                exit 1
            fi
            echo "        search:"
            echo "          - $SEARCH_DOMAIN"
        fi
    fi
} > "$CONFIG_FILE"

chmod 600 "$CONFIG_FILE"

echo
echo "Generated configuration:"
cat "$CONFIG_FILE"
echo

# Validate configuration
if ! netplan generate; then
    echo "ERROR: Netplan validation failed."
    restore_config
    exit 1
fi

echo
echo "Netplan configuration validated successfully."
echo

read -rp "Apply configuration using Netplan Try? [y/N]: " APPLY

if [[ ! "$APPLY" =~ ^[Yy]$ ]]; then
    restore_config
    echo "Configuration cancelled and previous settings restored."
    exit 0
fi

echo
echo "Applying configuration."
echo "You will have 120 seconds to confirm connectivity."
echo

# Try allows automatic rollback if not confirmed
if netplan try --timeout 120; then
    echo
    echo "======================================"
    echo "       NETWORK CONFIGURATION OK"
    echo "======================================"
    echo
    echo "Interface:"
    ip -brief address show "$INTERFACE"
    echo
    echo "Backup: $BACKUP_DIR"
    echo "Config: $CONFIG_FILE"
    echo
else
    echo
    echo "Network configuration was not confirmed."
    restore_config
    echo "Please investigate and try again."
    exit 1
fi
