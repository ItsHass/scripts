#!/bin/bash
STATE_DIR="."
PENDING="$STATE_DIR/pending.rules"
mkdir -p "$STATE_DIR"

HOSTS=("server01.domain.uk" "server02.domain.uk")
CIDRS=("10.10.0.0/24" "192.168.1.0/24")
PORTS=(22 8006 443)   # multiple ports

for HOST in "${HOSTS[@]}"; do
    IP=$(getent ahosts "$HOST" | awk '/STREAM/ {print $1; exit}')
    if [[ -n "$IP" ]]; then
        for PORT in "${PORTS[@]}"; do
            echo "$IP:$PORT" >> "$PENDING"
        done
    fi
done

for CIDR in "${CIDRS[@]}"; do
    for PORT in "${PORTS[@]}"; do
        echo "$CIDR:$PORT" >> "$PENDING"
    done
done
