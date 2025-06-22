#!/bin/bash

# =======================
# Configurable Variables
# =======================

SOURCE_DIR="/mnt/xxx/node/"
DEST_DIR="/mnt/xxx/node/"
LOG_DIR="/mnt/xxx"
SYNC_LOG="$LOG_DIR/sync.log"
SYNC_1_LOG="$LOG_DIR/sync_1.log"
SYNC_2_LOG="$LOG_DIR/sync_2.log"
SLEEP_DURATION=5

# =======================
# Functions
# =======================

log() {
    echo "$1"
    echo "$1" >> "$SYNC_LOG"
}

run_sync() {
    local sync_label=$1
    local log_file=$2

    log "Running $sync_label"
    date | tee -a "$SYNC_LOG"

    rsync -auh --delete --progress "$SOURCE_DIR" "$DEST_DIR" >> "$log_file"

    log "$sync_label Finished"
    date | tee -a "$SYNC_LOG"
}

# =======================
# Main Script Execution
# =======================

clear

run_sync "Sync 1" "$SYNC_1_LOG"

log "Sleeping for $SLEEP_DURATION seconds"
sleep "$SLEEP_DURATION"

log "-------"

run_sync "Sync 2" "$SYNC_2_LOG"

log "Finished 2 x syncs"
