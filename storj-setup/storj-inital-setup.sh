identityLoc=/
storageLoc=/

docker run --rm -e SETUP="true" \
    --user $(id -u):$(id -g) \
    --mount type=bind,source="$identityLoc",destination=/app/identity \
    --mount type=bind,source="$storageLoc",destination=/app/config \
    --name storagenode storjlabs/storagenode:latest
