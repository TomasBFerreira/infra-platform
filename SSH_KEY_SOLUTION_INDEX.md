# SSH Key Issue - Complete Solution Package

## 📋 Overview

The Ansible playbook failures with "error in libcrypto" were caused by SSH keys having Windows-style line endings (CRLF) instead of Unix-style (LF). This package provides multiple solutions to detect, fix, and prevent the issue.

---

## 🚀 Quick Start

**Choose your fix:**

| Option | Time | Requirements | Best For |
|--------|------|--------------|----------|
| **1. Rebuild Docker** | 2-3 min | Docker | Production & automation |
| **2. Setup from Vault** | 1 min | Vault access | Fresh configuration |
| **3. Quick Fix** | 30 sec | Already have keys | Fast local fix |

### 1️⃣ Rebuild Docker (Automatic Fixes)
```bash
cd /app/infra-platform
docker-compose build --no-cache ansible
# That's it! SSH keys are fixed automatically on container startup
```

### 2️⃣ Setup from Vault
```bash
cd /app/infra-platform
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot"
./scripts/setup-ssh-keys.sh
```

### 3️⃣ Quick Fix
```bash
cd /app/infra-platform
./scripts/diagnose-ssh-keys.sh  # See what's wrong
./scripts/fix-ssh-keys.sh        # Fix it
```

---

## 📚 Documentation Files

### For Quick Help
- **[QUICK_FIX_SSH_KEYS.md](./QUICK_FIX_SSH_KEYS.md)** - 30-second overview and solutions

### For Complete Understanding
- **[docs/SSH_KEY_FIX_SUMMARY.md](docs/SSH_KEY_FIX_SUMMARY.md)** - Detailed explanation of problem and solutions
- **[docs/SSH_KEY_TROUBLESHOOTING.md](docs/SSH_KEY_TROUBLESHOOTING.md)** - Full troubleshooting guide with all options

### For Script Documentation
- **[scripts/README.md](scripts/README.md)** - All scripts documented with usage examples

---

## 🛠️ Tools & Scripts

### Setup & Configuration
| Script | Purpose | Usage |
|--------|---------|-------|
| **setup-ssh-keys.sh** | Retrieve & fix SSH keys from Vault | `./scripts/setup-ssh-keys.sh [project]` |
| **entrypoint.sh** | Docker container auto-fix (embedded) | Runs automatically on container start |

### Diagnostics & Repair
| Script | Purpose | Usage |
|--------|---------|-------|
| **diagnose-ssh-keys.sh** | Report all SSH key issues | `./scripts/diagnose-ssh-keys.sh` |
| **fix-ssh-keys.sh** | Quick fix for line ending issues | `./scripts/fix-ssh-keys.sh` |

### Modified Files
| File | Changes |
|------|---------|
| **scripts/Dockerfile** | Added entrypoint.sh support for automatic SSH key fixes |
| **scripts/entrypoint.sh** | NEW - Auto-fixes SSH keys on container startup |

---

## 🔍 What Was Changed

### Problem Diagnosed
✗ SSH keys had CRLF line endings (from Vault or Windows clipboard)  
✗ OpenSSH libcrypto couldn't parse them  
✗ Ansible couldn't connect to hosts  

### Solution Implemented
✅ Docker image now auto-fixes SSH keys (transparent)  
✅ New script to retrieve & fix keys from Vault  
✅ Diagnostic tools to detect issues  
✅ Quick fix utilities for emergencies  

### How It Works
1. **Container Startup**: `entrypoint.sh` detects SSH keys with CRLF
2. **Automatic Fix**: `sed 's/\r$//'` removes carriage returns
3. **Validation**: `ssh-keygen` verifies key format
4. **Ready**: Ansible runs with proper keys

---

## ✅ Verification

### Test SSH Key Format
```bash
# Should show key fingerprint (means it's valid)
ssh-keygen -l -f ~/ssh/infra-lxc_worker_id_ed25519
ssh-keygen -l -f ~/ssh/network-vm_worker_id_ed25519

# Should show LF only (not CRLF)
file ~/ssh/*_id_ed25519
```

### Test SSH Connection
```bash
# Should connect successfully
ssh -i ~/ssh/infra-lxc_worker_id_ed25519 root@192.168.50.221 "echo OK"
ssh -i ~/ssh/network-vm_worker_id_ed25519 root@192.168.50.251 "echo OK"
```

