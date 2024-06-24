#!/bin/bash

# Check if variables.sh exists
if [ ! -f ./variables.sh ]; then
  echo "Error: variables.sh not found. Exiting."
  exit 1
fi
# run_storagenode.sh

# Source the variables from variables.sh
source ./variables.sh

# Stop and remove any existing container with the same name
docker stop $DockerRemoveName &> /dev/null
docker rm $DockerRemoveName &> /dev/null

# Pull the latest image
docker pull storjlabs/storagenode:latest

# Run the Docker container with the sourced variables
docker run -d \  # Run container in detached mode
  --restart unless-stopped \  # Restart policy
  --stop-timeout 300 \  # Stop timeout in seconds
  --log-driver json-file \ # Log driver
  --log-opt path=$LogFilePath \ # Log file path
  --log-opt max-size=$MaxLogSize \  # Max log size
  -p $Port:28967/udp \  # UDP port mapping
  -p $Port:28967/tcp \  # TCP port mapping
  -p $DashPort:14002 \  # Dashboard port mapping
  -e WALLET="$Wallet" \  # Wallet environment variable
  -e EMAIL="$Email" \  # Email environment variable
  -e ADDRESS="$ExtAddr" \  # External address environment variable
  -e BANDWIDTH="1000TB" \  # Bandwidth limit
  -e STORAGE="$NodeSize" \  # Storage size limit
  --mount type=bind,source="$IdentityLocation",destination=/app/identity \  # Identity location
  --mount type=bind,source="$StorageLocation",destination=/app/config \  # Storage location
  --mount type=bind,source="$dbs_location",destination=/app/dbs \  # Database location
  --sysctl net.ipv4.tcp_fastopen=3 \  # System control parameter for TCP fast open
  --name $DockerName \  # Container name
  storjlabs/storagenode:latest \  # Docker image
  --operator.wallet-features="$WalletFeatures" \  # Wallet features
  --storage2.database-dir=$storage2_dbs \  # Database directory
  --storage2.orders.path=$storage2_orders \  # Orders path
  --log.level=$LogLevel \  # Log level
  --pieces.enable-lazy-filewalker="$Lazy_filewalker"  # Enable lazy file walker for pieces
