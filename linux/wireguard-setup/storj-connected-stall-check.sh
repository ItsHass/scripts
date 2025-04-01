#!/bin/bash

# Check if the password is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <sudo_password>"
    exit 1
fi

SUDO_PASSWORD="$1"
TEMP_LOG_FILE="/tmp/docker_log_check.txt"

# Find the Docker container with a mount containing either /mnt/ or /disk/
CONTAINER_ID=$(docker inspect --format='{{.Id}} {{range .Mounts}}{{.Source}}{{end}}' $(docker ps -q) | grep -E "/mnt/|/disk/" | awk '{print $1}')

if [ -z "$CONTAINER_ID" ]; then
    echo "No container found with /mnt/ or /disk/ mounted."
    exit 1
fi

echo "Targeting container: $CONTAINER_ID"

# Write last two log lines to a temp file
docker logs "$CONTAINER_ID" --tail 2 > "$TEMP_LOG_FILE" 2>&1

# Read from the temporary log file
SECOND_LAST_LOG=$(head -n 1 "$TEMP_LOG_FILE")
LAST_LOG=$(tail -n 1 "$TEMP_LOG_FILE")

echo "Second last log: $SECOND_LAST_LOG"
echo "Last log: $LAST_LOG"

# Check for "Connecting" being stuck
if grep -q "Connecting" "$TEMP_LOG_FILE" && ! grep -q "Connected." "$TEMP_LOG_FILE"; then
    echo "Stuck on 'Connecting'. Restarting process..."

    echo "$SUDO_PASSWORD" | sudo -S wg-quick down wg0
    docker kill "$CONTAINER_ID"
    docker start "$CONTAINER_ID"
    sleep 30
    echo "$SUDO_PASSWORD" | sudo -S wg-quick up wg0

    echo "Process completed."
else
    echo "No 'Connecting' issue detected in logs. Exiting."
fi

# Clean up temporary log file
rm -f "$TEMP_LOG_FILE"
