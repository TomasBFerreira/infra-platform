# SSH Key Troubleshooting Guide

## Problem
When running Ansible playbooks via Docker container, SSH keys fail to load with error:
```
Load key "/root/ssh/infra-lxc_worker_id_ed25519": error in libcrypto
```

## Root Cause
SSH keys retrieved from Vault may contain Windows-style line endings (CRLF) instead of Unix-style line endings (LF). This causes OpenSSH's libcrypto to fail parsing the key file.

## Solutions

### Option 1: Use the Automated Setup Script (Recommended)
```bash
# Set your Vault credentials
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="your-token"

# Run the setup script to retrieve and fix all SSH keys
./scripts/setup-ssh-keys.sh

# Or setup keys for a specific project
./scripts/setup-ssh-keys.sh infra-lxc
./scripts/setup-ssh-keys.sh network-vm
```

This script:
- Retrieves SSH keys from Vault
- Automatically fixes line endings (CRLF → LF)
- Validates key format with ssh-keygen
- Sets correct permissions (600)

### Option 2: Manual Fix (If keys already exist)
If SSH keys already exist at `~/ssh/`, you can manually fix line endings:

```bash
# Fix a specific key
sed -i 's/\r$//' ~/ssh/infra-lxc_worker_id_ed25519
chmod 600 ~/ssh/infra-lxc_worker_id_ed25519

# Or fix all keys at once
for key in ~/ssh/*_id_ed25519 ~/ssh/*_id_rsa; do
    [ -f "$key" ] && sed -i 's/\r$//' "$key" && chmod 600 "$key"
done
```

### Option 3: Docker Container Fixes (Automatic)
The Docker image has been updated with an entrypoint script that automatically fixes SSH key line endings when the container starts. Simply rebuild the image:

```bash
docker-compose build --no-cache ansible
```

Then run your Ansible playbooks as normal:
```bash
./scripts/run-ansible.sh playbook -i ansible/dev/network-vm/inventory.ini \
    --private-key /root/ssh/network-vm_worker_id_ed25519 \
    ansible/dev/network-vm/network-vm_setup.yml
```

## Verification

To verify SSH keys are properly formatted:

```bash
# List SSH keys
ls -l ~/ssh/*_id_ed25519

# Check line endings (should show just LF, not CRLF)
file ~/ssh/*_id_ed25519

# Validate key format
ssh-keygen -l -f ~/ssh/infra-lxc_worker_id_ed25519
ssh-keygen -l -f ~/ssh/network-vm_worker_id_ed25519
```

## Prevention

- Always use the `setup-ssh-keys.sh` script to retrieve keys from Vault
- The Docker container now automatically fixes line endings, making this issue transparent
- Keys are properly validated before use

## Related Files
- `./scripts/setup-ssh-keys.sh` - Automated SSH key setup script
- `./scripts/entrypoint.sh` - Docker entrypoint that fixes SSH keys
- `./scripts/Dockerfile` - Updated with entrypoint support
