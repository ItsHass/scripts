#!/bin/bash
PATH=/usr/local/hestia/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

####set -euo pipefail

bash hestia-fw-clear.sh;

CONFIG="firewall-hosts.conf"
LOG="logs/hestia-fw-sync.log"
PREFIX="AUTOHOST"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }
sanitize() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9 _-'; }

log "=== Firewall sync start ==="

declare -A RULE_HOSTS
declare -A RULE_LABELS

# Build desired state
while IFS='|' read -r HOST PORT PROTO LABEL; do
    [[ -z "$HOST" || "$HOST" =~ ^# ]] && continue
    IPS=$(dig +short "$HOST" A; dig +short "$HOST" AAAA)
    IPS=$(printf "%s\n" $IPS | grep -E '^[0-9a-fA-F:.]+$' || true)
    [[ -z "$IPS" ]] && { log "WARNING: $HOST resolved to no IPs"; continue; }
    for IP in $IPS; do
        KEY="$IP|$PORT|$PROTO"
        RULE_HOSTS["$KEY"]+="$HOST "
        RULE_LABELS["$KEY"]="$LABEL"
    done
done < "$CONFIG"

# Delete all existing AUTOHOST rules first
mapfile -t EXISTING < <(
    v-list-firewall plain | awk -F'\t' '$7 ~ /^AUTOHOST_/ {print $1}'
)
for ID in "${EXISTING[@]}"; do
    log "Removing existing AUTOHOST rule $ID"
    v-delete-firewall-rule "$ID"
done

# Add consolidated rules
for KEY in "${!RULE_HOSTS[@]}"; do
    IFS='|' read -r IP PORT PROTO <<< "$KEY"

    HOSTS=$(echo "${RULE_HOSTS[$KEY]}" | xargs -n1 | sort -u)
    HOSTS=$(sanitize "$HOSTS" | cut -c1-40)
    LABEL=$(sanitize "${RULE_LABELS[$KEY]}")
    COMMENT="${PREFIX}_${LABEL}_${HOSTS}"

    log "Adding rule $IP:$PORT/$PROTO"
    v-add-firewall-rule ACCEPT "$IP" "$PORT" "$PROTO" "$COMMENT"
done

log "=== Firewall sync complete ==="


