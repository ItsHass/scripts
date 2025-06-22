#!/bin/bash

sudo apt install -y unzip

clear

# Define array of node names
NodeNames=("2.2.1" "2.4.1")

# Download and prepare identity tool only once
curl -L https://github.com/storj/storj/releases/latest/download/identity_linux_amd64.zip -o identity_linux_amd64.zip
unzip -o identity_linux_amd64.zip
chmod +x identity
sudo mv identity /usr/local/bin/identity

# Loop through all node names
for NodeName in "${NodeNames[@]}"; do
    echo "Creating identity for node: $NodeName"
    identity create "$NodeName"
    echo "Identity created for $NodeName."
    echo "----------------------------------------------------------"
done

echo "All identities created. You still need to authorise them manually later."
