#!/bin/bash

# Allow STORJ ports through the firewall
iptables -D INPUT -p tcp -m state --state NEW --dport 28922 -j ACCEPT
iptables -D INPUT -p udp --dport 28922 -j ACCEPT

# DNAT Storj ports to the client on the other side of the tunnel
iptables -t nat -D PREROUTING -p tcp --dport 28922 -j DNAT --to-destination 10.0.0.x:28922
iptables -t nat -D PREROUTING -p udp --dport 28922 -j DNAT --to-destination 10.0.0.x:28922
