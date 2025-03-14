DockerRemoveName=storagenode
DockerName=storagenode

docker stop $DockerRemoveName &> /dev/null
docker rm $DockerRemoveName &> /dev/null
docker pull storjlabs/storagenode:latest

NodeSize=3.5TB
Port=28969
DashPort=14002
Wallet=xxxxxxxxxxxxxxxxx
Email=xxxxxxxxxxxxxxxxxx

Domain=....
Windscribe_Port=....
ExtAddr=$Domain:$Windscribe_Port

IdentityLocation=/mnt/location
StorageLocation=/mnt/location

dbs_location=/mnt/storj_dbs/dbs/
storage2_dbs=dbs
storage2_orders=dbs/orders

MaxLogSize=10m

LogLevel=error
CustomLog=piecestore=WARN

HashStoreDIR=/mnt/disk

docker run -d --restart unless-stopped --stop-timeout 300 --log-opt max-size=$MaxLogSize -p $Port:28967/udp -p $Port:28967/tcp -p $DashPort:14002 -e WALLET="$Wallet" -e EMAIL="$Email" -e ADDRESS="$ExtAddr" -e BANDWIDTH="1000TB" -e STORAGE="$NodeSize" --mount type=bind,source="$HashStoreDIR",destination=/app/config/storage/hashstore --mount type=bind,source="$IdentityLocation",destination=/app/identity --mount type=bind,source="$StorageLocation",destination=/app/config --mount type=bind,source="$dbs_location",destination=/app/dbs --sysctl net.ipv4.tcp_fastopen=3 --name $DockerName storjlabs/storagenode:latest --storage2.database-dir=$storage2_dbs --storage2.orders.path=$storage2_orders --log.level=$LogLevel --log.custom-level=$CustomLog --pieces.enable-lazy-filewalker="true"

docker logs $DockerName -f --tail 10
