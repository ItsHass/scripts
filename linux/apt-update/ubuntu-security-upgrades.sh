#!/bin/bash

set -e

WEBHOOK_URL="https://n8n........."   # <-- your webhook

LOG_FILE="/var/log/security-updates.log"
TMP_LOG="/tmp/apt-security-upgrade.log"

echo "===== $(date) Security Update Run =====" >> "$LOG_FILE"

# 1. Update package lists
apt update -y >> "$LOG_FILE" 2>&1

# 2. Run ONLY security upgrades via unattended-upgrades in dry-run first
unattended-upgrade --dry-run --debug > "$TMP_LOG" 2>&1

# Check if any upgrades would be applied
UPDATES=$(grep -E "Inst|upgraded|packages will be upgraded" "$TMP_LOG" || true)

# 3. Run actual security upgrades
unattended-upgrade -v >> "$LOG_FILE" 2>&1

# 4. Clean up
apt autoremove -y >> "$LOG_FILE" 2>&1
apt clean >> "$LOG_FILE" 2>&1

# 5. Detect if anything actually changed
CHANGES=$(grep -E "Inst|upgraded|The following packages" "$TMP_LOG" || true)

# 6. Send webhook only if updates happened
if [ ! -z "$CHANGES" ]; then

    HOSTNAME=$(hostname)
    DATE=$(date -Iseconds)

    PAYLOAD=$(cat <<EOF
{
  "hostname": "$HOSTNAME",
  "timestamp": "$DATE",
  "updates_detected": true,
  "details": $(echo "$CHANGES" | jq -R -s -c 'split("\n") | map(select(length > 0))')
}
EOF
)

    curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" >> "$LOG_FILE" 2>&1

else
    echo "No security updates available." >> "$LOG_FILE"
fi

echo "===== End Run =====" >> "$LOG_FILE"
