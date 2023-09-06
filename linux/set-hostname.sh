#!/bin/bash
#set-hostname.sh

clear

read -p "Enter Hostname: " HName

sudo hostnamectl set-hostname $HName

echo "set hostname"

sudo rm /etc/hosts
sudo echo "127.0.0.1 localhost
127.0.1.1 $HName

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
" > /etc/hosts

echo "added hosts file"

hostnamectl
