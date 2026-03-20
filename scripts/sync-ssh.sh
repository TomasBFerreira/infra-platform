#!/bin/bash
# sync-ssh.sh — Pull SSH keys from bootstrap vault and update ~/.ssh/config
#
# Usage:
#   VAULT_ADDR=http://192.168.50.200:8200 VAULT_TOKEN=<token> ./scripts/sync-ssh.sh
#
# Or with a token file:
#   export VAULT_ADDR=http://192.168.50.200:8200
#   export VAULT_TOKEN=$(cat ~/.vault-token)
#   ./scripts/sync-ssh.sh
#
# Run this any time you want to refresh keys or after a blue/green deployment
# flips the active slot of a service.

set -euo pipefail

SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"
MANAGED_HEADER="# === BEGIN MANAGED BY sync-ssh.sh — DO NOT EDIT ==="
MANAGED_FOOTER="# === END MANAGED BY sync-ssh.sh ==="

# ─── Checks ──────────────────────────────────────────────────────────────────

if [[ -z "${VAULT_ADDR:-}" ]]; then
  echo "ERROR: VAULT_ADDR is not set. Point it at the bootstrap vault." >&2
  echo "  Example: export VAULT_ADDR=http://192.168.50.200:8200" >&2
  exit 1
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "ERROR: VAULT_TOKEN is not set." >&2
  exit 1
fi

if ! command -v vault &>/dev/null; then
  echo "ERROR: vault CLI not found in PATH." >&2
  exit 1
fi

mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Fetch a field from vault KV, trying primary_field first then fallback_field.
# Returns the value or empty string if not found.
vault_get_field() {
  local path="$1" field="$2" fallback="${3:-}"
  local val
  val=$(vault kv get -field="${field}" "${path}" 2>/dev/null || true)
  if [[ -z "$val" && -n "$fallback" ]]; then
    val=$(vault kv get -field="${fallback}" "${path}" 2>/dev/null || true)
  fi
  echo "$val"
}

# Write a private key to ~/.ssh/, set 600 perms.
write_key() {
  local key_name="$1"
  local key_content="$2"
  local key_path="${SSH_DIR}/${key_name}"

  if [[ -z "$key_content" ]]; then
    echo "  [skip] ${key_name} — not found in vault"
    return
  fi

  printf '%s\n' "$key_content" > "${key_path}"
  chmod 600 "${key_path}"
  echo "  [ok]   ${key_name}"
}

# Query vault for the active IP of a blue/green service.
# Returns empty string if the service hasn't been deployed yet.
active_ip() {
  local service="$1" env="$2"
  vault kv get -field=ip "secret/${service}/${env}/active-slot" 2>/dev/null || true
}

# ─── Step 1: Pull SSH keys from vault ────────────────────────────────────────

echo ""
echo "==> Pulling SSH keys from vault (${VAULT_ADDR})"

# media-stack uses 'private' field (older convention)
media_key=$(vault_get_field "secret/ssh_keys/media-stack_worker" "private_key" "private")
write_key "media-stack_worker_id_ed25519" "$media_key"

# Newer services use 'private_key' field
vault_ct_key=$(vault_get_field "secret/ssh_keys/vault_ct_worker" "private_key" "private")
write_key "vault_ct_worker_id_ed25519" "$vault_ct_key"

network_vm_key=$(vault_get_field "secret/ssh_keys/network_vm_worker" "private_key" "private")
write_key "network_vm_worker_id_ed25519" "$network_vm_key"

torrent_key=$(vault_get_field "secret/ssh_keys/torrent_worker" "private_key" "private")
write_key "torrent_worker_id_ed25519" "$torrent_key"

# ─── Step 2: Resolve active IPs for blue/green services ──────────────────────

echo ""
echo "==> Resolving active slots from vault"

