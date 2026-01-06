# Quick Start: Fix SSH Key Issues

## The Problem
```
Load key "/root/ssh/infra-lxc_worker_id_ed25519": error in libcrypto
```

## The Solution (Pick One)

### 🟢 Option 1: Rebuild Docker Image (Best)
```bash
cd /app/infra-platform
docker-compose build --no-cache ansible
```
Done! SSH key issues are now fixed automatically.

---

### 🟡 Option 2: Setup Fresh Keys from Vault (Recommended)
```bash
cd /app/infra-platform
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot"

./scripts/setup-ssh-keys.sh
```

---

### 🔴 Option 3: Quick Fix Existing Keys
```bash
cd /app/infra-platform
./scripts/fix-ssh-keys.sh
```

---

## Verify It Works

```bash
# Test a key
ssh-keygen -l -f ~/ssh/infra-lxc_worker_id_ed25519

# Run Ansible
cd /app/infra-platform
./scripts/run-ansible.sh playbook \
    -i ansible/dev/network-vm/inventory.ini \
    --private-key /root/ssh/network-vm_worker_id_ed25519 \
    ansible/dev/network-vm/network-vm_setup.yml
```

---

## Need More Help?

- **Diagnose issues**: `./scripts/diagnose-ssh-keys.sh`
- **Full guide**: See `docs/SSH_KEY_TROUBLESHOOTING.md`
- **Script docs**: See `scripts/README.md`
