#!/bin/bash
#ens19_IP_Change.sh
clear

read -p "Enter ENS 18 IP Address (static): 192...." IPaddr1
read -p "Enter ENS 19 IP Address (static): 10....." IPaddr2

rm /etc/netplan/00-installer-config.yaml

echo "# This is the network config written by 'subiquity'
network:
  ethernets:
    ens18:
      dhcp4: false
      addresses:
      - $IPaddr1/24
      routes:
      - to: default
        via: 192.168.0.1
    ens19:
      addresses:
      - $IPaddr2/24
      nameservers:
        addresses: []
        search: []
  version: 2 " > /etc/netplan/00-installer-config.yaml
  
  echo "Added New Config"
  
  echo "Applying Change"
  netplan apply
  echo "Completed"
  
  ip -4 -br addr show