vault_ct_dev_ip=$(active_ip "vault-ct" "dev")
vault_ct_prod_ip=$(active_ip "vault-ct" "prod")
network_vm_dev_ip=$(active_ip "network-vm" "dev")
network_vm_prod_ip=$(active_ip "network-vm" "prod")
torrent_dev_ip=$(active_ip "torrent" "dev")
torrent_prod_ip=$(active_ip "torrent" "prod")

echo "  vault-ct     dev=${vault_ct_dev_ip:-not deployed}  prod=${vault_ct_prod_ip:-not deployed}"
echo "  network-vm   dev=${network_vm_dev_ip:-not deployed}  prod=${network_vm_prod_ip:-not deployed}"
echo "  torrent      dev=${torrent_dev_ip:-not deployed}  prod=${torrent_prod_ip:-not deployed}"

# ─── Step 3: Build the managed SSH config block ──────────────────────────────

echo ""
echo "==> Updating ${CONFIG_FILE}"

# Helper: emit a Host block, skipping if IP is empty (service not deployed yet)
host_block() {
  local alias="$1" ip="$2" key_file="$3"
  if [[ -z "$ip" ]]; then
    return
  fi
  cat <<EOF
Host ${alias}
  HostName ${ip}
  User root
  IdentityFile ${SSH_DIR}/${key_file}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

EOF
}

managed_block="${MANAGED_HEADER}
# Auto-generated — edit the script, not this block.
# Re-run scripts/sync-ssh.sh to refresh after deployments.

# ── Proxmox nodes (static) ────────────────────────────────────────────────────

Host betsy
  HostName 192.168.50.2
  User root
  IdentityFile ${SSH_DIR}/id_rsa
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host benedict
  HostName 192.168.50.4
  User root
  IdentityFile ${SSH_DIR}/id_rsa
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

# ── Media VM (static) ─────────────────────────────────────────────────────────

Host media-vm
  HostName 192.168.50.111
  User root
  IdentityFile ${SSH_DIR}/media-stack_worker_id_ed25519
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

# ── Bootstrap vault CT 200 (static) ──────────────────────────────────────────

Host bootstrap-vault
  HostName 192.168.50.200
  User root
  IdentityFile ${SSH_DIR}/id_rsa
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

# ── Vault CT (blue/green active slot) ────────────────────────────────────────

$(host_block "vault-ct-dev"  "${vault_ct_dev_ip}"  "vault_ct_worker_id_ed25519")
$(host_block "vault-ct-prod" "${vault_ct_prod_ip}" "vault_ct_worker_id_ed25519")
# ── Network VM (blue/green active slot) ──────────────────────────────────────

$(host_block "network-vm-dev"  "${network_vm_dev_ip}"  "network_vm_worker_id_ed25519")
$(host_block "network-vm-prod" "${network_vm_prod_ip}" "network_vm_worker_id_ed25519")
# ── Torrent LXC (blue/green active slot) ─────────────────────────────────────

$(host_block "torrent-dev"  "${torrent_dev_ip}"  "torrent_worker_id_ed25519")
$(host_block "torrent-prod" "${torrent_prod_ip}" "torrent_worker_id_ed25519")
${MANAGED_FOOTER}"

# Preserve any content that was in the config before the managed block,
# and any content after it, then replace the managed block.
if [[ -f "${CONFIG_FILE}" ]]; then
  before=$(awk "/^${MANAGED_HEADER//\//\\/}/{exit} {print}" "${CONFIG_FILE}")
  after=$(awk "found{print} /^${MANAGED_FOOTER//\//\\/}/{found=1}" "${CONFIG_FILE}")
else
  before=""
  after=""
fi

{
  [[ -n "$before" ]] && printf '%s\n' "$before"
  printf '%s\n' "$managed_block"
  [[ -n "$after" ]] && printf '%s\n' "$after"
} > "${CONFIG_FILE}"

chmod 600 "${CONFIG_FILE}"

echo "  Done. Available host aliases:"
grep "^Host " "${CONFIG_FILE}" | awk '{print "    ssh " $2}'
echo ""
