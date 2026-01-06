# SSH Key Issue Resolution - Summary

## Problem Identified

Both the `infra-lxc` and `network-vm` Ansible playbook runs failed with:
```
Load key "/root/ssh/infra-lxc_worker_id_ed25519": error in libcrypto
Permission denied (publickey,password).
```

### Root Cause
SSH keys retrieved from Vault contain Windows-style line endings (CRLF) instead of Unix-style (LF). When OpenSSH's libcrypto tries to parse these malformed keys, it fails.

## Solution Implemented

### 1. Docker Container Auto-Fix
**File**: `scripts/Dockerfile` + `scripts/entrypoint.sh`
- Added an entrypoint script that automatically detects and fixes SSH key line endings
- This runs transparently whenever the container starts
- No additional steps needed once image is rebuilt

**How it works**:
- Container startup detects CRLF in SSH key files
- Automatically converts to LF with `sed 's/\r$//'`
- Validates key format with `ssh-keygen`
- All fixes happen automatically before Ansible runs

### 2. Automated Setup Script
**File**: `scripts/setup-ssh-keys.sh`
- Retrieves SSH keys from Vault
- Automatically fixes line endings
- Validates and sets correct permissions
- Works for all projects (infra-lxc, network-vm, media-stack)

**Usage**:
```bash
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="your-token"
./scripts/setup-ssh-keys.sh
```

### 3. Diagnostic Tools
**Files**: 
- `scripts/diagnose-ssh-keys.sh` - Comprehensive diagnostic report with interactive repair
- `scripts/fix-ssh-keys.sh` - Quick line ending fix without Vault

**Usage**:
```bash
# Diagnose issues
./scripts/diagnose-ssh-keys.sh

# Quick fix existing keys
./scripts/fix-ssh-keys.sh
```

### 4. Documentation
**Files**:
- `docs/SSH_KEY_TROUBLESHOOTING.md` - Complete troubleshooting guide
- `scripts/README.md` - Updated with all new scripts and workflows

## Files Created/Modified

### Created:
- `/app/infra-platform/scripts/setup-ssh-keys.sh` - Main SSH setup script
- `/app/infra-platform/scripts/entrypoint.sh` - Docker entrypoint for auto-fixes
- `/app/infra-platform/scripts/diagnose-ssh-keys.sh` - Diagnostic tool
- `/app/infra-platform/scripts/fix-ssh-keys.sh` - Quick fix utility
- `/app/infra-platform/docs/SSH_KEY_TROUBLESHOOTING.md` - Troubleshooting guide
- `/app/infra-platform/scripts/README.md` - Updated scripts documentation

### Modified:
- `/app/infra-platform/scripts/Dockerfile` - Added entrypoint support

## Next Steps

### Immediate Action (Choose One)

#### Option A: Full Docker Rebuild (Recommended)
```bash
# Rebuild the Ansible Docker image with the fix
docker-compose build --no-cache ansible

# Then run your Ansible playbooks
cd /app/infra-platform
./scripts/run-ansible.sh playbook \
    -i ansible/dev/network-vm/inventory.ini \
    --private-key /root/ssh/network-vm_worker_id_ed25519 \
    ansible/dev/network-vm/network-vm_setup.yml
```

#### Option B: Retrieve Fresh Keys from Vault
```bash
# Set Vault credentials
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="your-token"

# Retrieve and fix SSH keys
./scripts/setup-ssh-keys.sh

# Run Ansible playbooks
./scripts/run-ansible.sh playbook ...
```

#### Option C: Quick Fix Existing Keys
If keys already exist but have formatting issues:
```bash
./scripts/diagnose-ssh-keys.sh
# or
./scripts/fix-ssh-keys.sh
```

## Verification

### Test SSH Key Format
```bash
# Verify keys are properly formatted
ssh-keygen -l -f ~/ssh/infra-lxc_worker_id_ed25519
ssh-keygen -l -f ~/ssh/network-vm_worker_id_ed25519

# Check for line ending issues
file ~/ssh/*_id_ed25519
```

### Test SSH Connection
```bash
# Test SSH to infra-lxc
ssh -i ~/ssh/infra-lxc_worker_id_ed25519 root@192.168.50.221 "echo 'Connected!'"

# Test SSH to network-vm
ssh -i ~/ssh/network-vm_worker_id_ed25519 root@192.168.50.251 "echo 'Connected!'"
```

### Test Ansible Playbook
```bash
cd /app/infra-platform

# Run infra-lxc setup
./scripts/run-ansible.sh playbook \
    -i ansible/dev/infra-lxc/inventory.ini \
    --private-key /root/ssh/infra-lxc_worker_id_ed25519 \
    ansible/dev/infra-lxc/infra-lxc_setup.yml

# Run network-vm setup
./scripts/run-ansible.sh playbook \
    -i ansible/dev/network-vm/inventory.ini \
    --private-key /root/ssh/network-vm_worker_id_ed25519 \
    ansible/dev/network-vm/network-vm_setup.yml
```

## Key Features of the Solution

✅ **Automatic**: Docker container fixes SSH keys transparently  
✅ **Safe**: Validates key format before using  
✅ **Reversible**: No data loss, only formatting fixes  
✅ **Well-documented**: Multiple troubleshooting guides  
✅ **Comprehensive**: Diagnostic tools included  
✅ **Vault-integrated**: Can retrieve fresh keys as needed  

## How the Fix Works (Technical Details)

### The Issue
```
SSH key in Vault: "-----BEGIN OPENSSH PRIVATE KEY-----\r\n[key data]\r\n-----END OPENSSH PRIVATE KEY-----\r\n"
                                                    ^^                                      ^^
                                                 CRLF line endings cause libcrypto failure
```

### The Solution
```bash
sed -i 's/\r$//' /root/ssh/infra-lxc_worker_id_ed25519
# Removes all \r (carriage returns) at end of lines
# Result: proper Unix-style LF only line endings
```

### Where the Fix Happens
1. **In Docker Container** (Automatic): `entrypoint.sh` runs before any command
2. **Local Script** (Manual): `setup-ssh-keys.sh` fixes during retrieval
3. **Interactive** (On-demand): `diagnose-ssh-keys.sh` or `fix-ssh-keys.sh`

## Prevention

For future key retrieval, always use:
```bash
./scripts/setup-ssh-keys.sh
```

This ensures proper formatting from the start.

## Support

If you encounter issues:
1. Run diagnostic: `./scripts/diagnose-ssh-keys.sh`
2. Check documentation: `docs/SSH_KEY_TROUBLESHOOTING.md`
3. Review script README: `scripts/README.md`
