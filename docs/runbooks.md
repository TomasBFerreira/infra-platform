# Runbooks

## How to log into Vault

**Via UI (OIDC):**
1. Go to `http://192.168.20.45:8200` (dev) or `https://vault.databaes.net` (prod)
2. Select **OIDC** from the method dropdown
3. Click **Sign in with OIDC Provider**
4. Log in with your Authentik account (`akadmin` or your user)
5. You're in with the `admin` policy (full access)

**Via CLI (OIDC):**
```bash
export VAULT_ADDR=http://192.168.20.45:8200
vault login -method=oidc
# Opens browser for Authentik login
```

**Via CLI (token — for scripts):**
```bash
export VAULT_ADDR=http://192.168.20.45:8200
export VAULT_TOKEN=<ci-token-from-github-secrets>
vault kv get secret/some/path
```

---

## How to add a new external service/domain

1. Open `traefik-gitops/config/dynamic/services.yml`
2. Add a router and service:
```yaml
http:
  routers:
    myapp-router:
      rule: "Host(`myapp.databaes.net`)"
      service: myapp-service
      entryPoints:
        - web

  services:
    myapp-service:
      loadBalancer:
        servers:
          - url: "http://192.168.50.XXX:PORT"
```
3. Commit and push to `main`
4. `deploy.yml` deploys config to active dev network-vm (Traefik hot-reloads)
5. `sync-dns.yml` creates `myapp.databaes.net CNAME → prod tunnel` in Cloudflare
6. Service is live at `https://myapp.databaes.net`

> **Dev services:** name them `myapp-dev.databaes.net` and they'll automatically get the dev tunnel CNAME instead.

> **Prod deploy:** re-run `Deploy Traefik Config` with `deploy_prod: true` when ready.

---

## How to protect a service with SSO

1. Add `middlewares: [authentik-dev]` to the router in `services.yml`
2. In Authentik Admin UI: Create a **Proxy Provider** for the service
3. Create an **Application** linked to that provider
4. Configure the **Embedded Outpost** to include the new application

---

## Cloudflare tunnel dies after network-vm reboot

**Symptom:** External services unreachable, `systemctl status cloudflared` shows failed/inactive.

**Fix:**
```bash
ssh root@192.168.20.55  # or .56 — whichever is active (dev); prod: 192.168.10.55/.56
systemctl restart cloudflared
journalctl -u cloudflared -f  # watch for "Connected to Cloudflare"
```

**Root cause / prevention:** `cloudflared` uses `Type=notify` — systemd kills it if it doesn't send `READY` within `TimeoutStartSec`. On boot, DNS resolution for `*.argotunnel.com` can take >15s. We set `TimeoutStartSec=90` in the Ansible role. If the issue recurs, increase this value in `ansible/network-vm/roles/cloudflare-tunnel/tasks/main.yml`.

**Check ingress rules:** If cloudflared is connected but services still return 503, check that the tunnel has ingress rules configured in Cloudflare Zero Trust → Tunnels → select tunnel → Configure → Public Hostname. A wildcard rule `*.databaes.net → http://localhost:80` should exist.

---

## GitHub Actions runner is stuck

There are two runner tiers. Identify which one is stuck.

### Env runner (CT 201 for dev, CT 101 for prod)

```bash
# SSH into the runner CT (CT 201 for dev)
ssh root@192.168.20.101  # dev

# Check service status
SERVICE=$(systemctl list-units --type=service | grep 'actions.runner' | awk '{print $1}' | head -1)
systemctl status "$SERVICE"
```

If `Runner.Listener` is running but jobs aren't being picked up, it may have lost connection to GitHub. Sending `SIGTERM` forces a reconnect (the service wrapper restarts it automatically):
```bash
pgrep -a Runner.Listener  # find PID
kill -SIGTERM <pid>
# RunnerService.js restarts it within a few seconds
```

**Restart the runner service:**
```bash
# From inside the runner CT:
cd /opt/github-runners/tomasbferreira-infra-platform
./svc.sh stop
./svc.sh start
```

### Management runner (CT 200 — bootstrap vault)

