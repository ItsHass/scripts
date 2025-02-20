#!/bin/bash

LOGFILE="/var/log/system_cleanup.log"

echo "==== System Cleanup Started on $(date) ====" | tee -a $LOGFILE

# Update package lists
echo "Updating package lists..." | tee -a $LOGFILE
sudo apt update >> $LOGFILE 2>&1

# Upgrade installed packages
echo "Upgrading installed packages..." | tee -a $LOGFILE
sudo apt full-upgrade -y >> $LOGFILE 2>&1

# Firmware updates
echo "Checking and updating firmware..." | tee -a $LOGFILE
sudo fwupdmgr refresh >> $LOGFILE 2>&1
sudo fwupdmgr get-updates >> $LOGFILE 2>&1
sudo fwupdmgr update -y >> $LOGFILE 2>&1

# Remove unnecessary packages
echo "Removing unused dependencies..." | tee -a $LOGFILE
sudo apt autoremove -y >> $LOGFILE 2>&1

# Clean up APT cache
echo "Cleaning up APT cache..." | tee -a $LOGFILE
sudo apt autoclean >> $LOGFILE 2>&1
sudo apt clean >> $LOGFILE 2>&1

# Remove old kernels (Optional: Uncomment to enable)
# echo "Removing old kernels..." | tee -a $LOGFILE
# sudo apt purge $(dpkg --list | grep -E '^ii  linux-(image|headers)-[0-9]+' | awk '{print $2}' | grep -v $(uname -r | cut -d'-' -f1,2)) -y >> $LOGFILE 2>&1

echo "==== System Cleanup Completed on $(date) ====" | tee -a $LOGFILE
