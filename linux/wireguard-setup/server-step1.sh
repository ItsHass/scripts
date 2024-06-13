#!/bin/bash
# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please run with sudo."
  exit 1
fi

# If the user is root, proceed with the rest of the script
echo "Running with root privileges..."

sudo apt update

#install wireguard
sudo apt install wireguard -y

#variables
WGpublickey_path=/etc/wireguard/public.key
WGprivatekey_path=/etc/wireguard/private.key

#generate private key
wg genkey | sudo tee $WGprivatekey_path
#set private key permissions
sudo chmod go= $WGprivatekey_path
#generate public key
sudo cat $WGprivatekey_path | wg pubkey | sudo tee $WGpublickey_path

#variables
WGServer_pubKey=$(cat "$WGpublickey_path")
WGServer_privKey=$(cat "$WGprivatekey_path")
WGServer_port="51820"
WGServer_ipRange="10.8.0.1/24"

# Define the target file
target_file="/etc/wireguard/wg0.conf"

# Use a here document to write the content to the file
cat <<EOF > "$target_file"
[Interface]
PrivateKey = $WGServer_privKey
Address = $WGServer_ipRange
ListenPort = $WGServer_port
SaveConfig = true
EOF

# Optionally, print a message to indicate success
echo "wg0 Configuration written to $target_file"

# Define the sysctl configuration file
sysctl_conf="/etc/sysctl.conf"

# Define the setting to enable IP forwarding
setting="net.ipv4.ip_forward=1"

# Check if the setting is already present in the file
if grep -q "^$setting" "$sysctl_conf"; then
    # If the setting is present, update it
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' "$sysctl_conf"
else
    # If the setting is not present, add it to the end of the file
    echo "$setting" >> "$sysctl_conf"
fi

# Apply the changes
if sysctl -p >/dev/null 2>&1; then
    # If the changes were applied successfully, print a success message
    echo "IP forwarding has been enabled."
else
    # If there was an error, print an error message
    echo "Error: Unable to enable IP forwarding."
    exit 1
fi

# Extract the IP address and subnet mask from the range
ip_address=$(echo "$WGServer_ipRange" | cut -d'/' -f1)
subnet_mask=$(echo "$WGServer_ipRange" | cut -d'/' -f2)

# Split the IP address into octets
IFS='.' read -r -a octets <<< "$ip_address"

# Increment the last octet by one
last_octet=$(( ${octets[3]} + 1 ))

# Construct the next IP address
next_ip="${octets[0]}.${octets[1]}.${octets[2]}.$last_octet"

# Define the text to append
additional_text="
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
PreUp = iptables -t nat -I PREROUTING -p tcp --dport 28967 -j DNAT --to-destination $next_ip:28967
PreUp = iptables -t nat -I PREROUTING -p udp --dport 28967 -j DNAT --to-destination $next_ip:28967
PostDown = iptables -t nat -D PREROUTING -p tcp --dport 28967 -j DNAT --to-destination $next_ip:28967
PostDown = iptables -t nat -D PREROUTING -p udp --dport 28967 -j DNAT --to-destination $next_ip:28967
"

# Append the text to the configuration file
if echo "$additional_text" >> "$target_file"; then
    # If the text was successfully appended, print a success message
    echo "iptables config appended to $target_file"
else
    # If there was an error, print an error message
    echo "Error: Failed to append config to $target_file"
    exit 1
fi
#SERVER SUMMARY#
# Function to print a centered string
print_centered() {
    # Calculate the width of the terminal
    term_width=$(tput cols)

    # Calculate the length of the string
    str_length=${#1}

    # Calculate the padding on the left side
    pad_left=$(( (term_width - str_length) / 2 ))

    # Print the padding on the left side
    printf "%${pad_left}s" "$1"
}

# Print the summary with centered formatting
echo "** Summary **"
echo
print_centered "Your Server Public Key: $WGServer_pubKey"
echo
print_centered "Your Server Private Key: $WGServer_privKey"
echo
print_centered "Your Server Port: $WGServer_port"
echo
print_centered "IP Range: $WGServer_ipRange"
echo
print_centered "Config Location: $target_file"
echo
print_centered "Storj Forwarding IP: $next_ip"
echo
print_centered "Storj Forwarding Port: 28967"

# Pause the script until the user presses another key
echo -e "\n\n\n"
echo "**NOTE: Server configuration is finished at this point."
echo
read -n 1 -s -r -p "Please now follow on using client-step1.sh on the Client device."


## now to configure client WG ##
## client-step1.sh
