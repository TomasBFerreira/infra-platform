# Infrastructure Platform

Container-based infrastructure management using Terraform and Ansible with **separate** HashiCorp Vault for secrets management.

## Architecture

This platform uses Docker containers to provide a consistent, isolated environment for infrastructure operations:

- **Terraform Container**: `hashicorp/terraform:1.6.4` - Infrastructure provisioning
- **Ansible Container**: `quay.io/ansible/ansible-core:latest` - Configuration management  
- **Vault**: **Separate system** - Running independently at `http://localhost:8200`
- **GitHub Runner**: Self-hosted runner for CI/CD pipelines

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- SSH keys configured for target systems
- Access to Proxmox API (if using Proxmox provider)

### Setup

1. **Ensure Vault is running separately:**
```bash
# Check Vault status (should be running from separate repository)
curl http://localhost:8200/v1/sys/health
```

2. **Test infrastructure tools:**
```bash
# Test container access
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version
```

### Usage

#### Terraform Operations
```bash
# Initialize Terraform
./scripts/run-terraform.sh init

# Plan changes
./scripts/run-terraform.sh plan

# Apply changes
./scripts/run-terraform.sh apply

# Destroy infrastructure
./scripts/run-terraform.sh destroy
```

#### Ansible Operations
```bash
# Install collections
./scripts/run-ansible.sh galaxy collection install community.general

# Run playbook
./scripts/run-ansible.sh playbook -i inventory.yml playbook.yml

# Check connectivity
./scripts/run-ansible.sh inventory -i inventory.yml --list-hosts
```

## Project Structure

```
├── docker-compose.yml          # Container orchestration
├── scripts/
│   ├── run-terraform.sh       # Terraform container wrapper
│   ├── run-ansible.sh         # Ansible container wrapper
│   └── setup-github-runner.sh # GitHub runner setup
├── terraform/
│   └── dev/                   # Development environments
├── ansible/
│   └── dev/                   # Development playbooks
├── .github/workflows/         # CI/CD pipelines
└── docs/                      # Documentation
```

## Container Management

### Tool Containers
```bash
# Terraform and Ansible containers run on-demand via wrapper scripts
# They don't need to be running continuously

# Test container access
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version

# View running containers (should only see Vault if it's running)
docker ps
```

### Update Containers
```bash
# Pull latest versions
docker compose pull terraform ansible

# Test updated versions
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version
```

## GitHub Actions Integration

The platform includes self-hosted GitHub Actions workflows that use the container-based tools:

- `media-stack_pipeline_self_hosted.yml` - Media stack deployment
- `network-vm_pipeline_self_hosted.yml` - Network VM management

See `docs/GITHUB_RUNNER_SETUP.md` for complete setup instructions.

## Vault Integration

Vault is **managed separately** and runs independently at `http://localhost:8200`:

1. **External Vault**: Running from separate repository
2. **Secret Storage**: SSH keys, passwords, and configuration
3. **Integration**: Terraform and Ansible access Vault via host network

### Vault Operations
```bash
# Check Vault status (external)
curl http://localhost:8200/v1/sys/health

# Login (development token)
export VAULT_TOKEN=myroot
export VAULT_ADDR=http://localhost:8200

# List secrets
vault kv list secret/
```

## Security Considerations

- **Container Isolation**: Tools run in isolated containers
- **SSH Keys**: Mounted read-only into containers
- **Vault Token**: Use GitHub Secrets for production tokens
- **Network Access**: Containers communicate via dedicated network
- **Version Pinning**: Specific container versions are pinned

## Troubleshooting

### Container Issues
```bash
# Check container status
docker ps

# View logs
docker-compose logs [service]

# Restart containers
docker-compose restart [service]
```

### Permission Issues
```bash
# Check Docker group membership
groups $USER | grep docker

# Add user to docker group
sudo usermod -aG docker $USER
```

### Volume Issues
```bash
# Check volume mounts
docker-compose config | grep volumes

# Test SSH key access
docker-compose run --rm terraform ls -la /root/.ssh
```

## Development

