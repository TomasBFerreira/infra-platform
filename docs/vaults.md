# Vault Architecture

## Overview

Three tiers of Vault:

```
Bootstrap vault (CT 200, 192.168.50.200)
    Permanent. Never redeployed. Stores SSH keys, slot state, shared infra secrets.
    Credentials: VAULT_DEV_ADDR / VAULT_DEV_TOKEN GitHub secrets.

Dev env vault (192.168.50.245 or .246, whichever is active)
    Blue/green deployed. Stores dev environment secrets.
    Credentials: VAULT_ADDR / VAULT_TOKEN GitHub secrets.

Prod env vault (192.168.50.145 or .146, whichever is active)
    Blue/green deployed. Stores prod environment secrets.
    Credentials: VAULT_PROD_ADDR / VAULT_PROD_TOKEN GitHub secrets.
```

Active slot for each env vault is tracked in the bootstrap vault:
- `secret/vault-ct/dev/active-slot` → `{slot, vmid, ip}`
- `secret/vault-ct/prod/active-slot` → `{slot, vmid, ip}`

## Bootstrap Vault — Secrets Inventory

| Path | Fields | Written by |
|------|--------|------------|
| `secret/ssh_keys/vault_ct_worker` | `private_key` | Manual setup |
| `secret/ssh_keys/network_vm_worker` | `private_key` | Manual setup |
| `secret/ssh_keys/sso_worker` | `private_key` | Manual setup |
| `secret/tailscale` | `authkey` | Manual setup |
| `secret/wireguard` | `private_key, peer_public_key, endpoint, address, dns` | Manual setup |
| `secret/adguard` | `username, password` | Manual setup |
| `secret/cloudflare-tunnel` | `token` | Manual setup (prod tunnel) |
| `secret/authentik/dev/vault-oidc` | `client_id, client_secret, sso_ip, discovery_url` | SSO pipeline |
| `secret/authentik/prod/vault-oidc` | `client_id, client_secret, sso_ip, discovery_url` | SSO pipeline |
| `secret/vault-ct/dev/active-slot` | `slot, vmid, ip` | vault-ct pipeline |
| `secret/vault-ct/prod/active-slot` | `slot, vmid, ip` | vault-ct pipeline |
| `secret/network-vm/dev/active-slot` | `slot, vmid, ip` | network-vm pipeline |
| `secret/network-vm/prod/active-slot` | `slot, vmid, ip` | network-vm pipeline |
| `secret/sso/dev/active-slot` | `slot, vmid, ip` | SSO pipeline |
| `secret/sso/prod/active-slot` | `slot, vmid, ip` | SSO pipeline |

## Env Vault — Secrets Inventory

| Path | Fields | Seeded from | Written by |
|------|--------|-------------|------------|
| `secret/tailscale` | `authkey` | Bootstrap vault | vault-ct Ansible |
| `secret/wireguard` | `private_key, peer_public_key, endpoint, address, dns` | Bootstrap vault | vault-ct Ansible (prod only) |
| `secret/adguard` | `username, password` | Bootstrap vault | vault-ct Ansible |
| `secret/cloudflare-tunnel` | `token` | Bootstrap vault | vault-ct Ansible (prod only) |
| `secret/authentik/vault-oidc` | `client_id, client_secret, sso_ip, discovery_url` | Bootstrap vault (`secret/authentik/<env>/vault-oidc`) | vault-ct Ansible |
| `secret/sso` | `db_password, secret_key, bootstrap_password, bootstrap_token` | Not seeded | SSO pipeline |
| `secret/network-vm/dev/active-slot` | *(same as bootstrap, legacy path)* | - | network-vm pipeline |

## Vault Authentication

**CI pipelines** use a limited-scope CI token (`VAULT_TOKEN` / `VAULT_PROD_TOKEN`) created by the vault-ct Ansible playbook. Policy: read/write `secret/*`, manage tokens.

**Admin operations** (enabling auth methods, writing policies) require the root token. The root token is stored at `/root/vault-init.json` on the vault CT itself (mode 0400). On each vault-ct deploy, the root token is also saved to `VAULT_DEV_ROOT_TOKEN` / `VAULT_ROOT_TOKEN` GitHub secrets via `gh secret set`.

**OIDC login** (interactive, human use): after OIDC is configured, users log in via `vault login -method=oidc -address=http://192.168.50.245:8200` or through the Vault UI → Sign in with OIDC provider. Grants `admin` policy (full access).

## Vault OIDC Auth Method

Configured automatically by the `configure-vault-oidc` workflow after every vault-ct deploy.

| Setting | Value |
|---------|-------|
| Discovery URL | `http://192.168.50.247:9000/application/o/vault/` (dev) |
| Default role | `admin` |
| User claim | `sub` |
| Policy | `admin` (full access — appropriate for homelab) |
| Token TTL | 12h |

Allowed redirect URIs (configured in both Vault and Authentik):
- `http://192.168.50.245:8200/ui/vault/auth/oidc/oidc/callback`
- `http://192.168.50.246:8200/ui/vault/auth/oidc/oidc/callback`
- `http://192.168.50.145:8200/ui/vault/auth/oidc/oidc/callback`
- `http://192.168.50.146:8200/ui/vault/auth/oidc/oidc/callback`
- `https://vault-dev.databaes.net/ui/vault/auth/oidc/oidc/callback`
- `https://vault.databaes.net/ui/vault/auth/oidc/oidc/callback`
- `http://localhost:8250/oidc/callback`
- `http://localhost:8200/oidc/callback`

## Vault Unsealing

Vault uses Shamir secret sharing: **3 shares, threshold 2**. Two unseal keys are stored at `/etc/vault.d/.unseal_keys` on the vault CT itself. The `vault-unseal` systemd service runs on boot and unseals automatically using these keys.

This means the vault auto-unseals after a reboot but the unseal keys are on the same host — acceptable for a homelab, not suitable for production security requirements.

## What Survives a vault-ct Redeploy

| Secret | Survives? | How |
|--------|-----------|-----|
| Tailscale, AdGuard, WireGuard, Cloudflare tunnel | ✅ Yes | Seeded from bootstrap vault |
| Authentik OIDC credentials | ✅ Yes | Seeded from bootstrap vault → OIDC method configured by `configure-oidc` job |
| Vault OIDC auth method config | ✅ Yes | `configure-oidc` job runs post-deploy |
| `secret/sso` (Authentik db/app secrets) | ❌ No | Must re-run SSO pipeline to regenerate |

## GitHub Secrets Reference

| Secret | Vault | Purpose |
|--------|-------|---------|
| `VAULT_DEV_ADDR` | Bootstrap | Bootstrap vault address |
| `VAULT_DEV_TOKEN` | Bootstrap | Bootstrap vault CI token |
| `VAULT_ADDR` | Dev | Dev env vault address |
| `VAULT_TOKEN` | Dev | Dev env vault CI token |
| `VAULT_PROD_ADDR` | Prod | Prod env vault address |
| `VAULT_PROD_TOKEN` | Prod | Prod env vault CI token |
| `VAULT_DEV_ROOT_TOKEN` | Dev | Dev vault root token (updated on vault-ct deploy) |
| `VAULT_ROOT_TOKEN` | Prod | Prod vault root token (updated on vault-ct deploy) |
| `VAULT_BOOTSTRAP_ROOT_TOKEN` | Bootstrap | Bootstrap vault root token |