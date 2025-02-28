# Main script: run.sh

# Source the variables from the external file
source ./variables.sh

# Stop and remove the existing Docker container
docker stop $DockerRemoveName &> /dev/null
docker rm $DockerRemoveName &> /dev/null

# Pull the latest Docker image
docker pull storjlabs/storagenode:latest

# Run the Docker container
docker run -d \
  --restart unless-stopped \
  --stop-timeout 300 \
  --log-opt max-size=$MaxLogSize \
  -p $Port:28967/udp \
  -p $Port:28967/tcp \
  -p $DashPort:14002 \
  -e WALLET="$Wallet" \
  -e EMAIL="$Email" \
  -e ADDRESS="$ExtAddr" \
  -e BANDWIDTH="1000TB" \
  -e STORAGE="$NodeSize" \
  --mount type=bind,source="$HashStoreDIR",destination=/app/config/storage/hashstore \
  --mount type=bind,source="$filestatcacheDIR",destination=/app/config/storage/filestatcache \
  --mount type=bind,source="$IdentityLocation",destination=/app/identity \
  --mount type=bind,source="$StorageLocation",destination=/app/config \
  --mount type=bind,source="$dbs_location",destination=/app/dbs \
  --sysctl net.ipv4.tcp_fastopen=3 \
  --name $DockerName \
  storjlabs/storagenode:latest \
  --storage2.monitor.verify-dir-readable-timeout=5m \
  --storage2.monitor.verify-dir-readable-interval=5m \
  --storage2.monitor.verify-dir-writable-timeout=5m \
  --storage2.database-dir=$storage2_dbs \
  --storage2.orders.path=$storage2_orders \
  --log.level=$LogLevel \
  --log.custom-level=$CustomLog \
  --pieces.enable-lazy-filewalker="true"

# Tail the logs for the Docker container
docker logs $DockerName -f --tail 10