### Adding New Terraform Modules
1. Create module in `terraform/dev/`
2. Update container volumes if needed
3. Test with `./scripts/run-terraform.sh`

### Adding New Ansible Playbooks
1. Create playbook in `ansible/dev/`
2. Update inventory files
3. Test with `./scripts/run-ansible.sh`

### Container Customization
Edit `docker-compose.yml` to:
- Change container versions
- Add environment variables
- Modify volume mounts
- Adjust network settings

## Benefits of Container-Based Approach

- ✅ **Version Isolation**: Exact tool versions pinned in containers
- ✅ **Clean Host**: No system-wide installations required
- ✅ **Consistent Environment**: Same containers work across machines
- ✅ **Better Security**: Tools isolated from host system
- ✅ **Easy Updates**: Update by changing container versions
- ✅ **Persistent Caching**: Volume mounts preserve plugins and collections
- ✅ **Network Isolation**: Containers communicate via dedicated network
- ✅ **Resource Management**: Container resource limits available
- ✅ **Parallel Execution**: Multiple container instances can run simultaneously

## Support

For issues and questions:

1. Check container logs: `docker-compose logs`
2. Verify network connectivity: `docker network inspect`
3. Test tool access: `./scripts/run-terraform.sh version`
4. Review documentation in `docs/` directory

## ops-portal-* first-time env bringup runbook

Bringing up a new env (typically prod, the first time) for the 8 ops-portal-*
services has hard ordering and a few non-obvious gotchas. The first prod
push (2026-04-19) hit each of them. Future bringups should follow this
order — every step here corresponds to a workflow already in this repo.

**Prereqs (assumed already in place):** prod k3s worker reachable on the
private network, prod monitoring-lxc + Authentik LXC running, prod Traefik
network-vm running, GitHub PAT seeded into the prod runner LXC.

### 1. Register self-hosted runners for each service repo

The prod runner LXC starts with runners for streambox / infra-platform /
otel-monitoring etc. but **not** for any ops-portal-* repo. Without this
step every Deploy workflow sits queued forever.

```
for repo in ops-portal-incidents ops-portal-shell ops-portal-infrastructure \
            ops-portal-identity ops-portal-domain ops-portal-deployments \
            ops-portal-audit ops-portal-cmdb; do
  gh workflow run "Register GitHub Actions Runner" \
    --repo TomasBFerreira/infra-platform \
    -f repo=TomasBFerreira/$repo -f env=prod
done
```

These serialise on the single infra-platform runner. **Watch the runner
LXC's disk** — 8 fresh runners + an otel-monitoring deploy can fill a
20G LXC. If you see "No space left on device" in `journalctl -u
actions.runner.*`, `pct resize 101 rootfs +20G` and `systemctl restart
actions.runner.TomasBFerreira-infra-platform.github-runner-prod`.

### 2. Seed Vault with per-service secrets

```
gh workflow run "Seed Vault for ops-portal env" \
  --repo TomasBFerreira/infra-platform \
  -f environment=prod -f worker_node_ip=<prod-worker-ip>
```

Idempotent — won't rotate keys unless `force_rotate=true`. Writes:
`worker-node/<env>/active-slot`, `ops-portal/<env>/nats`,
`ops-portal/<env>/svc-jwt/{<svc>,trusted}`, `ops-portal/<env>/incidents`
(+ webhook + internal-health tokens), and per-service `postgres_password`
for cmdb/audit/identity/deployments/domain.

Then seed the Authentik bootstrap token (separate path because it
requires SSH-ing into the SSO LXC):

```
gh workflow run "Seed devops-portal/<env>/authentik Vault path" \
  --repo TomasBFerreira/infra-platform -f environment=prod
```

This workflow is safe to re-run and now acts as a **reconcile/upsert**:
it rewrites `secret/devops-portal/<env>/authentik` from the current
`secret/sso/<env>/active-slot`. The SSO pipeline also runs it
automatically after `flip-active`, so the Authentik admin URL/token track
blue/green slot changes instead of drifting to an old slot IP.

### 3. Configure Authentik forward-auth provider for the env

```
gh workflow run "Configure Prod Forward Auth (Authentik domain-level SSO)" \
  --repo TomasBFerreira/infra-platform
```