### Test Ansible
```bash
cd /app/infra-platform

# Test infra-lxc
./scripts/run-ansible.sh playbook \
    -i ansible/dev/infra-lxc/inventory.ini \
    --private-key /root/ssh/infra-lxc_worker_id_ed25519 \
    ansible/dev/infra-lxc/infra-lxc_setup.yml

# Test network-vm
./scripts/run-ansible.sh playbook \
    -i ansible/dev/network-vm/inventory.ini \
    --private-key /root/ssh/network-vm_worker_id_ed25519 \
    ansible/dev/network-vm/network-vm_setup.yml
```

---

## 📖 Detailed Guides by Use Case

### I want the automatic fix (easiest)
→ See [QUICK_FIX_SSH_KEYS.md](./QUICK_FIX_SSH_KEYS.md) - Option 1

### My keys are broken, fix them now
→ Run `./scripts/fix-ssh-keys.sh`

### I want fresh keys from Vault
→ See [docs/SSH_KEY_TROUBLESHOOTING.md](docs/SSH_KEY_TROUBLESHOOTING.md) - Option 1

### I want to understand what happened
→ Read [docs/SSH_KEY_FIX_SUMMARY.md](docs/SSH_KEY_FIX_SUMMARY.md)

### I want complete documentation
→ See [scripts/README.md](scripts/README.md)

### I need to diagnose issues
→ Run `./scripts/diagnose-ssh-keys.sh`

---

## 🎯 Key Features

| Feature | Benefit |
|---------|---------|
| **Automatic Docker Fix** | No manual steps, works transparently |
| **Vault Integration** | Retrieve fresh keys anytime |
| **Diagnostic Tools** | Know exactly what's wrong |
| **Multiple Solutions** | Fast fixes or comprehensive setup |
| **Well Documented** | Complete guides for every scenario |
| **Safe & Validated** | No data loss, validated before use |

---

## 🆘 Troubleshooting

### If you still get "error in libcrypto"

1. Run diagnostic:
```bash
./scripts/diagnose-ssh-keys.sh
```

2. Check what's reported and follow the suggestions

3. If keys are broken, retrieve fresh ones:
```bash
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot"
./scripts/setup-ssh-keys.sh
```

4. Rebuild Docker image:
```bash
docker-compose build --no-cache ansible
```

5. Try Ansible again

### Still having issues?

- Check [docs/SSH_KEY_TROUBLESHOOTING.md](docs/SSH_KEY_TROUBLESHOOTING.md)
- Run `./scripts/diagnose-ssh-keys.sh` with full output
- Review [scripts/README.md](scripts/README.md) for each script

---

## 📦 Files Created/Modified

### Created Files (7 new)
```
✨ scripts/setup-ssh-keys.sh          - Main SSH key setup script
✨ scripts/entrypoint.sh              - Docker container entrypoint
✨ scripts/diagnose-ssh-keys.sh       - SSH key diagnostic tool
✨ scripts/fix-ssh-keys.sh            - Quick line ending fix
✨ docs/SSH_KEY_TROUBLESHOOTING.md    - Complete troubleshooting guide
✨ docs/SSH_KEY_FIX_SUMMARY.md        - Problem explanation & solutions
✨ QUICK_FIX_SSH_KEYS.md              - Quick reference guide
```

### Modified Files (2)
```
🔧 scripts/Dockerfile                - Added entrypoint support
🔧 scripts/README.md                 - Updated with new scripts
```

---

## ✨ Next Steps

1. **Choose your fix** from the Quick Start section above
2. **Verify it works** using the Verification section
3. **Bookmark** the appropriate documentation for future reference
4. **Done!** Your Ansible playbooks should now work

---

## 📞 Support

All scripts include:
- ✅ Comprehensive error messages
- ✅ Helpful output and suggestions
- ✅ Exit codes for automation
- ✅ Interactive mode where helpful

For questions or issues, refer to the documentation files listed above.

---

## 📝 Technical Details

### The Root Cause
SSH keys in Vault are stored with literal newlines. When retrieved, they can end up with:
- ✗ CRLF (`\r\n`) - Windows line endings
- ✗ LF (`\n`) - Unix line endings (correct)

OpenSSH libcrypto only accepts LF. The fix simply converts CRLF → LF.

### Where the Fix Happens
1. **Vault retrieval**: `setup-ssh-keys.sh` fixes during download
2. **Docker startup**: `entrypoint.sh` fixes on container start  
3. **Manual fix**: `fix-ssh-keys.sh` or `diagnose-ssh-keys.sh` on demand

### Compatibility
- ✅ Works with ED25519 keys
- ✅ Works with RSA keys
- ✅ Safe to run multiple times
- ✅ No data loss (formatting only)

---

**Status**: ✅ Complete - Ready to deploy

**Last Updated**: January 6, 2026
