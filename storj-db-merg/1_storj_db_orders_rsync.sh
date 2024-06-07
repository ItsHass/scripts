maindir=/mnt/storj...
from=$maindir/storage/
from1=$maindir/orders/

to=/mnt/storj_dbs/dbs
to1=/mnt/storj_dbs/dbs/orders

###rm -r /mnt/storj-4tb_dbs_orders/*
mkdir -p $to
mkdir -p $to1


###rsync -avP -m --include="*.db" --exclude="*" "$from" "$to"
rsync -aruvP -m --exclude='*/' "$from" "$to"
rsync -aruvP "$from1" "$to1"
