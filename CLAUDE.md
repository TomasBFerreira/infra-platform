# Rules

1. **All changes must be made on a branch** — never commit directly to `main` or `master`. Create a descriptive branch before making any changes to a repo.
2. **Documentation must be updated with any infra, network, or app changes** — if you add, modify, or remove anything in the infrastructure, network, application, or any other critical part of the homelab, update the relevant documentation (runbooks, CLAUDE.md, or other docs) in the same PR.

## New app onboarding checklist

Every new app/service being onboarded must satisfy all of the following before it is considered complete:

3. **Deploy on a worker node or static host** — must be provisioned on a Proxmox worker node (benedict/vladimir/betsy) or a designated static host. Ad-hoc deployments directly on the hypervisor are not allowed.
4. **VMID and IP registration** — claim the next available VMID slot following the `1xx` (prod) / `2xx` (dev) / `3xx` (QA) prefix scheme and update the assignment table in this file. No unregistered or ad-hoc IPs.
5. **Blue/green pipeline** — every service must have a pipeline with all 6 standard jobs in order: `resolve-slots` → `terraform-staging` → `ansible-staging` → `flip-active` → `teardown-old-active` → `cleanup-on-failure`. Single-slot deployments are not allowed. Pipelines must use the shared env runner via `runs-on: [self-hosted, <env>]` (e.g. `[self-hosted, dev]`). Do not assume a personal dev machine or ad-hoc host. **Exception:** the `github-runner` pipeline uses `runs-on: [self-hosted, management]` (CT 200) so it can rebuild the env runner even after a full env teardown — never change it back to the env runner label.
6. **Authentik SSO** — the service must be gated behind Authentik via the Traefik `forwardAuth` middleware (`authentik-dev` / `authentik-prod`). Unauthenticated public exposure is not allowed unless explicitly approved.
7. **Cloudflare CNAME via traefik-gitops** — routing and the public CNAME must be added to the `TomasBFerreira/traefik-gitops` repo (`config/dynamic/services.yml`). Do not configure ingress directly in pipelines or hardcode hostnames elsewhere.
8. **Vault secrets structure** — SSH keys go in the bootstrap vault at `secret/ssh_keys/<service>_worker`. Application secrets go in the env-specific vault. All secret paths must be documented in `docs/vaults.md`.
9. **Terraform/Ansible paths** — new services go in `terraform/<service>/` and `ansible/<service>/` (shared, env-injected via variables). The legacy `terraform/dev/<service>/` and `ansible/dev/<service>/` paths are frozen — nothing new goes there.
10. **LXC template** — use `local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst` unless there is a specific technical reason not to; any deviation must be documented.
11. **Standard users on every VM/LXC** — every Ansible playbook must create two users: `appadm` (owns the service — runs processes, owns files) and `tomas` (admin for interactive access, member of `sudo` group). No service should run as root, and no interactive access should rely solely on the root account.
12. **Register a GitHub Actions runner for every new repo** — any repo that needs CI/CD must have a runner registered on the shared env runner LXC. Use the `register-runner.yml` workflow in infra-platform (one-time per repo per env). See [docs/runbooks.md](docs/runbooks.md#registering-a-github-actions-runner-for-a-new-repo) for the full procedure.

---

# infra-platform

Proxmox homelab infrastructure managed via Terraform + Ansible + GitHub Actions on a self-hosted runner at `/app/infra-platform`.

## Proxmox nodes

| Node      | IP              | Role |
|-----------|-----------------|------|
| benedict  | 192.168.50.4    | dev  |
| vladimir  | 192.168.50.4    | qa   |
| betsy     | 192.168.50.2    | prod |

All nodes share the `192.168.50.0/24` management network (gateway `192.168.50.1`). Services run on per-environment subnets (see below).

## VMID and IP scheme

Each environment has its own /24 subnet. IP last octet = VMID last 2 digits (e.g., VMID 245 → .45), except github-runner (x01 → .101 to avoid gateway conflict).

| Env  | Prefix | Service subnet     | Gateway       | Bridge |
|------|--------|-------------------|---------------|--------|
| prod | 1xx    | 192.168.10.0/24   | 192.168.10.1  | vmbr10 |
| dev  | 2xx    | 192.168.20.0/24   | 192.168.20.1  | vmbr20 |
| qa   | 3xx    | 192.168.30.0/24   | 192.168.30.1  | vmbr30 |

Management network (Proxmox nodes, bootstrap vault): 192.168.50.0/24

Existing assignments:
- vault-ct: prod=145/146 (192.168.10.45/.46), dev=245/246 (192.168.20.45/.46), qa=345/346 (192.168.30.45/.46)
- network-vm: prod=155/156 (192.168.10.55/.56), dev=255/256 (192.168.20.55/.56), qa=355/356 (192.168.30.55/.56)
- torrent: prod=165/166 (192.168.10.65/.66), dev=265/266 (192.168.20.65/.66)
- sso: prod=175/176 (192.168.10.75/.76), dev=275/276 (192.168.20.75/.76)
- semaphore: prod=185/186 (192.168.10.85/.86), dev=285/286 (192.168.20.85/.86)

**Worker nodes — numbered singletons:**
- Prod (betsy):  VMID = 110+N, IP = 192.168.10.(10+N)  → 111→.11, 112→.12, 113→.13…
- Dev (benedict): VMID = 210+N, IP = 192.168.20.(10+N) → 211→.11, 212→.12, 213→.13…
- QA (vladimir):  VMID = 310+N, IP = 192.168.30.(10+N) → 311→.11, 312→.12, 313→.13…

Current nodes:
- worker-node-01 (dev):  VMID 211, IP 192.168.20.11 (benedict — pipeline-managed)
- worker-node-01 (prod): VMID 111, IP 192.168.10.11 (betsy — existing manual VM, pending pipeline migration)

**GPU worker nodes — numbered singletons (separate VMID range from regular worker nodes):**
- Prod (betsy):  VMID = 120+N, IP = 192.168.10.(20+N) → N=1: 121 → .21
- Dev (benedict): VMID = 220+N, IP = 192.168.20.(20+N) → N=1: 221 → .21
- QA (vladimir):  VMID = 320+N, IP = 192.168.30.(20+N) → N=1: 321 → .21

Current GPU nodes:
- worker-node-gpu-01 (prod): VMID 121, IP 192.168.10.21 (betsy — GTX 970 passthrough, IOMMU group 15, PCI 0000:26:00)

**GitHub Actions runners — env singletons:**
- github-runner-prod: VMID 101, IP 192.168.10.101 (betsy)
- github-runner-dev:  VMID 201, IP 192.168.20.101 (benedict)
- github-runner-qa:   VMID 301, IP 192.168.30.101 (vladimir)

**Rancher (K3s management plane) — env singletons:**
- rancher-prod: VMID 102, IP 192.168.10.2 (betsy)
- rancher-dev:  VMID 202, IP 192.168.20.2 (benedict)
- rancher-qa:   VMID 302, IP 192.168.30.2 (vladimir)

## Vault architecture

- **Bootstrap vault** (CT 200, always stable): stores SSH keys and slot state for all envs. Credentials: `VAULT_BOOTSTRAP_ADDR` / `VAULT_DEV_TOKEN` GitHub secrets.
- **Env vaults** (blue/green deployed): store application secrets (Tailscale, WireGuard, AdGuard, etc). Credentials: `VAULT_ADDR`/`VAULT_TOKEN` (dev), `VAULT_QA_ADDR`/`VAULT_QA_TOKEN` (qa), `VAULT_PROD_ADDR`/`VAULT_PROD_TOKEN` (prod).
- **Root tokens per env**: `VAULT_DEV_ROOT_TOKEN`, `VAULT_QA_ROOT_TOKEN`, `VAULT_PROD_ROOT_TOKEN` — used by the vault-ct pipeline on re-runs.

## Blue/green deployment pattern

Every service uses blue/green slots. Slot state is stored in the bootstrap vault at `secret/<service>/<env>/active-slot` with fields `slot`, `vmid`, `ip`.

Pipeline jobs (in order):
1. `resolve-slots` — reads active slot from bootstrap vault, computes staging slot
2. `terraform-staging` — destroys stale staging CT (pre-flight), applies new one
3. `ansible-staging` — configures the new CT
4. `flip-active` — writes new slot to bootstrap vault
5. `teardown-old-active` — destroys the previous active CT (skipped on first run)
6. `cleanup-on-failure` — destroys staging CT if any step failed

## Directory structure

```
terraform/<service>/        # Shared Terraform config (env injected via variables)
ansible/<service>/          # Shared Ansible playbooks
terraform/dev/<service>/    # Legacy — do not add new services here
ansible/dev/<service>/      # Legacy — do not add new services here
```

State files: `terraform/<service>/terraform.<slot>.<env>.tfstate` (local backend, on runner disk).

## Terraform execution

All Terraform runs go through Docker via `scripts/run-terraform.sh`. It mounts the repo as `/workspace` and passes env vars explicitly. Add new `TF_VAR_*` vars to both `run_terraform` and `run_terraform_with_chdir` functions in that script.

The Terraform Vault provider always uses the **bootstrap vault** (`VAULT_BOOTSTRAP_ADDR`/`VAULT_DEV_TOKEN`) to fetch SSH keys — these are infra-level secrets shared across envs.

## Ansible conventions

- SSH keys are fetched from the bootstrap vault at `secret/ssh_keys/<service>_worker`
- Application secrets are fetched from the env-specific vault
- `vault_env` and `vault_ct_ip` / `staging_ip` are passed as `-e` extra vars
- Locale env vars `LC_ALL=C.UTF-8` and `LANG=C.UTF-8` are always set

## LXC template

`local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst` — must exist on each Proxmox node's local storage before deploying to that node.

## GitHub secrets reference

| Secret                | Purpose                                      |
|-----------------------|----------------------------------------------|
| VAULT_BOOTSTRAP_ADDR        | Bootstrap vault address (CT 200)             |
| VAULT_DEV_TOKEN       | Bootstrap vault CI token                     |
| VAULT_ADDR            | Dev vault address                            |
| VAULT_TOKEN           | Dev vault CI token                           |
| VAULT_QA_ADDR         | QA vault address                             |
| VAULT_QA_TOKEN        | QA vault CI token                            |
| VAULT_PROD_ADDR       | Prod vault address                           |
| VAULT_PROD_TOKEN      | Prod vault CI token                          |
| VAULT_DEV_ROOT_TOKEN  | Dev vault root token (vault-ct re-runs)      |
| VAULT_QA_ROOT_TOKEN   | QA vault root token (vault-ct re-runs)       |
| VAULT_PROD_ROOT_TOKEN | Prod vault root token (vault-ct re-runs)     |
| PVE_USER              | Proxmox user (e.g. root@pam)                 |
| PVE_PASS              | Proxmox password (dev/QA nodes — benedict/vladimir) |
| PVE_PROD_PASS         | Proxmox password (prod node — betsy)         |
| SSH_USER              | Default SSH user for CTs                     |
| GH_PAT                | GitHub PAT for setting secrets via gh CLI    |
