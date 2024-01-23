DockerContainerName=storagenode

docker stop $DockerContainerName &> /dev/null
docker rm $DockerContainerName &> /dev/null
docker pull storjlabs/storagenode:latest

NodeSize=3.3TB
Port=28969
DashPort=14002
Wallet=xxxxx
Email=xxxxxx
ExtHost=svr01.domain.com
ExtAddr=$ExtHost:$Port
 
IdentityLocation=/mnt/storj/_identity-backup/storj/identity/storagenode/
StorageLocation=/mnt/storj/node/
 
MaxLogSize=50m
 
docker run -d --restart unless-stopped --stop-timeout 300 --log-opt max-size=$MaxLogSize -p $Port:28967/udp -p $Port:28967/tcp -p $DashPort:14002 -e WALLET="$Wallet" -e EMAIL="$Email" -e ADDRESS="$ExtHost:$Port" -e BANDWIDTH="1000TB" -e STORAGE="$NodeSize" --mount type=bind,source="$IdentityLocation",destination=/app/identity --mount type=bind,source="$StorageLocation",destination=/app/config --sysctl net.ipv4.tcp_fastopen=3 --name storagenode storjlabs/storagenode:latest --operator.wallet-features=zksync --pieces.enable-lazy-filewalker="true"
