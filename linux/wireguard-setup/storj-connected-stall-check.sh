#!/bin/bash

# Check if the password is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <sudo_password>"
    exit 1
fi

SUDO_PASSWORD="$1"

# Find the Docker container with a mount containing either /mnt/ or /disk/
CONTAINER_ID=$(docker inspect --format='{{.Id}} {{range .Mounts}}{{.Source}}{{end}}' $(docker ps -q) | grep -E "/mnt/|/disk/" | awk '{print $1}')

if [ -z "$CONTAINER_ID" ]; then
    echo "No container found with /mnt/ or /disk/ mounted."
    exit 1
fi

echo "Targeting container: $CONTAINER_ID"

# Get the last log line
LAST_LOG=$(docker logs "$CONTAINER_ID" --tail 1 2>/dev/null)

# Check if the last log line ends with "connected."
if [[ "$LAST_LOG" == *"connected." ]]; then
    echo "Last log line confirms connection. Restarting process..."

    echo "$SUDO_PASSWORD" | sudo -S wg-quick down wg0
    docker kill "$CONTAINER_ID"
    docker start "$CONTAINER_ID"
    sleep 30
    echo "$SUDO_PASSWORD" | sudo -S wg-quick up wg0

    echo "Process completed."
else
    echo "No 'connected.' message found in logs. Exiting."
fi
