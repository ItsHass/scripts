#!/bin/bash

CHAIN="DOCKER-USER"

reset_chain() {
  echo "[*] Resetting DOCKER-USER chain..."
  iptables -F $CHAIN
  iptables -A $CHAIN -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

list_rules() {
  echo "===== DOCKER-USER RULES ====="
  iptables -L DOCKER-USER -n --line-numbers
}

allow_ip() {
  read -p "IP: " IP
  read -p "Port: " PORT

  echo "[+] Allowing $IP on port $PORT"
  iptables -I $CHAIN -s "$IP" -p tcp --dport "$PORT" -j ACCEPT
}

block_port() {
  read -p "Port to block: " PORT

  echo "[!] Blocking all other IPs on port $PORT"
  iptables -A $CHAIN -p tcp --dport "$PORT" -j DROP
}

remove_rule() {
  list_rules
  echo ""
  read -p "Enter rule line number to delete: " NUM

  echo "[*] Removing rule $NUM"
  iptables -D DOCKER-USER "$NUM"
}

pause() {
  echo ""
  read -p "Press enter to continue..."
}

while true; do
  clear
  echo "==================================="
  echo "     DOCKER FIREWALL MANAGER"
  echo "==================================="
  echo "1) Reset firewall"
  echo "2) Allow IP + Port"
  echo "3) Block Port (default deny)"
  echo "4) List rules"
  echo "5) Remove rule"
  echo "6) Exit"
  echo "==================================="
  read -p "Select option: " opt

  case $opt in
    1) reset_chain; pause ;;
    2) allow_ip; pause ;;
    3) block_port; pause ;;
    4) list_rules; pause ;;
    5) remove_rule; pause ;;
    6) exit 0 ;;
    *) echo "Invalid option"; pause ;;
  esac
done
