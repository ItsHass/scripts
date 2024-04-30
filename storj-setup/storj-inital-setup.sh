identityLoc=
storageLoc=
dbs_location=
storj_name=

docker run --rm -e SETUP="true" \
    --user $(id -u):$(id -g) \
    --mount type=bind,source="$identityLoc",destination=/app/identity \
    --mount type=bind,source="$storageLoc",destination=/app/config \
    --mount type=bind,source="$dbs_location",destination=/app/dbs \
    --name $storj_name storjlabs/storagenode:latest

