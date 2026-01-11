#!/bin/bash
# Script to delete and regenerate all SSH keys in Vault with proper formatting
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-myroot}"

export VAULT_ADDR
export VAULT_TOKEN

echo "========================================"
echo "Regenerating SSH keys in Vault"
echo "========================================"

# Install Vault CLI if not present
if ! command -v vault >/dev/null 2>&1; then
    echo "Installing Vault CLI..."
    VAULT_VERSION="1.15.2"
    curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o /tmp/vault.zip
    unzip -o /tmp/vault.zip -d /tmp/
    chmod +x /tmp/vault
    export PATH="/tmp:$PATH"
fi

echo "Using Vault at: $VAULT_ADDR"

# Delete existing media-stack key
echo ""
echo "1. Deleting existing media-stack SSH key..."
vault kv delete secret/ssh_keys/media-stack_worker 2>/dev/null || echo "  (Key didn't exist or already deleted)"

# Delete existing network-vm key (try both paths)
echo ""
echo "2. Deleting existing network-vm SSH key..."
vault kv delete secret/ssh_keys/network-vm_worker 2>/dev/null || echo "  (Key didn't exist at network-vm_worker)"
vault kv delete secret/ssh_keys/network_vm_worker 2>/dev/null || echo "  (Key didn't exist at network_vm_worker)"

# Regenerate media-stack key
echo ""
echo "3. Regenerating media-stack SSH key..."
cd /app/dev/infra-platform
docker run --rm \
  -e VAULT_ADDR="$VAULT_ADDR" \
  -e VAULT_TOKEN="$VAULT_TOKEN" \
  -v "$PWD:/app/infra-platform" \
  -w /app/infra-platform \
  ubuntu:22.04 \
  bash -c "
    apt-get update -qq && apt-get install -y -qq curl unzip openssh-client wget > /dev/null 2>&1
    ./scripts/vault-generate-secrets.sh
  "

# Regenerate network-vm key
echo ""
echo "4. Regenerating network-vm SSH key..."
docker run --rm \
  -e VAULT_ADDR="$VAULT_ADDR" \
  -e VAULT_TOKEN="$VAULT_TOKEN" \
  -v "$PWD:/app/dev/infra-platform" \
  -w /app/infra-platform \
  ubuntu:22.04 \
  bash -c "
    apt-get update -qq && apt-get install -y -qq curl unzip openssh-client > /dev/null 2>&1
    curl -fsSL https://releases.hashicorp.com/vault/1.15.2/vault_1.15.2_linux_amd64.zip -o vault.zip
    unzip -o vault.zip
    mv vault /usr/local/bin/
    chmod +x /usr/local/bin/vault
    /app/dev/infra-platform/scripts/vault-generate-network-vm-key.sh \"$VAULT_ADDR\" \"$VAULT_TOKEN\"
  "

echo ""
echo "========================================"
echo "✅ All SSH keys regenerated successfully!"
echo "========================================"
echo ""
echo "You can now verify the keys with:"
echo "  vault kv get secret/ssh_keys/media-stack_worker"
echo "  vault kv get secret/ssh_keys/network-vm_worker"
