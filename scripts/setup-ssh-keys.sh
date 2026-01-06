#!/bin/bash

# Setup SSH keys from Vault
# This script retrieves SSH keys from Vault and stores them with correct formatting
# Usage: ./scripts/setup-ssh-keys.sh [PROJECT_NAME]
# If no PROJECT_NAME is provided, all known projects are set up

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# SSH keys directory
SSH_DIR="$HOME/ssh"
mkdir -p "$SSH_DIR"

# Function to setup a single SSH key
setup_ssh_key() {
    local project="$1"
    local vault_path="secret/ssh_keys/${project}_worker"
    local key_file="$SSH_DIR/${project}_worker_id_ed25519"
    
    echo "Setting up SSH key for: $project"
    
    # Check if Vault is accessible
    if ! vault status &> /dev/null; then
        echo "Error: Vault is not accessible at $VAULT_ADDR"
        return 1
    fi
    
    # Retrieve the private key from Vault
    if ! vault kv get -field=private "$vault_path" > "$key_file" 2>/dev/null; then
        echo "Error: Could not retrieve SSH key from $vault_path"
        return 1
    fi
    
    # Check if file is empty
    if [ ! -s "$key_file" ]; then
        echo "Error: SSH key file is empty"
        rm -f "$key_file"
        return 1
    fi
    
    # Fix line endings (remove Windows-style CRLF, keep Unix-style LF)
    sed -i 's/\r$//' "$key_file"
    
    # Set correct permissions
    chmod 600 "$key_file"
    
    # Verify the key format
    if ! ssh-keygen -l -f "$key_file" &> /dev/null; then
        echo "Error: SSH key format is invalid"
        rm -f "$key_file"
        return 1
    fi
    
    echo "✓ SSH key for $project stored at: $key_file"
    return 0
}

# Main logic
if [ -z "$1" ]; then
    # Setup all known projects
    projects=("infra-lxc" "network-vm" "media-stack")
else
    # Setup specific project
    projects=("$1")
fi

# Check for required commands
if ! command -v vault &> /dev/null; then
    echo "Error: vault CLI is not installed or not in PATH"
    exit 1
fi

if ! command -v ssh-keygen &> /dev/null; then
    echo "Error: ssh-keygen is not installed or not in PATH"
    exit 1
fi

# Ensure Vault environment variables are set
if [ -z "$VAULT_ADDR" ]; then
    echo "Error: VAULT_ADDR environment variable is not set"
    exit 1
fi

if [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_TOKEN environment variable is not set"
    exit 1
fi

# Setup SSH keys for each project
failed=0
for project in "${projects[@]}"; do
    if ! setup_ssh_key "$project"; then
        failed=$((failed + 1))
    fi
done

if [ $failed -gt 0 ]; then
    echo "Failed to setup $failed SSH key(s)"
    exit 1
fi

echo ""
echo "All SSH keys have been successfully retrieved and configured!"
echo "SSH keys directory: $SSH_DIR"
ls -lh "$SSH_DIR" | grep "_worker_id_ed25519" || echo "No SSH keys found"
