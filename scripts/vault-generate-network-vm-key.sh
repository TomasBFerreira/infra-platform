#!/bin/bash
# vault-generate-network-vm-key.sh
# Usage: ./vault-generate-network-vm-key.sh <vault_addr> <vault_token>
# Example: ./vault-generate-network-vm-key.sh http://127.0.0.1:8200 s.xxxxxxxx

set -euo pipefail

VAULT_ADDR="$1"
VAULT_TOKEN="$2"
VAULT_PATH="secret/ssh_keys/network_vm_worker"
TMPDIR=$(mktemp -d)
KEYNAME="network_vm_worker_id_ed25519"

export VAULT_ADDR
export VAULT_TOKEN

# Check if key already exists in Vault
if vault kv get -field=public_key "$VAULT_PATH" >/dev/null 2>&1; then
  echo "SSH key already exists in Vault at $VAULT_PATH. Skipping generation."
  exit 0
fi

echo "Generating new SSH keypair..."
ssh-keygen -t ed25519 -N "" -f "$TMPDIR/$KEYNAME" -C "network-vm-worker" >/dev/null

PUB_KEY=$(cat "$TMPDIR/$KEYNAME.pub")
PRIV_KEY=$(cat "$TMPDIR/$KEYNAME")

# Upload both keys to Vault
vault kv put "$VAULT_PATH" public_key="$PUB_KEY" private_key="$PRIV_KEY"

echo "SSH keypair generated and uploaded to Vault at $VAULT_PATH."
# Clean up
test -d "$TMPDIR" && rm -rf "$TMPDIR"
