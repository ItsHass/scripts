#!/bin/bash
clear
echo Running Sync 1

date

echo Running Sync 1 >> /mnt/xxx/sync.log
date >> /mnt/xxx/sync.log

rsync -auh --delete --progress /mnt/xxx/node/ /mnt/xxx/node/ >> /mnt/xxx/sync_1.log

echo Sync 1 Finished
echo Sync 1 Finished >> /mnt/xxx/sync.log
date
date >> /mnt/xxx/sync.log

echo sleeping 5 seconds
sleep 5

echo -------
date
echo Running Sync 2
echo Running Sync 2 >> /mnt/xxx/sync.log
date >> /mnt/xxx/sync.log

rsync -auh --delete --progress /mnt/xxx/node/ /mnt/xxx/node/ >> /mnt/xxx/sync_2.log

echo Sync 2 Finished
echo Sync 2 Finished >> /mnt/xxx/sync.log
date
date >> /mnt/xxx/sync.log

echo finished 2 x syncs

echo finished 2 x syncs >> /mnt/xxx/sync.log