Creates a `forward_domain` Proxy Provider, Application, and binds it to
the embedded outpost. Without it the Traefik `authentik-prod` middleware
returns 404 for unknown hosts.

### 4. Add Traefik routes + DNS

In `traefik-gitops`, add 8 prod routers + services under host
`ops.databaes.net` (path-routed: `/api/cmdb`, `/api/audit`, `/api/incidents`,
…, `/` for the shell). Match the dev pattern.

```
# in traefik-gitops
git push  # auto-fires Deploy Traefik Config + Sync Cloudflare DNS
gh workflow run "Deploy Traefik Config" \
  --repo TomasBFerreira/traefik-gitops -f deploy_prod=true
```

**Push only deploys to dev by default.** You must explicitly
`workflow_dispatch` with `deploy_prod=true` for the prod network-vm.

The Cloudflare CNAME for `ops.databaes.net` is created automatically by
`sync-dns.yml` on the same push. Note the sync-dns iterates per-router,
so you'll see the first call OK and subsequent ones fail with "record
already exists" — that's expected and the CNAME is in place.

### 5. Deploy services in dependency order

Wave A — must go first (bootstraps NATS in the cluster):
```
gh workflow run "Deploy ops-portal-cmdb" --repo .../ops-portal-cmdb -f env=prod
```

Wave B — parallel, no inter-deps beyond cmdb:
```
infrastructure, audit, identity, domain, deployments, shell
```

`identity` is normally the source of the `nfs-ops-portal` StorageClass via
its cluster-bootstrap step — **but its bootstrap is dev-only.** Prod has
no NFS export. Three places reference `nfs-ops-portal` and need overlay
patches in prod:

- `ops-portal-incidents` runbooks PVC → `local-path`
- `ops-portal-deployments` data PVC → `local-path`
- `ops-portal-domain` postgres-nfs-patch → drop entirely (postgres falls
  back to base emptyDir)

Wave C — `incidents` last because it depends on cmdb + infrastructure +
audit being live.

### 6. Common deploy failures + fixes

| Failure | Cause | Fix |
|---|---|---|
| `manifests/overlays/prod: No such file or directory` | Service has no prod overlay | Clone qa overlay, retarget hostname → `ops.databaes.net`, middleware → `authentik-prod` |
| `pod has unbound immediate PersistentVolumeClaims` (PVC `nfs-ops-portal`) | Prod has no NFS provisioner | Add overlay patch replacing `storageClassName: nfs-ops-portal` with `local-path` |
| `PersistentVolumeClaim ... is invalid: spec: Forbidden` after fix | Pre-existing PVC from earlier failed attempt is immutable | `gh workflow run "Wipe PVC" -f environment=prod -f namespace=<ns> -f pvc_name=<pvc>` |
| `StatefulSet "postgres" is invalid: spec: Forbidden` | Same, but for postgres volumeClaimTemplates | Re-run the service deploy with `-f wipe_postgres=true` |
| `404 Client Error: secret/data/devops-portal/<env>/authentik` | Identity/shell deploy needs Authentik bootstrap token in Vault | Run "Seed devops-portal/<env>/authentik Vault path" |
| Deploy queued forever, no movement | Self-hosted runner not registered for that repo | Run "Register GitHub Actions Runner" for it |
| Auth redirect loops or 404 from `auth.databaes.net` from a browser | Forward-auth Proxy Provider not yet bound to outpost | "Configure Prod Forward Auth" workflow |

### 7. Verification

Internal `/healthz` from the env's monitoring LXC:
```
for s in incidents:30096 cmdb:30092 audit:30093 identity:30091 \
         infrastructure:30094 domain:30098 deployments:30097 shell:30180; do
  printf "%-16s %s\n" "${s%:*}" "$(curl -sk --max-time 5 -o /dev/null \
    -w %{http_code} http://<worker-ip>:${s#*:}/healthz)"
done
```

External through Traefik (use a tunnel or run from inside the env):
```
curl -sk -H "Host: ops.databaes.net" https://<network-vm-ip>/  # → 302 to auth
```

