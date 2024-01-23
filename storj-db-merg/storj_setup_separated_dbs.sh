NodeName=storagenode2
 
docker stop $NodeName &> /dev/null
docker rm $NodeName &> /dev/null
docker pull storjlabs/storagenode:latest
 
NodeSize=3TB
Port=28968
DashPort=14003
Wallet=x
Email=x
ExtHost=x
ExtAddr=$ExtHost:$Port
 
IdentityLocation=/root/.local/share/storj/identity/storagenode2
StorageLocation=/mnt/storj/node/
 
MaxLogSize=50m
 
dbs_location=/mnt/storj_dbs/dbs/
storage2_dbs=dbs
storage2_orders=dbs/orders
 
docker run -d --restart unless-stopped --stop-timeout 300 --log-opt max-size=$MaxLogSize -p $Port:28967/udp -p $Port:28967/tcp -p $DashPort:14002 -e WALLET="$Wallet" -e EMAIL="$Email" -e ADDRESS="$ExtAddr" -e BANDWIDTH="1000TB" -e STORAGE="$NodeSize" --mount type=bind,source="$IdentityLocation",destination=/app/identity --mount type=bind,source="$StorageLocation",destination=/app/config --mount type=bind,source="$dbs_location",destination=/app/dbs --sysctl net.ipv4.tcp_fastopen=3 --name "$NodeName" storjlabs/storagenode:latest --operator.wallet-features=zksync --storage2.database-dir=$storage2_dbs --storage2.orders.path=$storage2_orders --pieces.enable-lazy-filewalker="true"
 
docker logs -f --tail 20 $NodeName
