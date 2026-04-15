# Network & Routing

## Proxmox Nodes

| Node | IP | Role |
|------|----|------|
| benedict | 192.168.50.4 | dev |
| heaton | 192.168.50.8 | qa |
| betsy | 192.168.50.2 | prod |

Proxmox nodes remain on the management network (`192.168.50.0/24`, gateway `192.168.50.1`). Services run on per-environment subnets.

## VMID and IP Scheme

Services run on per-environment /24 subnets. Proxmox nodes and the bootstrap vault remain on the management network (192.168.50.0/24).

| Env  | Service subnet   | Gateway      | Bridge |
|------|-----------------|--------------|--------|
| prod | 192.168.10.0/24 | 192.168.10.1 | vmbr10 |
| dev  | 192.168.20.0/24 | 192.168.20.1 | vmbr20 |
| qa   | 192.168.30.0/24 | 192.168.30.1 | vmbr30 |

IP last-octet = VMID last 2 digits (e.g. VMID 245 → .45). Exception: github-runner (x01 → .101).

| Service | Env | Blue VMID | Blue IP | Green VMID | Green IP |
|---------|-----|-----------|---------|------------|----------|
| vault-ct | prod | 145 | 192.168.10.45 | 146 | 192.168.10.46 |
| vault-ct | dev | 245 | 192.168.20.45 | 246 | 192.168.20.46 |
| vault-ct | qa | 345 | 192.168.30.45 | 346 | 192.168.30.46 |
| network-vm | prod | 155 | 192.168.10.55 | 156 | 192.168.10.56 |
| network-vm | dev | 255 | 192.168.20.55 | 256 | 192.168.20.56 |
| network-vm | qa | 355 | 192.168.30.55 | 356 | 192.168.30.56 |
| sso | prod | 175 | 192.168.10.75 | 176 | 192.168.10.76 |
| sso | dev | 275 | 192.168.20.75 | 276 | 192.168.20.76 |
| torrent | prod | 165 | 192.168.10.65 | 166 | 192.168.10.66 |
| torrent | dev | 265 | 192.168.20.65 | 266 | 192.168.20.66 |
| semaphore | dev | 285 | 192.168.20.85 | 286 | 192.168.20.86 |
| bootstrap vault | mgmt | 200 | 192.168.50.200 | - | - |

### Worker Nodes — Numbered Singletons

`VMID = env_base + N`, `IP = 192.168.<env_subnet>.(VMID last 2 digits)`.

| Node | VMID | IP | Proxmox host | Status |
|------|------|----|--------------|--------|
| worker-node-01 (prod) | 111 | 192.168.10.11 | betsy | existing (manual, pending pipeline migration) |
| worker-node-01 (dev)  | 211 | 192.168.20.11 | benedict | pipeline-managed |

### Singletons (GitHub Runner, Rancher)

| Service | Env | VMID | IP |
|---------|-----|------|----|
| github-runner | prod | 101 | 192.168.10.101 |
| github-runner | dev  | 201 | 192.168.20.101 |
| github-runner | qa   | 301 | 192.168.30.101 |
| rancher | prod | 102 | 192.168.10.2 |
| rancher | dev  | 202 | 192.168.20.2 |
| rancher | qa   | 302 | 192.168.30.2 |

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

## k3s cluster DNS — trailing-dot gotcha

Pods on the dev k3s worker get a `/etc/resolv.conf` search path ending with `databaes.net`:

```
search <ns>.svc.cluster.local svc.cluster.local cluster.local databaes.net
nameserver 10.43.0.10
options ndots:5
```

The `databaes.net` entry is injected from the worker host's DNS config (via AdGuard / the dev network-vm) and it matters because **Cloudflare serves a wildcard on `*.databaes.net`**:

```
$ dig +short anything.databaes.net
104.21.82.172
172.67.160.61
```

Any name the resolver falls through on — including a fully-qualified cluster service name that happens to have fewer than `ndots:5` dots — eventually hits `<name>.databaes.net` and gets a Cloudflare public IP back, pointing your in-cluster client at the public internet. The pod then sees "network unreachable" because there is no egress to that Cloudflare IP from the worker subnet.

### Rule: use absolute FQDNs for in-cluster service URLs

Always include the trailing dot when a service config file (Vault secret, k8s ConfigMap, env var) stores a `*.svc.cluster.local` hostname:

