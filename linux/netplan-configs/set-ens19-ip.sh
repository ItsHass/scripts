#!/bin/bash
#ens19_IP_Change.sh
clear

read -p "Enter IP Address: " IPaddr

rm /etc/netplan/00-installer-config.yaml

echo "# This is the network config written by 'subiquity'
network:
  ethernets:
    ens18:
      dhcp4: true
    ens19:
      addresses:
      - $IPaddr/24
      nameservers:
        addresses: []
        search: []
  version: 2 " > /etc/netplan/00-installer-config.yaml
  
  echo "Added New Config"
  
  echo "Applying Change"
  netplan apply
  echo "Completed"
  
  ip -4 -br addr show
