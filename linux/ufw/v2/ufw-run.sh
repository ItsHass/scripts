#!/bin/bash
# /usr/local/bin/run.sh
# Wrapper to run all ufw feeders and reconciler with detailed timestamped logging

# Set PATH for cron
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Directory containing feeders & reconciler
WORKDIR="$(pwd)"

# Log directory
LOGDIR="$WORKDIR/logs"
mkdir -p "$LOGDIR"

# Log file for today
LOGFILE="$LOGDIR/ufw-run-$(date +%F).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

{
    log "=== UFW run started ==="

    # --- Run all feeder scripts starting with ufw-feeder- but NOT ufw-feeder_ ---
    for FEEDER in "$WORKDIR"/ufw-feeder-*; do
        BASENAME=$(basename "$FEEDER")
        [[ "$BASENAME" == ufw-feeder_* ]] && continue
        if [[ -x "$FEEDER" ]]; then
            log ">>> Running feeder: $BASENAME"
            "$FEEDER" 2>&1 | while IFS= read -r LINE; do log "    $LINE"; done
            log "<<< Finished feeder: $BASENAME"
        else
            log "Skipping $BASENAME (not executable)"
        fi
    done

    # Wait 10 seconds before reconciler
    log "--- Waiting 10 seconds before reconciler ---"
    sleep 10

    # Run reconciler
    RECONCILER="$WORKDIR/ufw-reconciler.sh"
    if [[ -x "$RECONCILER" ]]; then
        log ">>> Running reconciler"
        "$RECONCILER" 2>&1 | while IFS= read -r LINE; do log "    $LINE"; done
        log "<<< Finished reconciler"
    else
        log "Reconciler not found or not executable"
    fi

    log "=== UFW run finished ==="

} >> "$LOGFILE" 2>&1

# --- Keep only last 5 days of logs ---
find "$LOGDIR" -name "ufw-run-*.log" -type f -mtime +5 -exec rm -f {} \;