```bash
ssh root@192.168.50.200  # or via Proxmox: pct exec 200 -- bash

systemctl status actions.runner.TomasBFerreira-infra-platform.github-runner-management
# Restart if needed:
cd /opt/github-runners/tomasbferreira-infra-platform
./svc.sh stop && ./svc.sh start
```

### Env runner lost its CT entirely

If the runner CT was destroyed and the env runner is missing:

```bash
# Re-run the github-runner pipeline — it runs on the management runner (CT 200)
# which is never affected by env teardowns
gh workflow run github-runner_pipeline_self_hosted.yml \
  --repo TomasBFerreira/infra-platform \
  --field environment=dev
```

---

## Vault is sealed after a reboot

The `vault-unseal` systemd service should handle this automatically. If it fails:

```bash
ssh root@192.168.20.45  # active vault IP (dev); prod: 192.168.10.45
systemctl status vault-unseal
# If failed, run manually:
export VAULT_ADDR=http://127.0.0.1:8200
while IFS= read -r key; do
    vault operator unseal "$key"
done < /etc/vault.d/.unseal_keys
```

---

## Need the Authentik admin password

```bash
# From the bootstrap vault (CT 200)
# Password was copied there by the fetch-sso-password workflow
vault kv get secret/sso/dev/bootstrap_password
# OR run the workflow again:
# infra-platform → Actions → "Fetch SSO bootstrap password" → Run workflow
```

**Note:** If the SSO pipeline has re-run since you last fetched the password, the password in Authentik's DB may not match what's in vault (Authentik only sets the password on first DB initialization). In that case, reset via:
```bash
ssh root@192.168.20.75  # active SSO IP (dev); prod: 192.168.10.75
docker exec authentik-server ak set_password --username akadmin
```

---

## vault-ct redeploy — full recovery sequence

If you need to fully redeploy the dev vault (e.g. after CT corruption):

1. **Run vault-ct pipeline** (dev) — provisions new vault, seeds secrets, configures OIDC automatically via `configure-oidc` job
2. **Re-run SSO pipeline** (dev) — regenerates `secret/sso` secrets (db password, bootstrap token), recreates Authentik Vault OAuth2 provider
3. **Re-run backfill-bootstrap-vault** — copies new OIDC creds to bootstrap vault for future vault-ct deploys
4. **Re-run configure-vault-oidc** — updates Vault OIDC config + Authentik redirect_uris with new credentials

> Steps 1 and 3-4 are automatic if run in order. Step 2 (SSO pipeline) is only needed if Authentik's OAuth2 provider credentials are lost.

---

## Provisioning a new worker node

Worker nodes are real VMs (not LXC containers) provisioned via the **Worker Node Pipeline**.

### Prerequisites (one-time per Proxmox node)

**1. Create the cloud-init template VM on the target node**

SSH into the Proxmox node (e.g. `ssh root@192.168.50.4` for benedict) and run:

```bash
# Download Debian 12 generic cloud image
wget -O /tmp/debian-12-genericcloud-amd64.qcow2 \
  https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

# Create template VM (VMID 9000 reserved for this)
qm create 9000 --name debian-12-cloud --memory 2048 --cores 2 \
 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci

# Import disk
qm importdisk 9000 /tmp/debian-12-genericcloud-amd64.qcow2 local-lvm

# Attach disk and cloud-init drive
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1

# Convert to template
qm template 9000

# Clean up
rm /tmp/debian-12-genericcloud-amd64.qcow2
```

**2. Add SSH keypair to bootstrap vault**

```bash
ssh-keygen -t ed25519 -C "worker-node" -f /tmp/worker_node_key -N ""

# Point at the bootstrap vault (get VAULT_DEV_TOKEN from GitHub secrets)
export VAULT_ADDR=http://192.168.50.200:8200
export VAULT_TOKEN=<VAULT_DEV_TOKEN>

vault kv put secret/ssh_keys/worker_node_worker \
  private_key="$(cat /tmp/worker_node_key)" \
  public_key="$(cat /tmp/worker_node_key.pub)"
rm /tmp/worker_node_key /tmp/worker_node_key.pub
```

