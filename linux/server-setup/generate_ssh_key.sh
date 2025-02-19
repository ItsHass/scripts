#!/bin/bash

# Function to list system users and allow selection
select_user() {
    echo "Available users:"
    getent passwd | awk -F: '$3 >= 1000 {print $1}' # Lists non-system users
    echo
    read -p "Enter the username to assign the key to: " ssh_user
    if id "$ssh_user" &>/dev/null; then
        echo "User selected: $ssh_user"
    else
        echo "Invalid user. Exiting."
        exit 1
    fi
}

# Function to create an RSA key
generate_key() {
    read -p "Enter key name (without extension): " key_name
    echo "Select key format:"
    echo "1) OpenSSH (.key) - Compatible with PowerShell"
    echo "2) PuTTY (.ppk) - Compatible with PuTTY"
    read -p "Enter choice (1 or 2): " key_format

    if [ "$key_format" == "1" ]; then
        ssh-keygen -t rsa -b 4096 -f "$HOME/$key_name.key" -N ""
        echo "Key generated: $HOME/$key_name.key"
    elif [ "$key_format" == "2" ]; then
        ssh-keygen -t rsa -b 4096 -f "$HOME/$key_name" -N ""
        sudo apt-get install -y putty-tools
        puttygen "$HOME/$key_name" -o "$HOME/$key_name.ppk"
        echo "Key generated: $HOME/$key_name.ppk"
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi
}

# Function to add the public key to the selected user
add_key_to_user() {
    mkdir -p "/home/$ssh_user/.ssh"
    cat "$HOME/$key_name.pub" >> "/home/$ssh_user/.ssh/authorized_keys"
    chown -R "$ssh_user:$ssh_user" "/home/$ssh_user/.ssh"
    chmod 700 "/home/$ssh_user/.ssh"
    chmod 600 "/home/$ssh_user/.ssh/authorized_keys"
    echo "Public key added to /home/$ssh_user/.ssh/authorized_keys"
}

# Main execution
select_user
generate_key
add_key_to_user
echo "Setup complete! You can now use the private key to connect via SSH."
