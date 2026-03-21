# Network & Routing

## Proxmox Nodes

| Node | IP | Role |
|------|----|------|
| benedict | 192.168.50.4 | dev |
| vladimir | 192.168.50.4 | qa |
| betsy | 192.168.50.2 | prod |

All nodes share `192.168.50.0/24`, gateway `192.168.50.1`.

## VMID and IP Scheme

| Service | Env | Blue VMID | Blue IP | Green VMID | Green IP |
|---------|-----|-----------|---------|------------|----------|
| vault-ct | prod | 145 | 192.168.50.145 | 146 | 192.168.50.146 |
| vault-ct | dev | 245 | 192.168.50.245 | 246 | 192.168.50.246 |
| vault-ct | qa | 345 | 192.168.50.243 | 346 | 192.168.50.244 |
| network-vm | prod | 155 | 192.168.50.155 | 156 | 192.168.50.156 |
| network-vm | dev | 255 | 192.168.50.250 | 256 | 192.168.50.251 |
| network-vm | qa | 355 | 192.168.50.240 | 356 | 192.168.50.241 |
| sso | prod | 175 | 192.168.50.175 | 176 | 192.168.50.176 |
| sso | dev | 275 | 192.168.50.247 | 276 | 192.168.50.248 |
| runner | - | 200 | 192.168.50.200 | - | - |

> **Note:** QA uses .243/.244 instead of .245/.246 since dev owns those.

### Worker Nodes — Numbered Singletons

Worker nodes do not follow the blue/green dual-slot pattern. Each is a permanent VM numbered sequentially: `VMID = 110 + N`, `IP = 192.168.50.(110+N)`. Kubernetes provides workload resilience at the application layer.

| Node | VMID | IP | Proxmox host | Status |
|------|------|----|--------------|--------|
| worker-node-01 | 111 | 192.168.50.111 | betsy | existing (manual, pending pipeline migration) |
| worker-node-02 | 112 | 192.168.50.112 | benedict | pipeline-managed (dev) |

## Cloudflare Tunnels

Two tunnels exist — one for prod, one for dev. All external traffic enters via Cloudflare, terminating at the appropriate network-vm.

| Tunnel | Handles | Points at |
|--------|---------|-----------|
| Prod tunnel (`6eff4426-...`) | `*.databaes.net` (non-dev subdomains) | prod network-vm Traefik |
| Dev tunnel (`80b044ef-...`) | `*-dev.databaes.net` subdomains | dev network-vm Traefik |

DNS is managed automatically: adding a router to `services.yml` in `traefik-gitops` triggers `sync-dns.yml` which creates the Cloudflare CNAME. Domains matching `*-dev.*` get the dev tunnel CNAME; all others get the prod tunnel CNAME.

### Tunnel Token Storage

| Token | Stored in |
|-------|-----------|
| Prod tunnel | `secret/cloudflare-tunnel` in prod env vault (seeded from bootstrap vault) |
| Dev tunnel | `CLOUDFLARE_DEV_TUNNEL_TOKEN` GitHub secret (infra-platform repo) |

## Traefik

Traefik runs inside Docker on the network-vm (all four containers use `network_mode: host`).

**Config locations on the network-vm:**
```
/opt/traefik/
    traefik.yml              # main config (entrypoints, providers)
    config/dynamic/
        services.yml         # routers + services (managed by traefik-gitops)
```

**Entrypoints:**
- `web` — port 80 (all current routers use this; Cloudflare handles TLS termination)

**Source of truth:** `traefik-gitops` repo, `config/dynamic/services.yml`. Changes are deployed automatically on push via the `deploy.yml` workflow (scps to active network-vm IP looked up from bootstrap vault).

### Adding a New Service

1. Add a router + service to `services.yml` in `traefik-gitops`
2. Commit and push to `main`
3. `deploy.yml` SCPs the config to the active dev network-vm (Traefik hot-reloads)
4. `sync-dns.yml` creates the Cloudflare CNAME automatically
5. To deploy to prod, re-run `Deploy Traefik Config` with `deploy_prod: true`

## AdGuard Home (DNS)

AdGuard runs on the network-vm and serves as the internal DNS resolver for the homelab. Credentials are seeded from the bootstrap vault (`secret/adguard`) at deploy time.

## WireGuard

WireGuard is configured on the **prod** network-vm only, providing a VPN tunnel for secure access. Keys are stored in `secret/wireguard` in the prod env vault and seeded from the bootstrap vault at deploy time. Dev network-vm does not use WireGuard.

## Tailscale

All LXC containers join the Tailscale network using an authkey from `secret/tailscale` in the env vault. This allows the runner and other services to reach each other over Tailscale IPs regardless of which blue/green slot is active.