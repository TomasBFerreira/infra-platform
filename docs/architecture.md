# Architecture Overview

## Stack

```
GitHub Actions (two-tier self-hosted runner setup)
    ├── CT 200 (bootstrap vault): management runner — label [self-hosted, management]
    │       Runs the github-runner pipeline only; stable anchor that survives env destruction
    ├── CT 201/101/301 (env runners): env runners — label [self-hosted, linux, <env>]
    │       Run all other pipelines for their respective env
    ├── Terraform  — provisions Proxmox LXC containers (Docker or direct binary fallback)
    ├── Ansible    — configures services inside containers
    └── gh CLI     — manages secrets, triggers workflows

Proxmox (3 nodes)
    ├── benedict  192.168.50.4   dev node
    ├── heaton    192.168.50.8   qa node
    └── betsy     192.168.50.2   prod node

Services (all LXC containers, Debian 12)
    ├── vault-ct      — HashiCorp Vault (secrets management)
    ├── network-vm    — Traefik reverse proxy + AdGuard DNS + cloudflared tunnel
    └── sso           — Authentik (OIDC identity provider)
```

## Design Principles

**Blue/Green deployments everywhere.** Every service runs in two slots (blue/green). The pipeline deploys to the inactive slot, validates it, then atomically flips the active pointer in the bootstrap vault. The old active slot is destroyed. This gives zero-downtime deploys and instant rollback (just flip the pointer back).

**Vault as source of truth for runtime secrets.** All service credentials (Tailscale keys, AdGuard passwords, WireGuard keys, OIDC client secrets) live in Vault, not in environment variables or config files on disk. Pipelines fetch secrets at deploy time and inject them as Ansible variables.

**Bootstrap vault is the stable anchor.** A permanently-running vault on CT 200 stores SSH keys, slot state, and shared infra secrets. It never gets blue/green deployed — if it goes down, nothing can deploy, but running services are unaffected.

**Management runner on bootstrap vault.** CT 200 also runs a permanent GitHub Actions runner with the `management` label. The github-runner pipeline runs on this runner so it can rebuild any env runner (including CT 201) from scratch — even after a full env teardown. All other pipelines run on the env-specific runners (CT 201 for dev, etc.).

**Critical infra starts first on host reboot.** `vault-ct`, `network-vm`, and `sso` have `onboot = true` and Proxmox startup order configured (`vault-ct` order 1, `network-vm` order 2, `sso` order 3, each with a 30 s `up_delay`). This ensures secrets, networking, and authentication are available before any downstream services attempt to start.

**GitOps for Traefik.** The `traefik-gitops` repo is the single source of truth for routing rules. Committing a new router automatically deploys the config to the active network-vm and creates the Cloudflare DNS CNAME.

## Data Flow on a Deploy

```
1. resolve-slots    reads bootstrap vault → determines staging slot (blue/green)
2. terraform-staging  provisions new LXC on Proxmox
3. configure-tun    (network-vm only) sets up TUN device for Docker
4. ansible-staging  configures the service:
                      - fetches secrets from env vault
                      - fetches SSH keys from bootstrap vault
                      - installs and starts the service
5. flip-active      writes new slot to bootstrap vault → traffic switches
6. configure-oidc   (vault-ct only) configures Vault OIDC auth post-deploy
7. teardown-old-active  destroys the previous active LXC
```

## Secret Seeding on vault-ct Deploy

When the env vault is redeployed, the Ansible playbook re-seeds it from the bootstrap vault:

```
Bootstrap vault (CT 200, permanent)
    secret/tailscale              → seeded into env vault
    secret/wireguard              → seeded into env vault (prod only)
    secret/adguard                → seeded into env vault
    secret/cloudflare-tunnel      → seeded into env vault (prod only)
    secret/authentik/<env>/vault-oidc → seeded into env vault

After seeding, configure-oidc job runs:
    → enables OIDC auth method on vault
    → creates admin policy + role
    → updates Authentik redirect_uris
```