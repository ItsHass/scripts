#!/bin/bash

set -e

echo "===== Disk usage before ====="
df -h
echo

echo "===== Cleaning apt cache ====="
apt clean
apt autoclean -y

echo "===== Removing unused packages ====="
apt autoremove --purge -y

echo "===== Removing old crash reports ====="
rm -f /var/crash/*

echo "===== Cleaning journal logs ====="
journalctl --vacuum-time=7d
journalctl --vacuum-size=200M

echo "===== Cleaning temporary files ====="
rm -rf /tmp/*
rm -rf /var/tmp/*

echo "===== Removing old kernels ====="
CURRENT_KERNEL=$(uname -r)

dpkg --list | awk '/linux-image-[0-9]/{ print $2 }' | while read pkg; do
    if [[ "$pkg" != *"$CURRENT_KERNEL"* ]]; then
        echo "Removing $pkg"
        apt purge -y "$pkg" || true
    fi
done

echo "===== Cleaning old headers ====="
dpkg --list | awk '/linux-headers-[0-9]/{ print $2 }' | while read pkg; do
    if [[ "$pkg" != *"$CURRENT_KERNEL"* ]]; then
        apt purge -y "$pkg" || true
    fi
done

if command -v docker &>/dev/null; then
    echo "===== Docker cleanup ====="
    docker system prune -af --volumes || true
fi

echo "===== Final autoremove ====="
apt autoremove --purge -y

echo "===== Disk usage after ====="
df -h

echo "Cleanup complete."
