#!/bin/bash

set -e

# Vault Secrets Setup Script
# Sets up SSH keys and other secrets needed for infrastructure

echo "========================================="
echo "Vault Secrets Setup"
echo "========================================="

# Configuration
VAULT_ADDR="http://localhost:8200"
VAULT_TOKEN="myroot"

# Check Vault is running
echo "Checking Vault connection..."
curl -s "$VAULT_ADDR/v1/sys/health" > /dev/null
if [ $? -ne 0 ]; then
    echo "❌ Vault is not running at $VAULT_ADDR"
    echo "Please start Vault first"
    exit 1
fi

echo "✅ Vault is running"

# Check if we can authenticate
echo "Checking Vault authentication..."
curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/token/lookup-self" > /dev/null
if [ $? -ne 0 ]; then
    echo "❌ Cannot authenticate with Vault"
    echo "Please check VAULT_TOKEN"
    exit 1
fi

echo "✅ Vault authentication successful"

# Create SSH keys for media-stack
echo ""
echo "Creating SSH keys for media-stack..."
SSH_KEY_PATH="$HOME/.ssh/media-stack_worker_id_ed25519"

if [ ! -f "$SSH_KEY_PATH" ]; then
    ssh-keygen -t ed25519 -N "" -f "$SSH_KEY_PATH"
    echo "✅ SSH keys created at $SSH_KEY_PATH"
else
    echo "✅ SSH keys already exist at $SSH_KEY_PATH"
fi

# Read SSH keys
SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH.pub")
SSH_PRIVATE_KEY=$(cat "$SSH_KEY_PATH")

# Store SSH keys in Vault
echo ""
echo "Storing SSH keys in Vault..."

# Store media-stack SSH keys (properly escaped)
SSH_PUBLIC_ESCAPED=$(printf '%s' "$SSH_PUBLIC_KEY" | jq -Rs .)
SSH_PRIVATE_ESCAPED=$(printf '%s' "$SSH_PRIVATE_KEY" | jq -Rs .)

curl -s -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"public\":$SSH_PUBLIC_ESCAPED,\"private\":$SSH_PRIVATE_ESCAPED}}" \
    "$VAULT_ADDR/v1/secret/data/ssh_keys/media-stack_worker"

if [ $? -eq 0 ]; then
    echo "✅ Media-stack SSH keys stored in Vault"
else
    echo "❌ Failed to store media-stack SSH keys"
    exit 1
fi

# Create SSH keys for network-vm if needed
NETWORK_VM_SSH_PATH="$HOME/.ssh/network-vm_id_ed25519"
if [ ! -f "$NETWORK_VM_SSH_PATH" ]; then
    ssh-keygen -t ed25519 -N "" -f "$NETWORK_VM_SSH_PATH"
    echo "✅ Network-VM SSH keys created at $NETWORK_VM_SSH_PATH"
    
    # Read and store network-vm SSH keys
    NETWORK_VM_SSH_PUBLIC=$(cat "$NETWORK_VM_SSH_PATH.pub")
    NETWORK_VM_SSH_PRIVATE=$(cat "$NETWORK_VM_SSH_PATH")
    
    curl -s -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"data\":{\"public\":\"$NETWORK_VM_SSH_PUBLIC\",\"private\":\"$NETWORK_VM_SSH_PRIVATE\"}}" \
        "$VAULT_ADDR/v1/secret/data/ssh_keys/network-vm"
    
    if [ $? -eq 0 ]; then
        echo "✅ Network-VM SSH keys stored in Vault"
    else
        echo "❌ Failed to store network-VM SSH keys"
    fi
fi

# Store Proxmox credentials (optional - for testing)
echo ""
echo "Storing Proxmox credentials in Vault..."

PVE_API="http://192.168.50.202:8006/api2/json"
PVE_USER="root@pam"
PVE_PASS="Tomtom22!"

curl -s -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"api_url\":\"$PVE_API\",\"user\":\"$PVE_USER\",\"password\":\"$PVE_PASS\"}}" \
    "$VAULT_ADDR/v1/secret/data/proxmox"

if [ $? -eq 0 ]; then
    echo "✅ Proxmox credentials stored in Vault"
else
    echo "❌ Failed to store Proxmox credentials"
fi

echo ""
echo "========================================="
echo "Vault setup complete!"
echo "========================================="
echo ""
echo "Stored secrets:"
echo "- SSH keys: secret/ssh_keys/media-stack_worker"
echo "- SSH keys: secret/ssh_keys/network-vm (if created)"
echo "- Proxmox: secret/proxmox"
echo ""
echo "To verify:"
echo "curl -H \"X-Vault-Token: myroot\" $VAULT_ADDR/v1/secret/data/ssh_keys/media-stack_worker"
echo ""
