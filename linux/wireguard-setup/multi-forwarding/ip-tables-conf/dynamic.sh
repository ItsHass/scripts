#!/bin/bash

# Usage: ip-tables_PEER.sh <up|down> <DEST_IP> <PORT>

MODE="$1"
DEST_IP="$2"
PORT="$3"

# Validate input
if [[ -z "$MODE" || -z "$DEST_IP" || -z "$PORT" ]]; then
    echo "Usage: $0 <up|down> <DEST_IP> <PORT>"
    exit 1
fi

if [[ "$MODE" == "up" ]]; then
    echo "Applying firewall rules for WireGuard peer (PreUp)..."

    # Allow traffic on the specified port
    iptables -I INPUT -p tcp -m state --state NEW --dport "$PORT" -j ACCEPT
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT

    # DNAT rules to forward the port to the peer
    iptables -t nat -I PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$DEST_IP":"$PORT"
    iptables -t nat -I PREROUTING -p udp --dport "$PORT" -j DNAT --to-destination "$DEST_IP":"$PORT"

elif [[ "$MODE" == "down" ]]; then
    echo "Removing firewall rules for WireGuard peer (PostDown)..."

    # Remove traffic rules
    iptables -D INPUT -p tcp -m state --state NEW --dport "$PORT" -j ACCEPT
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT

    # Remove DNAT rules
    iptables -t nat -D PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$DEST_IP":"$PORT"
    iptables -t nat -D PREROUTING -p udp --dport "$PORT" -j DNAT --to-destination "$DEST_IP":"$PORT"

else
    echo "Invalid mode. Use 'up' for PreUp or 'down' for PostDown."
    exit 1
fi

echo "Operation completed successfully."
exit 0
