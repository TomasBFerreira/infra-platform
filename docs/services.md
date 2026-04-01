# Services

## Authentik (SSO)

**Purpose:** OIDC identity provider. Provides single sign-on for Vault and (future) other services via Traefik forwardAuth.

| | Dev | Prod |
|-|-----|------|
| Active IP | 192.168.20.75 (blue) or .76 (green) | 192.168.10.75 or .76 |
| UI | `http://192.168.20.75:9000` | `http://192.168.10.75:9000` |
| Public URL | `https://auth-dev.databaes.net` | `https://auth.databaes.net` (not yet) |
| Active slot | `secret/sso/dev/active-slot` in bootstrap vault | `secret/sso/prod/active-slot` |

**Default admin:** `akadmin` / password in `secret/sso.bootstrap_password` in env vault (also copied to bootstrap vault via `fetch-sso-password` workflow for convenience).

**OAuth2 Providers configured:**
- `Vault` — client credentials in `secret/authentik/vault-oidc` in env vault

**Traefik forwardAuth middleware:**
- `authentik-dev` middleware defined in `services.yml` points to `http://192.168.20.75:9000/outpost.goauthentik.io/auth/traefik`
- Attach to any Traefik router to gate it behind SSO

**Known quirks:**
- Uses `network_mode: host` for all Docker containers (required for unprivileged LXC + Proxmox — avoids `net.ipv4.ip_unprivileged_port_start` sysctl restriction)
- Inter-container communication uses `127.0.0.1` instead of container names as a result
- Bootstrap token mechanism: `AUTHENTIK_BOOTSTRAP_TOKEN` env var relies on Celery background task (unreliable). Instead, the pipeline creates the token directly via `docker exec authentik-server ak shell` + Django ORM.
- API authentication: `Authorization: Bearer <token>` (not `Token`)
- `redirect_uris` format in Authentik 2024.x: list of `{url: "...", matching_mode: "strict"}` dicts (not a newline-delimited string as in older docs)

---

## HashiCorp Vault

**Purpose:** Secrets management. Stores all infrastructure credentials. Provides OIDC-based human login.

| | Dev | Prod |
|-|-----|------|
| Active IP | 192.168.20.45 (blue) or .46 (green) | 192.168.10.45 or .46 |
| UI | `http://192.168.20.45:8200` | `http://192.168.10.45:8200` |
| Public URL | `https://vault-dev.databaes.net` | `https://vault.databaes.net` |
| Active slot | `secret/vault-ct/dev/active-slot` in bootstrap vault | `secret/vault-ct/prod/active-slot` |

**Storage backend:** Filesystem (not Raft). Single-node. No replication.

**Unsealing:** Automatic via `vault-unseal.service` systemd unit on boot. Unseal keys at `/etc/vault.d/.unseal_keys` (2 of 3 shares required). Root token at `/root/vault-init.json` (mode 0400).

**Auth methods:**
- `token` — default, used by CI pipelines
- `oidc` — human login via Authentik. Role: `admin`. Policy: full access.

**Login (interactive):**
```bash
# Via CLI
vault login -method=oidc -address=http://192.168.20.45:8200

# Via UI
# Go to http://192.168.20.45:8200 → Sign in with OIDC provider
```

**Traefik routing:**
- `vault-dev.databaes.net` → Traefik health-checks both .20.45 and .20.46; routes to whichever returns HTTP 200 on `/v1/sys/health` (active node returns 200, down/standby returns non-200)

---

## network-vm

**Purpose:** Network services — Traefik reverse proxy, AdGuard Home DNS resolver, Cloudflare tunnel, WireGuard VPN (prod only).

| | Dev | Prod |
|-|-----|------|
| Active IP | 192.168.20.55 or .56 | 192.168.10.55 or .56 |
| Active slot | `secret/network-vm/dev/active-slot` in bootstrap vault | `secret/network-vm/prod/active-slot` |

**Services running:**
- **Traefik** — Docker container with `network_mode: host`. Config at `/opt/traefik/`. Hot-reloads on `services.yml` changes via file provider watch.
- **AdGuard Home** — DNS resolver for the homelab. Credentials from `secret/adguard` in env vault.
- **cloudflared** — Cloudflare tunnel daemon. Managed by systemd. `TimeoutStartSec=90` to handle slow boot-time DNS resolution. Ingress rules configured in Cloudflare Zero Trust dashboard (not locally).
- **WireGuard** — prod only. Keys from `secret/wireguard` in prod env vault.
- **Tailscale** — joins Tailscale network for inter-service connectivity.

**Adding a new public-facing service:**
1. Edit `traefik-gitops/config/dynamic/services.yml` — add router + service
2. Commit to `main` → deploy.yml and sync-dns.yml run automatically
3. Service is reachable at `https://<name>.databaes.net` within ~30 seconds

**Traefik forwardAuth (Authentik SSO):**
To protect a service with SSO, add to its router:
```yaml
middlewares:
  - authentik-dev  # or authentik (prod)
```
Then configure the corresponding Proxy Provider in the Authentik UI (Admin → Applications → Providers → Proxy Provider).

---

## Self-Hosted Runner (CT 200)

**Purpose:** GitHub Actions self-hosted runner. Executes all CI/CD jobs.

| | Value |
|-|-------|
| IP | 192.168.50.200 |
| Runner directory | `/app/actions-runner` |
| Working directory | `/app/infra-platform` |
| traefik-gitops | `/app/traefik-gitops` |

The runner has direct network access to all CTs on `192.168.50.0/24`, the Proxmox API, and the bootstrap vault. It also has `gh` CLI, `vault` CLI, `terraform` (via Docker), and `ansible` installed.

**Runner service:**
```bash
cd /app/actions-runner
sudo ./svc.sh status   # check
sudo ./svc.sh start    # start
sudo ./svc.sh stop     # stop
```