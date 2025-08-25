#!/bin/bash
# ufw-reconciler.sh
# Reconciles UFW rules from feeders safely, supports ALL ports and safety CIDRs

# -------- Configuration --------
STATE_DIR="."
PENDING="$STATE_DIR/pending.rules"
APPLIED="$STATE_DIR/applied.rules"
LOCK="$STATE_DIR/reconcile.lock"

# Safety CIDRs & ports (always allowed)
SAFETY_CIDRS=("10.10.0.0/24" "192.168.1.0/24")
SAFETY_PORTS=(22 8006 443)

UFW_CMD="/usr/sbin/ufw"

# -------- Prepare state --------
mkdir -p "$STATE_DIR"
touch "$PENDING" "$APPLIED"

# -------- Locking --------
exec 9>"$LOCK"
if ! /usr/bin/flock -n 9; then
    echo "Another reconcile is running, exiting"
    exit 0
fi

# -------- Merge feeders --------
if [ -s "$PENDING" ]; then
    sort -u "$PENDING" > "$PENDING.sorted"
    rm -f "$PENDING"
else
    touch "$PENDING.sorted"
fi

# -------- Add safety rules --------
for CIDR in "${SAFETY_CIDRS[@]}"; do
    for PORT in "${SAFETY_PORTS[@]}"; do
        echo "$CIDR:$PORT" >> "$PENDING.sorted"
    done
done

sort -u "$PENDING.sorted" -o "$PENDING.sorted"

# -------- Compare with last applied --------
if [ -s "$APPLIED" ] && cmp -s "$PENDING.sorted" "$APPLIED"; then
    echo "No changes detected, exiting"
    exit 0
fi

# -------- Remove old auto-allowed rules --------
$UFW_CMD status numbered | grep "auto-allowed" | \
    sed -E 's/^\[ *([0-9]+)\].*/\1/' | sort -nr | while read -r NUM; do
        yes | $UFW_CMD delete "$NUM"
done

# -------- Apply new rules --------
while IFS=: read -r IP PORT; do
    [ -z "$IP" ] && continue
    if [ "$PORT" = "ALL" ]; then
        $UFW_CMD allow from "$IP" comment "auto-allowed"
    else
        $UFW_CMD allow from "$IP" to any port "$PORT" comment "auto-allowed"
    fi
done < "$PENDING.sorted"

# -------- Save applied rules --------
mv "$PENDING.sorted" "$APPLIED"

echo "Reconciliation complete."
