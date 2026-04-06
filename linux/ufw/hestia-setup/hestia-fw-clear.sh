#!/bin/bash
set -euo pipefail

LOG="hestia-fw-clear-autohost.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

log "=== AUTOHOST firewall cleanup start ==="

# Delete every rule with AUTOHOST in comment
while IFS=$'\t' read -r ID ACTION PROTO PORT IP COMMENT SPND TIME DATE; do
    [[ "$COMMENT" != AUTOHOST* ]] && continue
    log "Deleting AUTOHOST rule ID $ID for $IP:$PORT/$PROTO"
    v-delete-firewall-rule "$ID"
done < <(v-list-firewall plain)

log "=== AUTOHOST firewall cleanup complete ==="

