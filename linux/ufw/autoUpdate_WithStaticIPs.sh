#!/bin/bash
#
# Run every 10 minutes via cron:
# */10 * * * * bash /root/update-ufw-allowed-hosts.sh >/dev/null 2>&1
#

# Set safe PATH for cron
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# === Config ===
HOSTS=("domain1" "domain2")  # hostnames to resolve dynamically
STATIC_CIDRS=("10.10.0.0/24" "192.168.1.0/24" "172.16.5.5/32")  # permanent ranges (VPN etc.)
PORTS=(22)   # restrict to SSH only, or add PBS ports if needed
UFW_COMMENT="auto-allowed-with-static"

# === Step 1: Resolve hostnames ===
RESOLVED_IPS=()
for HOST in "${HOSTS[@]}"; do
    IP=$(/usr/bin/getent ahosts "$HOST" | /usr/bin/awk '/STREAM/ { print $1; exit }')
    if [[ -n "$IP" ]]; then
        RESOLVED_IPS+=("$IP")
    else
        echo "Warning: Could not resolve $HOST"
    fi
done

# === Step 2: Handle rules dynamically for hostnames only ===
for PORT in "${PORTS[@]}"; do
    # Existing rules with our comment
    EXISTING_IPS=$(/usr/sbin/ufw status | grep "$UFW_COMMENT" | grep "$PORT" | awk '{print $3}')

    # Remove outdated hostname rules
    for IP in $EXISTING_IPS; do
        if [[ ! " ${RESOLVED_IPS[*]} " =~ " ${IP} " ]]; then
            echo "Removing outdated hostname rule: $IP → port $PORT"
            /usr/sbin/ufw delete allow from "$IP" to any port "$PORT" comment "$UFW_COMMENT"
        fi
    done

    # Add new hostname rules
    for IP in "${RESOLVED_IPS[@]}"; do
        if ! /usr/sbin/ufw status | grep -q "$IP.*$PORT.*$UFW_COMMENT"; then
            echo "Adding hostname rule: $IP → port $PORT"
            /usr/sbin/ufw allow from "$IP" to any port "$PORT" comment "$UFW_COMMENT"
        fi
    done
done

# === Step 3: Ensure static CIDRs exist once ===
for CIDR in "${STATIC_CIDRS[@]}"; do
    for PORT in "${PORTS[@]}"; do
        if ! /usr/sbin/ufw status | grep -q "$CIDR.*$PORT"; then
            echo "Ensuring static CIDR rule: $CIDR → port $PORT"
            /usr/sbin/ufw allow from "$CIDR" to any port "$PORT" comment "static-allow"
        fi
    done
done
