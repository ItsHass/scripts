#!/bin/bash

# Define base directory
BASE_DIR="/home/ubuntu"

# Function to download files
download_file() {
    local url="$1"
    local dest="$2"
    
    echo "Downloading $url to $dest"
    curl -L -o "$dest" "$url"
    chmod +x "$dest"
}

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Step 1: Download and store hostname setup script
download_file "https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/set-hostname.sh" "$BASE_DIR/set-hostname.sh"
download_file "https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/docker-add-normal-user.sh" "$BASE_DIR/docker-add-normal-user.sh"

# Step 2: Create required directories
mkdir -p "$BASE_DIR/storj/auth"
mkdir -p "$BASE_DIR/storj/2025"

# Step 3: Download files into appropriate locations
download_file "https://github.com/ItsHass/scripts/raw/refs/heads/main/storj-setup/new-identity.sh" "$BASE_DIR/storj/auth/new-identity.sh"
download_file "https://github.com/ItsHass/scripts/raw/refs/heads/main/storj-setup/new-auth.sh" "$BASE_DIR/storj/auth/new-auth.sh"
download_file "https://github.com/ItsHass/scripts/raw/refs/heads/main/storj-setup/storj-inital-setup.sh" "$BASE_DIR/storj/storj-inital-setup.sh"
download_file "https://github.com/ItsHass/scripts/raw/refs/heads/main/storj-setup/2025/standard-02-2025.sh" "$BASE_DIR/storj/2025/standard-02-2025.sh"
download_file "https://github.com/ItsHass/scripts/raw/refs/heads/main/storj-setup/2025/standard-variables.sh" "$BASE_DIR/storj/2025/standard-variables.sh"


# Final message
echo "Setup complete. You can now run the hostname script:"
echo "sudo bash /home/ubuntu/set-hostname.sh"
