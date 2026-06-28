mkdir wireguard-setup; cd wireguard-setup;
wget https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/wireguard-setup/server-step1.sh https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/wireguard-setup/new-peer.sh https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/wireguard-setup/wg-port-manager.sh
cd ../; mkdir ufw; cd ufw; 
wget https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/ufw/v2/ufw-run.sh https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/ufw/v2/ufw-reconciler.sh https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/ufw/v2/ufw-feeder-anyport.sh https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/ufw/v2/ufw-feeder-1.sh https://github.com/ItsHass/scripts/raw/refs/heads/main/linux/ufw/docker-firewall.sh
chmod 777 *


##---- ufw rules --- 
##*/15 * * * * cd /root/ufw; bash ufw-run.sh
