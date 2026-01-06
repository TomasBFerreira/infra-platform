#!/bin/bash

# Entrypoint script for Ansible container
# Fixes SSH key formatting issues before running commands

set -e

# Function to fix SSH key line endings
fix_ssh_key() {
    local key_file="$1"
    
    if [ -f "$key_file" ]; then
        # Check if the file has carriage returns (Windows line endings)
        if file "$key_file" | grep -q CRLF; then
            echo "Fixing line endings in: $key_file"
            sed -i 's/\r$//' "$key_file"
        fi
        
        # Verify the key format
        if ! ssh-keygen -l -f "$key_file" &> /dev/null; then
            echo "Warning: SSH key format may be invalid: $key_file"
        fi
    fi
}

# Fix all SSH keys in /root/ssh directory
if [ -d "/root/ssh" ]; then
    echo "Checking SSH keys in /root/ssh..."
    for key_file in /root/ssh/*_id_ed25519; do
        if [ -f "$key_file" ]; then
            fix_ssh_key "$key_file"
        fi
    done
    
    # Also check RSA keys
    for key_file in /root/ssh/*_id_rsa; do
        if [ -f "$key_file" ]; then
            fix_ssh_key "$key_file"
        fi
    done
fi

# Execute the passed command
exec "$@"
