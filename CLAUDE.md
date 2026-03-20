# infra-platform

Proxmox homelab infrastructure managed via Terraform + Ansible + GitHub Actions on a self-hosted runner at `/app/infra-platform`.

## Proxmox nodes

| Node      | IP              | Role |
|-----------|-----------------|------|
| benedict  | 192.168.50.4    | dev  |
| vladimir  | 192.168.50.4    | qa   |
| betsy     | 192.168.50.2    | prod |

All nodes share the `192.168.50.0/24` subnet, gateway `192.168.50.1`.

## VMID and IP scheme

| Env  | Prefix | Blue VMID | Blue IP         | Green VMID | Green IP        |
|------|--------|-----------|-----------------|------------|-----------------|
| prod | 1xx    | x45       | 192.168.50.x45  | x46        | 192.168.50.x46  |
| dev  | 2xx    | x45       | 192.168.50.x45  | x46        | 192.168.50.x46  |
| qa   | 3xx    | x45       | 192.168.50.x43* | x46        | 192.168.50.x44* |

*QA IPs use .243/.244 since dev owns .245/.246.

Existing assignments:
- vault-ct: prod=145/146 (.145/.146), dev=245/246 (.245/.246), qa=345/346 (.243/.244)
- network-vm: prod=155/156 (.155/.156), dev=255/256 (.250/.251), qa=355/356 (.240/.241)
- torrent: prod=165/166 (.165/.166), dev=265/266 (.252/.253)
- sso: prod=175/176 (.175/.176), dev=275/276 (.247/.248)

## Vault architecture

- **Bootstrap vault** (CT 200, always stable): stores SSH keys and slot state for all envs. Credentials: `VAULT_DEV_ADDR` / `VAULT_DEV_TOKEN` GitHub secrets.
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

The Terraform Vault provider always uses the **bootstrap vault** (`VAULT_DEV_ADDR`/`VAULT_DEV_TOKEN`) to fetch SSH keys — these are infra-level secrets shared across envs.

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
| VAULT_DEV_ADDR        | Bootstrap vault address (CT 200)             |
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
| PVE_PASS              | Proxmox password                             |
| SSH_USER              | Default SSH user for CTs                     |
| GH_PAT                | GitHub PAT for setting secrets via gh CLI    |
