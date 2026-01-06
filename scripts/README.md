# Infrastructure Platform Scripts

This directory contains utility scripts for managing the infrastructure platform.

## SSH Key Management Scripts

### 1. **setup-ssh-keys.sh** - Primary SSH Key Setup
**Purpose**: Retrieve SSH keys from Vault and configure them properly.

**Usage**:
```bash
# Setup all SSH keys
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="your-token"
./scripts/setup-ssh-keys.sh

# Setup keys for a specific project
./scripts/setup-ssh-keys.sh infra-lxc
./scripts/setup-ssh-keys.sh network-vm
./scripts/setup-ssh-keys.sh media-stack
```

**What it does**:
- Retrieves private keys from Vault
- Automatically fixes line endings (CRLF → LF)
- Validates key format with ssh-keygen
- Sets correct file permissions (600)
- Saves keys to `~/.ssh/`

### 2. **diagnose-ssh-keys.sh** - Diagnostic Tool
**Purpose**: Check SSH keys for issues and interactively repair them.

**Usage**:
```bash
./scripts/diagnose-ssh-keys.sh
```

**What it does**:
- Scans all SSH keys in `~/ssh/`
- Reports issues: wrong permissions, invalid line endings, corrupted keys
- Shows file sizes and key types
- Offers interactive repair of detected issues

### 3. **fix-ssh-keys.sh** - Quick Fix
**Purpose**: Immediately fix SSH key line endings without Vault.

**Usage**:
```bash
./scripts/fix-ssh-keys.sh
```

**What it does**:
- Fixes Windows line endings (CRLF) in all SSH keys
- Sets correct permissions
- Verifies key format after fixing
- No Vault required

## Ansible Scripts

### run-ansible.sh
Main script for running Ansible commands in Docker containers.

**Usage**:
```bash
./scripts/run-ansible.sh playbook -i inventory.ini playbook.yml
./scripts/run-ansible.sh inventory -i inventory.ini --host myhost
./scripts/run-ansible.sh vault encrypt myfile.yml
```

## Infrastructure Setup Scripts

### setup-vault-secrets.sh
Initializes Vault with required secrets (SSH keys, passwords, etc.).

**Usage**:
```bash
./scripts/setup-vault-secrets.sh
```

### setup-github-runner.sh
Configures GitHub Actions runner for CI/CD.

**Usage**:
```bash
./scripts/setup-github-runner.sh
```

## Vault Management Scripts

### vault-generate-secrets.sh
Generates and stores secrets in Vault (SSH keys, passwords).

### vault-regenerate-all-keys.sh
Regenerates all SSH keys and passwords in Vault.

### vault-generate-network-vm-key.sh
Generates SSH key specifically for network-vm.

### vault-smoke-test.sh
Tests Vault connectivity and secret retrieval.

### scripts/dev/network-vm/vault-generate-secrets.sh
Project-specific secret generation for network-vm.

## Terraform Scripts

### run-terraform.sh
Wrapper for running Terraform commands in Docker containers.

**Usage**:
```bash
./scripts/run-terraform.sh plan
./scripts/run-terraform.sh apply
./scripts/run-terraform.sh init
```

## Environment-Specific Tests

### test-vault-secrets.yml
Ansible playbook to test Vault integration.

### test-container-vault.sh
Tests Vault within the Docker container.

## Other Scripts

### delete-network-vm.sh
Removes the network-vm infrastructure.

### get_ssh_key.py
Python utility to retrieve SSH keys from Vault.

## Common Workflows

### First Time Setup
```bash
# 1. Initialize Vault secrets
./scripts/setup-vault-secrets.sh

# 2. Retrieve SSH keys
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot"
./scripts/setup-ssh-keys.sh

# 3. Test Ansible
./scripts/run-ansible.sh playbook -i ansible/dev/network-vm/inventory.ini \
    --private-key /root/ssh/network-vm_worker_id_ed25519 \
    ansible/dev/network-vm/network-vm_setup.yml
```

### Troubleshooting SSH Connection Issues
```bash
# 1. Diagnose the issue
./scripts/diagnose-ssh-keys.sh

# 2. If keys have Windows line endings
./scripts/fix-ssh-keys.sh

# 3. Or retrieve fresh keys from Vault
./scripts/setup-ssh-keys.sh
```

### Regenerating Secrets
```bash
# Regenerate all SSH keys and passwords
./scripts/vault-regenerate-all-keys.sh

# Then setup new SSH keys
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot"
./scripts/setup-ssh-keys.sh
```

## Docker Entrypoint

The Ansible Docker image includes an `entrypoint.sh` that automatically:
- Detects SSH keys with Windows line endings
- Fixes line endings automatically
- Validates key formats
- Ensures proper permissions

This means SSH key issues are transparent when using the Docker container - they're fixed automatically when needed.

## Requirements

### For setup-ssh-keys.sh:
- `vault` CLI installed and in PATH
- `ssh-keygen` installed (openssh-client)
- VAULT_ADDR and VAULT_TOKEN environment variables set

### For diagnose-ssh-keys.sh and fix-ssh-keys.sh:
- `ssh-keygen` installed
- `file` command available
- `sed` command available

### For Ansible scripts:
- Docker or Docker Compose installed
- Custom Ansible Docker image built

## SSH Key Format Details

Valid ED25519 SSH private keys have this format:
```
-----BEGIN OPENSSH PRIVATE KEY-----
[base64 encoded data]
-----END OPENSSH PRIVATE KEY-----
```

**Common Issues**:
- ✗ CRLF line endings (Windows): Caused by copying keys through Windows systems
- ✗ Missing newline at end of file
- ✗ Trailing whitespace
- ✗ Wrong file permissions

The provided scripts automatically handle all of these issues.
