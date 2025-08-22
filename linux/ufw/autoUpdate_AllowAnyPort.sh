#!/bin/bash

## Example cron:
## */10 * * * * bash /root/update-ufw-allow-hosts-any-port.sh >/dev/null 2>&1

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Configuration
HOSTS=("example.com" "203.0.113.5")   # Hostnames or IPs
UFW_COMMENT="auto-allowed-any-port"

# Resolve hostnames to IPs
RESOLVED_IPS=()
for HOST in "${HOSTS[@]}"; do
    IP=$(getent ahosts "$HOST" | awk '/STREAM/ {print $1; exit}')
    if [[ -n "$IP" ]]; then
        RESOLVED_IPS+=("$IP")
    else
        echo "Warning: could not resolve $HOST"
    fi
done

# Existing rules for this comment
EXISTING_IPS=$(ufw status | grep "$UFW_COMMENT" | awk '{print $3}')

# Remove outdated rules
for IP in $EXISTING_IPS; do
    if [[ ! " ${RESOLVED_IPS[*]} " =~ " ${IP} " ]]; then
        echo "Removing outdated rule: $IP → all ports"
        ufw delete allow from "$IP" comment "$UFW_COMMENT"
    fi
done

# Add new rules
for IP in "${RESOLVED_IPS[@]}"; do
    if ! ufw status | grep -q "$IP.*Anywhere.*$UFW_COMMENT"; then
        echo "Adding allow rule: $IP → all ports"
        ufw allow from "$IP" to any comment "$UFW_COMMENT"
    fi
done
