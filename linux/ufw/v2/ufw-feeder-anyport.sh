#!/bin/bash
# /usr/local/bin/ufw-feeder-trusted.sh

STATE_DIR="."
PENDING="$STATE_DIR/pending.rules"
mkdir -p "$STATE_DIR"

TRUSTED_HOSTS=("server01.domain.uk" "server02.domain.uk")
TRUSTED_CIDRS=("203.0.113.55/32" "10.20.0.0/16")

# Resolve hostnames and allow ALL ports
for HOST in "${TRUSTED_HOSTS[@]}"; do
    IP=$(getent ahosts "$HOST" | awk '/STREAM/ {print $1; exit}')
    if [[ -n "$IP" ]]; then
        echo "$IP:ALL" >> "$PENDING"
    fi
done

# Direct CIDRs
for CIDR in "${TRUSTED_CIDRS[@]}"; do
    echo "$CIDR:ALL" >> "$PENDING"
done
