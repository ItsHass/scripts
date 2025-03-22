#!/bin/bash

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo: sudo bash setup-vbox-shared-folder.sh"
    exit 1
fi

echo "Updating system and installing required packages..."
apt update && apt upgrade -y
apt install -y build-essential dkms linux-headers-$(uname -r)

echo "Mounting VirtualBox Guest Additions ISO..."
VBOX_ISO="/dev/sr0"
VBOX_MOUNT="/mnt/cdrom"

mkdir -p "$VBOX_MOUNT"

#if [ ! -f "$VBOX_ISO" ]; then
#    echo "Error: Guest Additions ISO not found. Please insert the ISO in VirtualBox."
#    exit 1
#fi

mount -o loop "$VBOX_ISO" "$VBOX_MOUNT"
bash "$VBOX_MOUNT/VBoxLinuxAdditions.run" --nox11
umount "$VBOX_MOUNT"
rm -rf "$VBOX_MOUNT"

echo "Adding current user to the vboxsf group..."
usermod -aG vboxsf $USER

echo "Creating mount point for shared folder..."
SHARED_FOLDER="/mnt/shared"
mkdir -p "$SHARED_FOLDER"

echo "Mounting shared folder (replace 'SharedFolder' with your actual folder name)..."
mount -t vboxsf SharedFolder "$SHARED_FOLDER"

echo "Setup complete! Please reboot the VM for changes to take effect."
