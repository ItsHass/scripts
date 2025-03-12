# Variables for Docker storage node setup

DockerRemoveName=storagenode
DockerName=storagenode

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

$storage2_dedicatedDisk=true
$storage2_dedicatedDisk_reservedBytes=100GB

MaxLogSize=10m

LogLevel=error
CustomLog=piecestore=WARN

HashStoreDIR=/mnt/hashstore
filestatcacheDIR=/mnt/filestatcache
