#!/bin/bash

# Must have VAULT_TOKEN and VAULT_ADDR set!
<<<<<<< HEAD
export VAULT_ADDR="http://192.168.50.169:8200"
export VAULT_TOKEN="root" # or your actual token
=======
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot" # or your actual token
>>>>>>> dev

# Insert Tailscale key
vault kv put secret/tailscale authkey="tskey-...paste_your_key..."

# Insert qbittorrent creds
vault kv put secret/qbittorrent username="admin" password="ReplaceWithStrongPassword"

# Generate WireGuard keys
wg genkey | tee wg_private.key | wg pubkey > wg_public.key
vault kv put secret/wireguard private_key="$(cat wg_private.key)" peer_public_key="replace_with_peer_key"

# AdGuard admin password
vault kv put secret/adguard admin_password="ReplaceWithAdminPassword"

echo "Vault seeding completed!"
