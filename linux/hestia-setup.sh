#!/bin/bash

clear

read -p "Enter Hestia Admin PW: " HestiaPW
read -p "Enter Hestia Admin Email: " HestiaEmail

wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh

sudo bash hst-install.sh --port '8083' --lang 'en' --email '$HestiaEmail' --password '$HestiaPW' --apache no --phpfpm yes --multiphp yes --vsftpd yes --proftpd no --named yes --mariadb yes --mysql8 no --postgresql no --exim yes --dovecot yes --sieve no --clamav yes --spamassassin yes --iptables yes --fail2ban yes --quota yes --api yes --interactive yes --force no

echo "======= completed ======="
