from=/mnt/storj-4tb/node/storage/
from1=/mnt/storj-4tb/node/orders/
rm -r /mnt/storj-4tb_dbs_orders/*
mkdir -p /mnt/storj-4tb_dbs_orders/dbs/
mkdir -p /mnt/storj4-tb_dbs_orders/dbs/orders/
to=/mnt/storj-4tb_dbs_orders/dbs
to1=/mnt/storj-4tb_dbs_orders/dbs/orders

#rsync -avP -m --include="*.db" --exclude="*" "$from" "$to"
rsync -aruvP -m --exclude='*/' "$from" "$to"
rsync -aruvP "$from1" "$to1"