### Running the pipeline

Go to **infra-platform → Actions → Worker Node Pipeline → Run workflow**:
- `node_number`: next available number (2 for worker-node-02, 3 for worker-node-03, etc.)
- `target_node`: Proxmox node to deploy on (`benedict` for dev, `betsy` for prod)
- `template_vmid`: VMID of the cloud-init template VM on the target node (default: `9000`)

VMID and IP are computed automatically: VMID = `env_base + node_number` (110 for prod, 210 for dev, 310 for qa), IP = `192.168.<env_subnet>.(VMID last 2 digits)`.

### Decommissioning a worker node

To tear down a worker node cleanly:

```bash
# 1. Drain the node in k3s (if it's part of a cluster)
k3s kubectl drain worker-node-02 --ignore-daemonsets --delete-emptydir-data
k3s kubectl delete node worker-node-02

# 2. Destroy the VM from Proxmox
ssh root@192.168.50.4  # target Proxmox node
qm stop 112 && qm destroy 112 --purge

# 3. Remove state file from runner
rm /app/infra-platform/terraform/worker-node/terraform.node-112.tfstate

# 4. Remove node record from bootstrap vault
vault kv delete secret/worker-node/2/state
```

---

## Proxmox LXC template is missing

**Symptom:** Terraform fails with `template not found` on a Proxmox node.

The LXC template must exist on each node's local storage before deploying:
```
local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst
```

Download from the Proxmox UI: Datacenter → node → local → CT Templates → Templates → search "debian-12".

---

## Registering a GitHub Actions runner for a new repo

Each repo that needs CI/CD runs its jobs on the shared env runner LXC. Use the `register-runner.yml` workflow to register a new repo — this is a one-time step per repo per environment.

### Prerequisites

1. The env runner LXC must already exist (provisioned by the `github-runner` pipeline).
2. `secret/ssh_keys/github_runner_worker` must be in bootstrap vault (runner LXC SSH key).
3. `secret/github-runner/<env>/state` must be in bootstrap vault with field `ip` (runner LXC IP — written by the github-runner pipeline on provision).
4. The infra-platform runner for the env must be running (so the workflow job can execute).

### Trigger the workflow

```bash
gh workflow run register-runner.yml \
  --repo TomasBFerreira/infra-platform \
  --field repo=<owner/repo> \
  --field env=<dev|qa|prod>
```

Or via GitHub UI: **infra-platform → Actions → Register GitHub Actions Runner → Run workflow**

### What it does

- SSHes into the runner LXC for the target env
- Runs `ansible/github-runner/github-runner_setup.yml` with `github_repo=<repo>` and `runner_env=<env>`
- Creates an isolated runner directory at `/opt/github-runners/<repo-slug>/`
- Registers the runner with GitHub using a fresh JIT token
- Installs and starts a per-repo systemd service (`github-runner-<repo-slug>.service`)

### Verify the runner is online

After the workflow completes, check the runner appears in the target repo:

```
https://github.com/<owner>/<repo>/settings/actions/runners
```

The runner label will include the env name (e.g. `dev`). Jobs using `runs-on: [self-hosted, dev]` will be picked up by this runner.

### Re-registering or replacing a runner

Re-run the same workflow. The Ansible playbook is idempotent — it de-registers any existing runner for the repo and registers a fresh one.

---

## Deploying to a new environment (QA or Prod)

1. Ensure the LXC template is on the target Proxmox node
2. Add shared secrets to bootstrap vault (`secret/tailscale`, `secret/adguard`, `secret/wireguard`, etc.)
3. Run **vault-ct pipeline** for the environment → creates vault, sets `VAULT_QA_ADDR/TOKEN` or `VAULT_PROD_ADDR/TOKEN` GitHub secrets
4. Run **network-vm pipeline** for the environment → sets up Traefik + cloudflared
5. Run **SSO pipeline** for the environment → deploys Authentik, stores OIDC creds
6. Run **configure-vault-oidc** for the environment → wires up OIDC login