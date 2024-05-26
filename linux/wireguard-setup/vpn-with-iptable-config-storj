## DNAT with iptables over wireguard hosted on a VPS to host services behind a firewall/GNAT.

This is a short description of how to host services, using [STORJ node](https://www.storj.io/node) as an example, on a host behind GNAT, or otherwise restrictive firewall, by forwarding packets through WireGuard endpoint on a relatively fast nearby VPS. This is not specific to Storj, and can be adopted to hosting other services.

As an example we will use an Oracle Cloud instance. Free tier still provides 10TB of monthly traffic that is sufficient for most node operators. Just make sure to create an account in a closest datacenter to minimize extra latency. 

### Notes on configuring the cloud instance

1. Create the oracle compute instance (ideally, Ampere, because they are awesome, but if that is not availabe, any other will do too). 
2. Pick any OS you prefer, here we'll describe Ubuntu, as a most popular one.
3. Configure public IP address (this is the default), and upload SSH key to access the instance.
4. Then edit the `Ingress Rules` in the Default Security List in the VCN associated with the instance and rules to allow:
    - Traffic from anywhere `0.0.0.0/0`, any port, to destination port `28967`, one for udp, one for tcp. This is for storj. 
    - UDP to port `51820`, for WireGuard. It does not need to be this specific port, any will do, just adjust the rest accordingly. The source network can also be narrowed down to your ISP's address range, if desired. 
    
       | Statless | Source  | IP Protocol | Source Port Range | Destination Port Range | Type and Code | Allows | Description|
       |----------|---------|-------------|-------------------|------------------------|---------------|--------|------------|
       | No | 0.0.0.0/0 | TCP | All | 28967| |TCP Traffic for port 28967 | Storj TCP|
       | No | 0.0.0.0/0 | UDP | All | 28967| |UDP Traffic for port 28967 | Storj UDP|
       | No | 0.0.0.0/0 | UDP | All | 51820| |UDP Traffic for port 51820 | Wireguard|
    
   That's all that needs to be done in Oracle console.


5. Optionaly, configure the public IP as an A record on your DNS provider, to use DNS name and not an ugly IP address in the subsequent configuration and in your storj node.

### Installing and configuring wireguard tunnel

1. ssh to your new instance, update software, and install wireguard: 

    ```bash
    sudo apt update && sudo apt upgrade
    sudo reboot
    sudo apt install wireguard -y
    ```
    
2. Configure wireguard tunnel between your node and VPS. There are tons of tutorials, here are the steps for reference: 

    On the VPS: 
    1. Initialize the config file
       ```bash
       (umask 077 && printf "[Interface]\nPrivateKey= " | sudo tee /etc/wireguard/wg0.conf > /dev/null)
       wg genkey | sudo tee -a /etc/wireguard/wg0.conf | wg pubkey | sudo tee /etc/wireguard/publickey
       ```
    2. Add peer information (public key and address) after configuing it below
    3. Enable ipv4 forwarding: in `/etc/sysctl.conf` uncomment 
       ```ini
       # Uncomment the next line to enable packet forwarding for IPv4
       net.ipv4.ip_forward=1   
       ```
       and for the change to take effect load it: 
       ```bash
       sudo sysctl -p
       ```
       Note: it is possible to configure this key in a number of other configuration files, see `man sysctl`, but in this case either provide path to file to `-p` argument or simply use `sudo sysctl --system`, that will parse all configuration files.
         
    3. Enable and start the wireguard service:
       ```bash
       sudo systemctl enable wg-quick@wg0
       sudo systemctl start wg-quick@wg0
       ```
         
    On the client, assuming it's a TrueNAS, and storj runs in the jail, we would need few things:
    
    1. In the jail properties tick the `allow_tun` flag. (e.g. `iocage set allow_tun=1 jailname`)
    2. On the host under System -> Tunables add `LOADER` variable `if_wg_load` with the value `YES`, to load wireguard kernel module.
    4. Initialize the wireguard config file and create keys just like above, noting that in FreeBSD the default configuration file location is `/usr/local/etc/wireguard/wg0.conf`
    3. In the jail, in the `/etc/rc.conf` add
       ```ini
       wireguard_enable="YES"
       wireguard_interfaces="wg0"
       ```
    
    Generally, the config files shall look like so: 
    1. On the server: `/etc/wireguard/wg0.conf`
        ```ini
        [Interface]
        PrivateKey = <server private key>

        ListenPort = 51820
        Address = 10.0.60.1
        
        # Allow WireGuard through the firwall
        PreUp = iptables -I INPUT 6 -p udp --dport 51820 -j ACCEPT
        PostDown = iptables -D INPUT -p udp --dport 51820 -j ACCEPT

        [Peer]
        PublicKey = <client public key>
        AllowedIPs = 10.0.60.2/32
        ```
        
    2. On the client: `/usr/local/etc/wireguard/wg0.conf`
        ```ini
        [Interface]
        PrivateKey = <client private key>
        Address = 10.0.60.2
        
        [Peer]
        PublicKey = <server public key>
        AllowedIPs = 10.0.60.1/32
        Endpoint = sub.example.com:51820
        PersistentKeepalive = 25
        ```
     3. Start the service on the client: 
         ```bash 
         service wireguard start
         ```
         
     At this point the client shall be able to ping the server, and the server shall be able to ping the clinet, at `10.0.60.1` and `10.0.60.2` addresses, respectively. 
     
### Packet forwarding

Now the very last thing, the meat of this tutorial. In the `[Interface]` section on the server in the `/etc/wireguard/wg0.conf` add the following `PreUp` and `PostDown` rules (PostDown rules are copies of PreUp rules, but with  `-A` or `-I` options replaced with `-D`, to delete the rule):

```ini
# Allow forwarding to and from wireguard interface
PreUp = iptables -I FORWARD -i %i -j ACCEPT
PreUp = iptables -I FORWARD -o %i -j ACCEPT
PostDown = iptables -D FORWARD -i %i -j ACCEPT
PostDown = iptables -D FORWARD -o %i -j ACCEPT

# Turn on masquarading
PreUp = iptables -t nat -I POSTROUTING -o %i -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE


# Note: in the next session we are inserting the rules below at position 6, before the default REJECT rule present on Oracle VMS. Your VPS may have similar default rules; adjust accordingly. 

# Allow Wireguard ports through the firewall
PreUp = iptables -I INPUT 6 -p udp --dport 51820 -j ACCEPT
PostDown = iptables -D INPUT -p udp --dport 51820 -j ACCEPT

# Allow STORJ ports through the firewall
PreUp = iptables -I INPUT 6 -p tcp -m state --state NEW --dport 28967 -j ACCEPT
PreUp = iptables -I INPUT 6 -p udp --dport 28967 -j ACCEPT
PostDown = iptables -D INPUT -p tcp -m state --state NEW --dport 28967 -j ACCEPT
PostDown = iptables -D INPUT -p udp --dport 28967 -j ACCEPT

# Any other ports for additinal applications can be added similarly.
# ...

# DNAT Storj ports to the client on the other side of the tunnel
PreUp = iptables -t nat -I PREROUTING -p tcp --dport 28967 -j DNAT --to-destination 10.0.60.2:28967
PreUp = iptables -t nat -I PREROUTING -p udp --dport 28967 -j DNAT --to-destination 10.0.60.2:28967
PostDown = iptables -t nat -D PREROUTING -p tcp --dport 28967 -j DNAT --to-destination 10.0.60.2:28967
PostDown = iptables -t nat -D PREROUTING -p udp --dport 28967 -j DNAT --to-destination 10.0.60.2:28967
```

These acomplish few things: 

1. Allow traffic to Wireguard port, so that your server can connect to establish the tunnel .
2. Allow new tcp and udp connections to Storj port (note inserting the rule before rule 6, on oracle instances rule 6 is reject).
2. Allow Storj packet forwarding to wireguard interface.
3. Turn on masquarading, to facilitate the correct routing of response packets. 
 

On the server, restart the wireguard service: 
```bash
sudo systemctl restart wg-quick@wg0
```

On the client, restart the wireguard service:
```bash
service wireguard restart
```

In the `config.yaml` of the storage node modify the external address to point to your vps:

```yaml
# the public address of the node, useful for nodes behind NAT
contact.external-address: sub.example.com:28967
```

[Re]start the node, and check the status page. It shall be now happily connected.
