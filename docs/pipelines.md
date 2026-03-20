# CI/CD Pipelines

All pipelines run on the self-hosted runner at CT 200 (192.168.50.200). Trigger via GitHub Actions → workflow_dispatch, selecting the target environment.

## vault-ct Pipeline

**File:** `.github/workflows/vault-ct_pipeline_self_hosted.yml`
**Purpose:** Deploy HashiCorp Vault (blue/green)

### Jobs

| Job | What it does |
|-----|-------------|
| `resolve-slots` | Reads active slot from bootstrap vault, computes staging slot |
| `terraform-staging` | Destroys stale staging CT (pre-flight), provisions new LXC |
| `ansible-staging` | Installs Vault, initialises it, seeds secrets from bootstrap vault, creates CI token + policy |
| `flip-active` | Writes new slot to bootstrap vault, updates `VAULT_ADDR`/`VAULT_TOKEN` GH secrets |
| `configure-oidc` | Enables Vault OIDC auth, creates admin role, updates Authentik redirect_uris |
| `teardown-old-active` | Destroys previous active CT |
| `cleanup-on-failure` | Destroys staging CT if any job fails |

### When to run

- On first setup of a new environment
- When the Vault binary needs upgrading (change version in Ansible vars)
- After a vault CT failure that requires reprovisioning
- **Note:** Running this pipeline wipes and recreates Vault. All non-seeded secrets (`secret/sso`) will be lost. The SSO pipeline must be re-run after vault-ct if Authentik secrets are wiped.

### Ansible secrets seeded automatically

Tailscale, AdGuard, WireGuard (prod), Cloudflare tunnel (prod), Authentik OIDC credentials. See [vaults.md](vaults.md) for the full inventory.

---

## network-vm Pipeline

**File:** `.github/workflows/network-vm_pipeline_self_hosted.yml`
**Purpose:** Deploy the network services VM (Traefik + AdGuard + cloudflared + WireGuard)

### Jobs

| Job | What it does |
|-----|-------------|
| `resolve-slots` | Reads active slot from bootstrap vault |
| `terraform-staging` | Provisions new LXC |
| `configure-tun-staging` | Creates `/dev/net/tun` on the Proxmox host for Docker networking |
| `ansible-staging` | Installs Docker, Traefik, AdGuard, cloudflared, WireGuard (prod), Tailscale |
| `flip-active` | Updates slot in bootstrap vault |
| `teardown-old-active` | Destroys old CT |
| `cleanup-on-failure` | Destroys staging CT on failure |

### Tunnel tokens

| Environment | Token source |
|-------------|-------------|
| `prod` | `secret/cloudflare-tunnel` in prod env vault |
| `dev` | `CLOUDFLARE_DEV_TUNNEL_TOKEN` GitHub secret |

### Traefik config

Deployed from `ansible/network-vm/roles/traefik/files/dynamic/services.yml` (kept in sync with `traefik-gitops` repo). Subsequent config changes are pushed via the `traefik-gitops` deploy workflow, not this pipeline.

---

## SSO Pipeline

**File:** `.github/workflows/sso_pipeline_self_hosted.yml`
**Purpose:** Deploy Authentik (OIDC identity provider)

### Jobs

| Job | What it does |
|-----|-------------|
| `resolve-slots` | Reads active SSO slot |
| `generate-secrets` | Generates Authentik db password, secret key, bootstrap password + token; stores in env vault at `secret/sso` |
| `terraform-staging` | Provisions new LXC |
| `ansible-staging` | Installs Docker, deploys Authentik (4 containers: postgresql, redis, server, worker), creates Vault OAuth2 provider + application, stores OIDC creds in env vault AND bootstrap vault |
| `flip-active` | Updates slot in bootstrap vault |
| `teardown-old-active` | Destroys old CT |
| `cleanup-on-failure` | Destroys staging CT on failure |

### Authentik containers

All four run with `network_mode: host` (required for unprivileged LXC on Proxmox — avoids sysctl permission issues):

| Container | Port |
|-----------|------|
| `authentik-server` | 9000 (HTTP) |
| `authentik-worker` | (no external port) |
| `authentik-postgresql` | 5432 |
| `authentik-redis` | 6379 |

### Key Ansible facts

- Bootstrap token: created via `docker exec authentik-server ak shell` Python script — bypasses the unreliable Celery background task mechanism
- API calls use `Authorization: Bearer <token>` (not `Token`)
- `redirect_uris` format in Authentik 2024.x: list of `{url, matching_mode}` dicts

---

## configure-vault-oidc Workflow

**File:** `.github/workflows/configure-vault-oidc.yml`
**Purpose:** Configure Vault's OIDC auth method (runs automatically after vault-ct deploy; also available as standalone `workflow_dispatch`)

### Steps

1. Fetch SSH keys from bootstrap vault; resolve active vault + SSO IPs
2. SSH into vault CT → read root token from `/root/vault-init.json` (fast path) or generate a new root token using unseal keys at `/etc/vault.d/.unseal_keys` (slow path)
3. Enable OIDC auth method, write config + admin policy + admin role (all redirect URIs)
4. SSH into SSO CT → get a fresh Authentik API token via `docker exec authentik-server ak shell`
5. PATCH the Vault OAuth2 provider's `redirect_uris` in Authentik to include domain-based URIs

---

## traefik-gitops Workflows

**Repo:** `traefik-gitops`

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `deploy.yml` | Push to `config/**` or `workflow_dispatch` | SCPs `services.yml` to active dev network-vm; optionally deploys to prod |
| `sync-dns.yml` | Push to `config/dynamic/services.yml` | Diffs added/removed routers vs previous commit; creates/deletes Cloudflare CNAMEs |
| `backfill-dns.yml` | `workflow_dispatch` | Creates/updates ALL CNAMEs for every router in `services.yml` (idempotent) |

### DNS routing logic

Domains matching `*-dev.*` → dev tunnel CNAME (`CLOUDFLARE_DEV_TUNNEL_HOSTNAME`)
All other domains → prod tunnel CNAME (`CLOUDFLARE_TUNNEL_HOSTNAME`)

---

## Helper / Utility Workflows

| Workflow | Purpose |
|----------|---------|
| `configure-vault-oidc.yml` | Configure OIDC on existing vault without full redeploy |
| `backfill-bootstrap-vault.yml` | Copy OIDC creds from env vault → bootstrap vault (one-time backfill) |
| `fetch-sso-password.yml` | Copy SSO bootstrap password to bootstrap vault for easy access |
| `setup-dev-tunnel-hostname.yml` | Decode dev tunnel JWT → store hostname as GH secret in traefik-gitops |
| `debug-network-vm.yml` | SSH into dev network-vm, check Traefik/cloudflared health and logs |