```
nats://nats.ops-portal-nats.svc.cluster.local.:4222    # CORRECT (absolute, stops search expansion)
nats://nats.ops-portal-nats.svc.cluster.local:4222     # WRONG — resolver walks the search path, hits Cloudflare
```

The trailing dot makes the name absolute, so `ndots:5` logic doesn't trigger search expansion at all. Equivalent fixes: (a) use just the service name `nats` (resolves via the first search entry), but that only works for pods in the same namespace; (b) add `options ndots:0` to the pod's `dnsConfig`, but that's cluster-wide surgery and not worth it for a few service URLs.

**Checked-in URLs that follow this rule:**
- `secret/ops-portal/<env>/nats` in Vault — `url` field MUST end with a dot.
- Any future service-to-service URL we add.

See `ops-portal-cmdb/cluster-bootstrap/nats/README.md` for the originating incident (slice 2, 2026-04-15).

### Same wildcard, different shape: external hostnames also break

The same Cloudflare wildcard catches **external** hostnames that have fewer than `ndots:5` dots and get search-expanded. Example: `api.anthropic.com` has 2 dots; with `ndots:5`, the resolver tries every search-path suffix first, and `api.anthropic.com.databaes.net` matches the wildcard and returns the Cloudflare IP — so the pod tries to dial `104.21.82.172` for Anthropic and gets "host is unreachable".

Fix per pod: lower `ndots` to **1** in the deployment's `dnsConfig`:

```yaml
spec:
  template:
    spec:
      dnsPolicy: ClusterFirst
      dnsConfig:
        options:
          - name: ndots
            value: "1"
```

With `ndots: 1`, any name containing at least one dot is tried as-is first, so external resolution wins. Cluster-internal short names (e.g. `nats` or `postgres` for same-namespace services) have zero dots and still walk the search path correctly.

**Don't use `ndots: 2`** — that was the first fix attempt during slice 4 (only `api.anthropic.com`-shaped 2-dot names worked), and it bit slice 6 the moment a service tried to reach `github.com` (1 dot, falls into the search path again). The deployments service standardised on `ndots: 1`; backport to any pod that talks to short external hostnames.

The `ops-portal-deployments` and `ops-portal-incidents` deployments carry this dnsConfig. Copy it into any service that calls a public API (Anthropic, GitHub, Cloudflare, Tailscale, etc.). Long-term the cleanest fix is a CoreDNS rewrite/ndots tweak at the cluster level — tracked but not implemented.

See `ops-portal-deployments/manifests/base/deployment.yaml` for the live reference (which also documents the rationale inline).

## Worker-to-Proxmox NFS routing

The dev k3s worker (`192.168.20.11`) lives on `192.168.20.0/24` and does **not** have a route to `192.168.50.0/24`. That means:

| From worker to… | IP to use | Why |
|---|---|---|
| benedict (the worker's Proxmox host) | `192.168.20.1` (benedict's vmbr20 interface) | benedict is the gateway for vmbr20; same host, different IP. |
| benedict over management | `192.168.50.4` | ❌ unreachable from the worker — management subnet isn't routed over. |
| bootstrap vault | `192.168.50.200` | ❌ unreachable from pods; only the runner LXC (on management-adjacent routing) can reach it. |

NFS exports from benedict are bound to `192.168.0.0/16` so they listen on both `192.168.50.4` *and* `192.168.20.1`. When a cluster workload mounts NFS (e.g. the `nfs-subdir-external-provisioner` Deployment), its `server:` field **must** be `192.168.20.1`, not `192.168.50.4`.

See `ansible/benedict_ops_portal_nfs_setup.yml` for the export definition and `ops-portal-identity/cluster-bootstrap/nfs-subdir-provisioner/deployment.yaml` for the consumer side that uses `192.168.20.1`.

## WireGuard

WireGuard is configured on the **prod** network-vm only, providing a VPN tunnel for secure access. Keys are stored in `secret/wireguard` in the prod env vault and seeded from the bootstrap vault at deploy time. Dev network-vm does not use WireGuard.

## Tailscale

All LXC containers join the Tailscale network using an authkey from `secret/tailscale` in the env vault. This allows the runner and other services to reach each other over Tailscale IPs regardless of which blue/green slot is active.

The network-vm acts as a Tailscale subnet router and advertises all four subnets: `192.168.10.0/24,192.168.20.0/24,192.168.30.0/24,192.168.50.0/24` (all three env service subnets plus the management subnet). This ensures full reachability across all envs over Tailscale.