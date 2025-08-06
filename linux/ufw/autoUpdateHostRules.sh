#!/bin/bash

##    */10 * * * * bash /root/update-ufw-allowed-hosts.sh >/dev/null 2>&1

# Set safe PATH for cron
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Configuration
HOSTS=("domain.uk" "domain.uk")
CIDRS=("10.10.0.0/24" "192.168.1.0/24" "172.16.5.5/32")  # Add as many as needed
PORTS=(22)
UFW_COMMENT="auto-allowed"

# Resolve IPs from hostnames
RESOLVED_IPS=()
for HOST in "${HOSTS[@]}"; do
    IP=$(/usr/bin/getent ahosts "$HOST" | /usr/bin/awk '/STREAM/ { print $1; exit }')
    if [[ -n "$IP" ]]; then
        RESOLVED_IPS+=("$IP")
    else
        /bin/echo "Warning: Could not resolve $HOST"
    fi
done

# Include VPN subnet
RESOLVED_IPS+=("${CIDRS[@]}")

# Loop over ports and IPs
for PORT in "${PORTS[@]}"; do
    # Get existing IPs for this port and comment
    EXISTING_IPS=$(/usr/sbin/ufw status | /bin/grep "$UFW_COMMENT" | /bin/grep "$PORT" | /usr/bin/awk '{print $3}')

    # Remove outdated rules
    for IP in $EXISTING_IPS; do
        if [[ ! " ${RESOLVED_IPS[*]} " =~ " ${IP} " ]]; then
            /bin/echo "Removing outdated rule: $IP → port $PORT"
            /usr/sbin/ufw delete allow from "$IP" to any port "$PORT" comment "$UFW_COMMENT"
        fi
    done

    # Add new rules
    for IP in "${RESOLVED_IPS[@]}"; do
        if ! /usr/sbin/ufw status | /bin/grep -q "$IP.*$PORT.*$UFW_COMMENT"; then
            /bin/echo "Adding rule: $IP → port $PORT"
            /usr/sbin/ufw allow from "$IP" to any port "$PORT" comment "$UFW_COMMENT"
        fi
    done
done


