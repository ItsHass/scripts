#!/bin/bash
# /usr/local/bin/ufw-reconcile.sh

STATE_DIR="."
PENDING="$STATE_DIR/pending.rules"
APPLIED="$STATE_DIR/applied.rules"
LOCK="$STATE_DIR/reconcile.lock"

# Safety CIDRs and ports (always allowed)
SAFETY_CIDRS=("10.10.0.0/24" "192.168.1.0/24")
SAFETY_PORTS=(22 8006 443)

# Create state dir if missing
mkdir -p "$STATE_DIR"
touch "$PENDING" "$APPLIED"

# Locking
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "Another reconcile is running, exiting"
    exit 0
fi

# Merge feeders
sort -u "$PENDING" > "$PENDING.sorted"
rm -f "$PENDING"

# Add safety rules
for CIDR in "${SAFETY_CIDRS[@]}"; do
    for PORT in "${SAFETY_PORTS[@]}"; do
        echo "$CIDR:$PORT" >> "$PENDING.sorted"
    done
done

# Deduplicate again
sort -u "$PENDING.sorted" -o "$PENDING.sorted"

# Compare with last applied
if cmp -s "$PENDING.sorted" "$APPLIED"; then
    echo "No changes"
    exit 0
fi

# Remove all previous auto-allowed rules
/usr/sbin/ufw status numbered | awk '/auto-allowed/ {print $1}' | \
    sed 's/[][]//g' | sort -nr | while read -r NUM; do
        yes | /usr/sbin/ufw delete "$NUM"
    done

# Apply new rules
while IFS=: read -r IP PORT; do
    [ -n "$IP" ] && [ -n "$PORT" ] && \
        /usr/sbin/ufw allow from "$IP" to any port "$PORT" comment "auto-allowed"
done < "$PENDING.sorted"

# Save as last applied
mv "$PENDING.sorted" "$APPLIED"
