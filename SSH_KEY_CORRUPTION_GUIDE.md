# SSH Key Issue - Deeper Diagnosis & Solutions

## What We Found

The error `"Warning: SSH key format may be invalid"` suggests the SSH keys are **fundamentally corrupted**, not just having line ending issues. This can happen if:

1. ✗ Keys were corrupted during transfer/storage
2. ✗ Keys are in the wrong format in Vault
3. ✗ Keys were truncated or partially copied
4. ✗ Binary corruption in the key data

## Immediate Actions (Do These Now)

### Step 1: Run Diagnostic Script
```bash
cd /app/infra-platform
./scripts/debug-ssh-keys.sh
```

This will show:
- Whether keys have CRLF vs LF
- Whether keys are corrupted (binary data)
- Whether headers/footers are correct
- Key size (should be > 1700 bytes)
- Hex dump for inspection

### Step 2: Based on Diagnostic Results

**If header shows `-----BEGIN OPENSSH PRIVATE KEY-----`:**
```bash
# Keys are structurally OK, just need line ending fix
./scripts/fix-ssh-keys.sh
```

**If header is WRONG or KEY SIZE TOO SMALL:**
```bash
# Keys are corrupted, need fresh retrieval from Vault
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="myroot"
./scripts/setup-ssh-keys.sh
```

**If unsure:**
```bash
# Safest option - get fresh keys and rebuild everything
./scripts/setup-ssh-keys.sh
docker compose build --no-cache ansible
```

## What Changed in GitHub Actions

We updated all 3 Ansible jobs in `.github/workflows/dev-infrastructure.yml`:
- ✅ Added `--no-cache` flag to `docker compose build ansible`
- This prevents GitHub Actions from using a cached Docker image
- Ensures the fix script runs fresh each time

## Improved Error Handling

The new `entrypoint.sh` now:
- ✅ Validates key size (> 1700 bytes)
- ✅ Checks for corrupted binary data
- ✅ Shows detailed error messages
- ✅ Suggests recovery steps
- ✅ Returns error code on failure (won't silently fail)

## New Debug Tool

**`scripts/debug-ssh-keys.sh`** provides detailed analysis:
```bash
./scripts/debug-ssh-keys.sh
```

Shows for each key:
- File permissions and size
- Line ending style (CRLF vs LF)
- Binary corruption detection
- Key header/footer validation
- SSH-keygen validation results
- Hex dump of first 100 bytes
- Specific recommendations

## Root Cause Investigation

If keys are corrupted, likely causes:
1. **Vault storage issue** - Keys stored incorrectly in Vault
2. **Transfer issue** - Keys corrupted during GitHub Actions secret transfer
3. **Previous run** - Bad keys saved from previous failed attempt

## Solution Plan

**Option A: Clean Restart (Recommended)**
```bash
# 1. Regenerate keys in Vault
./scripts/vault-regenerate-all-keys.sh

# 2. Retrieve fresh keys
./scripts/setup-ssh-keys.sh

# 3. Test locally first
ssh-keygen -l -f ~/ssh/infra-lxc_worker_id_ed25519

# 4. Rebuild Docker
docker compose build --no-cache ansible

# 5. Test Ansible
./scripts/run-ansible.sh playbook \
    -i ansible/dev/network-vm/inventory.ini \
    --private-key /root/ssh/network-vm_worker_id_ed25519 \
    ansible/dev/network-vm/network-vm_setup.yml
```

**Option B: Quick Fix (If keys are mostly OK)**
```bash
# Just fix line endings
./scripts/fix-ssh-keys.sh

# Verify
ssh-keygen -l -f ~/ssh/infra-lxc_worker_id_ed25519
```

## Next: GitHub Actions Will Now

1. ✅ Build Docker image **without cache** (fresh image)
2. ✅ Container starts and runs `entrypoint.sh`
3. ✅ Entrypoint validates SSH keys
4. ✅ If invalid, shows detailed error (not silent warning)
5. ✅ Ansible then runs (if keys are valid)

## Monitoring

Watch for in the GitHub Actions logs:
```
✓ SSH key OK: infra-lxc_worker_id_ed25519
✓ SSH key OK: network-vm_worker_id_ed25519
✓ SSH key OK: media-stack_worker_id_ed25519
```

If you see errors, the next section will tell you exactly what's wrong.

## Questions?

1. Run `./scripts/debug-ssh-keys.sh` to see detailed diagnostics
2. Check `docs/SSH_KEY_TROUBLESHOOTING.md` for full guide
3. Use `./scripts/setup-ssh-keys.sh` to retrieve fresh keys anytime
