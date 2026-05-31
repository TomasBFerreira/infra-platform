# Wiki content batch — 2026-05-31

Paste each section into the matching wiki.js page. Headings starting with `# PAGE:` are the wiki page path + whether it's new or an update.

Order matches dependency — the restore runbook stands alone, the others reference it.

> **Parser note (2026-05-31 self-fix)**: this file uses ` ```markdown ` outer fences with plain ``` inner code blocks. CommonMark closes the outer fence at the first inner ``` — so any parser that just greps ``` will truncate. Use a parser that takes "everything between `# PAGE:` metadata and the next `---` separator" and strips the outer wrapper line-by-line. See `/tmp/parse_wiki_batch_v2.py` (now deleted) for the reference implementation — it handled this correctly on the second push.

---

# PAGE: `operations/runbooks/restore-from-pbs` — NEW

**Title:** Restore a CT or VM from a PBS snapshot

**Tags:** runbook, backup, pbs, disaster-recovery

```markdown
# Restore a CT or VM from a PBS snapshot

Use this runbook when an upgrade goes wrong, a config change broke something, a file got nuked, or a CT/VM is unrecoverable and you want to roll back to a known-good state.

Backups come from the cluster's [Proxmox Backup Server](/infrastructure/proxmox-backup-server) (CT 103 on betsy). Every CT and worker VM is backed up nightly at 02:00 with `keep-last=3 keep-daily=7 keep-weekly=4 keep-monthly=6` retention.

## Choose the right scenario first

| You want to… | Scenario | Section |
|---|---|---|
| Try restore safely without overwriting the live CT | **Restore to a different VMID first**, validate, then swap | [§ A](#a-safe-restore-to-a-throwaway-vmid) |
| Roll the existing CT back to a previous point in time | **In-place restore** (destroys current state, replaces with snapshot) | [§ B](#b-in-place-restore-of-an-existing-ct--vm) |
| Pull a single file out of a snapshot without restoring the whole CT | **File-level restore** via `proxmox-backup-client mount` | [§ C](#c-restore-a-single-file-from-a-snapshot) |
| Restore from a snapshot that was just taken (e.g. before an upgrade) | Same as A or B — PBS doesn't distinguish | — |

**Always prefer A** unless you have an urgent outage and the storage cost of a parallel CT is unacceptable. A lets you sanity-check the restore (does it boot? does the service come back?) before destroying the broken state.

## Pre-flight (every scenario)

From any cluster node:

```bash
# 1. Confirm PBS is healthy and you can see snapshots
pvesm status | grep pbs-storage           # must be 'active'
pvesm list pbs-storage | grep "ct/<VMID>" # lists all snapshots for that CT
```

The last column of `pvesm list` is the snapshot time in `YYYY-MM-DDTHH:MM:SSZ` format. Pick the one you want. Typical answer: the latest snapshot from before the breakage.

To peek at what's actually in a snapshot without restoring:

```bash
pvesm extractconfig pbs-storage:backup/ct/<VMID>/<TIMESTAMP>     # CT config
# example:
pvesm extractconfig pbs-storage:backup/ct/154/2026-05-29T01:19:10Z
```

## A. Safe restore to a throwaway VMID

This restores the snapshot to a *new* CT/VM that runs alongside the broken one, so you can compare before committing.

### A1. Pick a temporary VMID

CT VMID ranges:
- prod (betsy): 1xx — pick something free in the 110–199 range
- dev (benedict): 2xx
- qa (heaton): 3xx
- temporary scratch is fine in any range; `pvesh get /cluster/nextid` returns the next free one cluster-wide.

```bash
TMP_VMID=$(pvesh get /cluster/nextid)
echo "Using temp VMID $TMP_VMID"
```

### A2. Restore

For an **LXC CT**:

```bash
# Run on the PVE node where you want it to land (often the same as the broken one)
pct restore $TMP_VMID pbs-storage:backup/ct/<SRC_VMID>/<TIMESTAMP> \
  --storage local-lvm \
  --rootfs local-lvm:8 \
  --hostname <SRC_HOSTNAME>-rollback-test

# Don't start it on the original IP — change net0 first or start with no network
pct config $TMP_VMID | grep '^net0'
pct set $TMP_VMID -net0 name=eth0,bridge=vmbr0,ip=dhcp     # or pick a free static
pct start $TMP_VMID
```

For a **QEMU VM**:

```bash
qmrestore pbs-storage:backup/vm/<SRC_VMID>/<TIMESTAMP> $TMP_VMID \
  --storage local-lvm
# Edit the IP on the VM's cloud-init or netplan before starting if it'd collide
qm start $TMP_VMID
```

### A3. Validate

Walk through whatever was broken:

- SSH in: `ssh root@<temp-ip>` (or via console: `pct console $TMP_VMID`)
- Check the service comes up: `systemctl status <service>`
- Check the service responds: `curl localhost:<port>/healthz`
- Compare config against the broken CT to be sure the snapshot pre-dates the bad change

### A4. Commit the rollback

Once you're confident the snapshot is good, replace the broken CT with the restored one. Two paths:

**Path 1 — swap IPs:**

```bash
# Stop the broken CT, mark it down
pct stop <BROKEN_VMID>
pct set <BROKEN_VMID> -onboot 0

# Move the production IP onto the restored CT and reboot it
pct set $TMP_VMID -net0 name=eth0,bridge=<bridge>,ip=<PROD_IP>/24,gw=<PROD_GW>
pct reboot $TMP_VMID

# After 24-48h of normal operation, destroy the broken one:
pct destroy <BROKEN_VMID>
```

**Path 2 — destroy and restore in place** (skip the temp CT entirely): see § B. Use this if Path 1 feels too risky and you want a single-step replacement.

After committing the rollback:

1. Update any external references (e.g. `secret/<service>/<env>/active-slot` in bootstrap vault) if the VMID changed.
2. Record a CMDB change (see [CMDB discipline](/operations/cmdb-discipline)).
3. Verify the next nightly backup picks up the restored CT — by ID. If the VMID changed, also confirm the previous VMID's snapshots are retained on PBS for at least one retention cycle.

## B. In-place restore of an existing CT / VM

⚠️ **Destructive.** The current state of the CT is irretrievable after this unless it was itself captured in a snapshot. If you're remotely unsure, take a fresh snapshot first or use § A.

```bash
# 1. Snapshot the current state, just in case
vzdump <VMID> --storage pbs-storage --mode snapshot

# 2. Stop the CT
pct stop <VMID>

# 3. Destroy and re-create from the chosen snapshot, reusing the same VMID
pct destroy <VMID>
pct restore <VMID> pbs-storage:backup/ct/<VMID>/<TIMESTAMP> \
  --storage local-lvm \
  --hostname <HOSTNAME>

# 4. Start it
pct start <VMID>
pct exec <VMID> -- systemctl status   # eyeball
```

VM equivalent: `qm stop` → `qm destroy --purge 1` → `qmrestore` → `qm start`.

After:

- Watch services for 5–15 min to confirm normal operation.
- Record a CMDB change. Reference the snapshot timestamp in the description.

## C. Restore a single file from a snapshot

Mount the snapshot read-only via `proxmox-backup-client` and copy the file out.

```bash
# From any host with proxmox-backup-client installed (PVE nodes have it)
# Get a token first:
TOKEN_SECRET=$(ssh root@192.168.50.2 \
  "grep -A2 '^pbs: pbs-storage' /etc/pve/storage.cfg | grep password" \
  || cat /etc/pve/priv/storage.cfg | grep -A1 pbs-storage)

# Or fetch from vault:
vault kv get -field=token_secret secret/pbs/cluster-storage

# Mount the snapshot — example for CT 154, snapshot 2026-05-29T01:19:10Z
mkdir -p /mnt/pbs-restore
proxmox-backup-client mount \
  --repository 'pbs-pve@pbs!pve-cluster@192.168.50.103:backup-storage' \
  ct/154/2026-05-29T01:19:10Z \
  root.pxar \
  /mnt/pbs-restore

# Now /mnt/pbs-restore has the CT's root filesystem as it was at the snapshot
cp /mnt/pbs-restore/etc/some-config.conf ~/restored-config.conf

# Unmount when done
proxmox-backup-client unmount /mnt/pbs-restore
```

Token credentials live in bootstrap vault at `secret/pbs/cluster-storage` (fields: `username`, `token_secret`, `fingerprint`).

## Common gotchas

- **IP collisions.** Don't start a restored CT on the same IP as the broken one — the network blackholes both until you fix it. Use DHCP or a free static for the validation period.
- **Snapshot timestamp is UTC.** The nightly fires at 02:00 local on the runner schedule but PBS stamps snapshots in UTC. Match by what you see in `pvesm list`, not what you remember the local-time job ran at.
- **`local-lvm` storage class.** All examples assume the destination storage is `local-lvm`. For prod betsy that's correct. If you're restoring onto NFS or another storage class, swap accordingly — `--storage <name>` for `pct restore`, `--storage <name>` for `qmrestore`.
- **`Recreate` vs `RollingUpdate` for k8s workloads inside the CT.** This runbook restores the CT or VM; if the broken state was inside a k8s deployment running on the worker VM, you may be better off `kubectl rollout undo deploy/<x>` instead — see [Rolling back a k8s app](#) (TBD page).
- **Encrypted datastore.** If anyone ever sets `--encryption-key` on the PBS datastore, you'll need the key to restore. Currently the datastore is unencrypted — that's a deliberate trade-off documented at [Proxmox Backup Server](/infrastructure/proxmox-backup-server).

## When nothing in this runbook applies

- If PBS itself is down, you can't restore. Health-check + recovery in [Proxmox Backup Server is down / not backing up](/operations/runbooks/pbs-down) (or `infra-platform/docs/runbooks.md`).
- If the snapshot you need has been pruned, you can't restore. PBS retention is `keep-last=3 keep-daily=7 keep-weekly=4 keep-monthly=6` — if the breakage is older than that, you're out of luck. Off-site B2 sync (planned, tracked in `/app/issues/backblaze-backup.md`) extends retention but isn't yet in place.

## Related

- [Proxmox Backup Server](/infrastructure/proxmox-backup-server) — what PBS is, where it lives, how to check it.
- [CMDB discipline](/operations/cmdb-discipline) — every restore is a change; record it.
- [Branch discipline](/operations/branch-discipline) — for restores that involve code rollback, branch + PR per repo.
```

---

# PAGE: `home/home` — UPDATE (replace existing content)

**Title:** Homelab Wiki

```markdown
# Homelab Wiki

Operational knowledge base for Tomas's homelab. Code-adjacent docs (build steps, package gotchas, in-flight work) live in the repos under `/app/` — this wiki is the cross-cutting half: architecture, runbooks, references that span repos.

> **Authoring rule** when the wiki and a repo CLAUDE.md disagree:
> - Code-adjacent → trust the repo
> - Cross-cutting → trust the wiki
> If you spot a contradiction, fix the wrong side rather than letting them drift.

## Most-used pages

- [Architecture overview](/architecture/overview) — the map of everything
- [Runbooks index](/operations/runbooks/index) — operational how-tos
- [Vault paths reference](/reference/vault-paths) — where every secret lives
- [Ports and Traefik path prefixes](/reference/ports-and-prefixes) — service URLs and NodePorts
- [Glossary](/reference/glossary) — the homelab's vocabulary

## When things break

- [Restore a CT or VM from a PBS snapshot](/operations/runbooks/restore-from-pbs) — roll back after a bad upgrade
- [Proxmox Backup Server is down](/operations/runbooks/pbs-down) — health check + recovery
- [Vault is sealed after a reboot](/operations/runbooks/vault-sealed) — unseal the env vault
- [Env runner is stuck](/operations/runbooks/runner-stuck) — what to check when CI hangs
- [Env runner disk is full](/operations/runbooks/runner-disk-full) — docker prune
- [Restart cloudflared after network-vm reboot](/operations/runbooks/restart-cloudflared)

## When you're adding something

- [Add a service or subdomain](/operations/runbooks/add-service-or-subdomain) — Traefik route + Cloudflare CNAME + AdGuard rewrite
- [Protect a service with SSO](/operations/runbooks/protect-with-sso) — Authentik forwardAuth in five lines
- [New-app onboarding checklist](/infrastructure/onboarding-checklist) — the 13-point gate before a new app is "done"
- [Provision a new worker node](/operations/runbooks/provision-new-worker-node)
- [Deploy to a new environment (QA or Prod)](/operations/runbooks/deploy-new-environment)
- [Register a runner for a new repo](/operations/runbooks/register-runner-for-new-repo)

## Conventions you must follow

- [Branch discipline](/operations/branch-discipline) — every change on a branch, no direct commits to main
- [CMDB discipline](/operations/cmdb-discipline) — every change recorded; problems tracked; closed when fixed
- [Incidents and the issues/ pattern](/operations/incidents/index) — where to log work that doesn't yet fit a service repo
- [Report format and naming](/operations/reports/format) — for generated artifacts under `/app/reports/`

## Infrastructure

- [Proxmox nodes](/infrastructure/proxmox-nodes) — betsy / benedict / heaton
- [Proxmox Backup Server](/infrastructure/proxmox-backup-server) — cluster-wide backup target (CT 103 on betsy, 10 TB datastore)
- [k3s clusters](/infrastructure/k3s-clusters) — prod / dev / qa workers
- [Network topology](/architecture/network-topology) — subnets, bridges, VMID/IP scheme
- [DNS and routing](/architecture/dns-and-routing) — Cloudflare, AdGuard, the ndots / trailing-dot gotchas
- [Authentication and SSO](/architecture/auth) — Authentik forwardAuth + OIDC
- [Storage and NFS](/infrastructure/storage-and-nfs) — betsy NFS layout, monitoring NFS
- [Blue/green pipelines](/infrastructure/blue-green-pipelines) — the deploy pattern every service uses
- [Traefik GitOps repo](/infrastructure/traefik-gitops) — single source of truth for routes

## Services

### Ops Portal mesh (microservices that replaced the devops-portal monolith)
- [Index](/services/ops-portal/index) — overview + dependency map
- Per-service: [identity](/services/ops-portal/identity), [cmdb](/services/ops-portal/cmdb), [audit](/services/ops-portal/audit), [infrastructure](/services/ops-portal/infrastructure), [incidents](/services/ops-portal/incidents), [deployments](/services/ops-portal/deployments), [domain](/services/ops-portal/domain), [shell](/services/ops-portal/shell)
- Supporting: [go-lib](/services/ops-portal/go-lib), [contracts](/services/ops-portal/contracts), [devcompose](/services/ops-portal/devcompose)

### Self-hosted apps
- [Streambox (Tomaj Flix)](/services/self-hosted/streambox), [Nextcloud](/services/self-hosted/nextcloud), [media-stack](/services/self-hosted/media-stack), [otel-monitoring](/services/self-hosted/otel-monitoring), [databaes-landing-page](/services/self-hosted/landing-page), [databaes-status-api](/services/self-hosted/status-api), [Wiki.js (this wiki)](/services/self-hosted/wikijs)

## Reference

- [Vault paths reference](/reference/vault-paths)
- [Ports and Traefik path prefixes](/reference/ports-and-prefixes)
- [GitHub repo secrets](/reference/github-secrets)
- [Cluster credentials and kubectl access](/reference/cluster-credentials)
- [Glossary](/reference/glossary)

## Recently added (2026-05-28 – 2026-05-31)

- [Proxmox Backup Server](/infrastructure/proxmox-backup-server) — restored from a months-long gap; cluster-wide nightly backups live again.
- [Restore from PBS](/operations/runbooks/restore-from-pbs) — the page you just thought about while reading this.
- [Recording a CMDB change from outside the cluster](/operations/runbooks/cmdb-record-off-cluster) — for Claude sessions and automation that can't reach the Authentik-gated API.
- [WikiJS SSO bootstrap and recovery](/operations/runbooks/wikijs-sso-bootstrap) — what to do when the OIDC strategy isn't wired up.
```

---

# PAGE: `infrastructure/proxmox-backup-server` — NEW

**Title:** Proxmox Backup Server

**Tags:** infrastructure, backup, pbs

```markdown
# Proxmox Backup Server

Cluster-wide backup target. One PBS serves benedict, heaton, and betsy.

## At a glance

| | Value |
|-|-------|
| Node | betsy |
| VMID / IP | 103 / 192.168.50.103 (mgmt subnet) |
| Port | 8007 (UI + API) |
| Datastore | `backup-storage` at `/backup-storage` |
| Underlying disk | `sdb` on betsy — 9.1 TB ext4 (LVM `backup-vg/backup-storage`, 2.5 TB LV) bind-mounted from `/mnt/backup-storage` |
| Schedule | `pbs-nightly-all` — all=1, exclude 999/9000/9001/9002, 02:00 |
| Retention | keep-last=3, keep-daily=7, keep-weekly=4, keep-monthly=6 |
| GC | daily 03:30 |
| Verify | weekly Sun 05:00 (`verify-job: backup-storage-weekly`) |
| API user | `pbs-pve@pbs` + token `pve-cluster` (role: `DatastorePowerUser`) |
| Credentials | bootstrap vault `secret/pbs/cluster-storage` (server, datastore, username, token_secret, fingerprint) |
| SSH key | bootstrap vault `secret/ssh_keys/pbs_worker` |
| Pipeline | `infra-platform/.github/workflows/pbs_pipeline.yml` |

## Why this shape

**Single-slot, not blue/green.** Documented as the second exception to `infra-platform` rule #5 (the first is `github-runner`). The backup datastore is the cluster's only authoritative restore source — blue/green flips would either lose the chain on each deploy or require detaching/reattaching the host bind-mount with brief downtime, for no operational benefit.

**Lives on betsy specifically.** The 10 TB HDD is physically attached there. PBS must run on the same host to use a bind-mount (cleanest, fastest path). All three PVE nodes reach the PBS API over the mgmt subnet — no inter-VLAN traffic for the backup hot path.

**Privileged CT.** PBS writes as uid 34 (`backup`); unprivileged-LXC uid remapping makes host-side directory permissions fight ugly. Privileged is the standard pattern for storage-handling CTs in this homelab.

**Datastore survives CT rebuilds.** The bind-mount is host-level. If CT 103 has to be torn down (e.g. `gh workflow run pbs_pipeline.yml -f reset=true`), the chunks on `/mnt/backup-storage` persist and the new CT recognises the existing datastore on first start.

**Unencrypted on disk.** Deliberate trade-off: easier disaster recovery (anyone with the disk can read it) at the cost of cold-storage privacy. Acceptable for a homelab where the disk lives behind locked doors. Off-site sync to Backblaze B2 (planned) will encrypt in transit + at rest on the B2 side.

## How backups flow

```
PVE node                betsy /etc/pve/jobs.cfg              betsy /etc/pve/storage.cfg
  (CT 100..397)  ──►   pbs-nightly-all (02:00)        ──►   pbs: pbs-storage
                       all=1, exclude 999/9000/...           server 192.168.50.103
                                                             username pbs-pve@pbs!pve-cluster
                                                  │
                                                  ▼
                                       PBS HTTPS API (8007 on CT 103)
                                                  │
                                                  ▼
                                       Chunkstore /backup-storage/.chunks/
                                       (content-addressed, deduped across all snapshots)
```

PVE storage.cfg is cluster-wide (`/etc/pve` is replicated). One `pvesm add` on any node propagates to all three.

## Latest known-good state (2026-05-29)

After provisioning on 2026-05-28, the first scheduled nightly ran cleanly:

- All **34 CTs + 3 worker VMs** backed up between 01:00 and 02:20.
- **~115 GB datastore usage, 69,366 chunks** — comfortable dedup ratio.
- PBS even backs itself up (CT 103, ~1 GB — bind-mount excluded by `backup=0`).
- No errors in `proxmox-backup-manager task list`.

Sanity-check current state from any cluster node:

```bash
pvesm status | grep pbs-storage          # active / inactive
ssh root@192.168.50.103 'proxmox-backup-manager datastore list'
ssh root@192.168.50.103 'df -h /backup-storage'
ssh root@192.168.50.103 'proxmox-backup-manager task list --limit 30'
```

## Restoring from PBS

→ See the dedicated runbook: [Restore a CT or VM from a PBS snapshot](/operations/runbooks/restore-from-pbs).

## Provisioning / rebuild

The pipeline is idempotent. Re-run normally with no inputs to reconcile after image upgrade or cert expiry. Pass `reset=true` only if the CT itself is unrecoverable — the datastore on the bind-mount survives.

```bash
gh workflow run pbs_pipeline.yml --repo TomasBFerreira/infra-platform
gh workflow run pbs_pipeline.yml --repo TomasBFerreira/infra-platform -f reset=true   # CT rebuild
```

## Recovery / failure modes

Health check + per-symptom diagnosis: [Runbook: PBS is down](/operations/runbooks/pbs-down) — mirrors `infra-platform/docs/runbooks.md § Proxmox Backup Server (PBS) is down / not backing up`.

## Off-site backup (planned)

Tracked at `/app/issues/backblaze-backup.md`. Backblaze B2 mirror of this datastore for off-site DR. Expected ~$1.50–3/mo at current size. Builds on this PBS — pre-requisite is in place.

## Change history

| Date | Change | Ref |
|------|--------|-----|
| 2026-05-28 | Initial provision (replaces dead .102 entry). 6 pipeline iterations to converge — fix-forward PRs for vault token name, generate-token CLI, verify-schedule → verify-job in PBS 4.x, and DatastorePowerUser. | infra-platform PRs #256–260, CMDB change #430 |
| 2026-05-29 | First scheduled nightly: 37 backup objects, ~115 GB. | — |
```

---

# PAGE: `operations/runbooks/cmdb-record-off-cluster` — NEW

**Title:** Recording a CMDB change from outside the cluster

**Tags:** runbook, cmdb, automation, claude

```markdown
# Recording a CMDB change from outside the cluster

## When to use this

The public CMDB at `ops-dev.databaes.net/api/cmdb/*` is behind Authentik forwardAuth. Off-cluster automation — Claude sessions, ad-hoc shell scripts, cron jobs running outside the k3s cluster — has no usable session cookie.

For these cases, dispatch `cmdb-record.yml` via `gh workflow run`. The workflow runs on the management runner (CT 200 on benedict), SSH-hops to benedict's host (direct vmbr20 route), and POSTs to the dev `ops-portal-cmdb` NodePort at `http://192.168.20.11:30092`. Bypasses Traefik — the runner identity is the trust boundary, same pattern as `github-runner`.

> If you're inside an `ops-portal-*` service, publish `cmdb.change.requested` on NATS instead — this workflow is the fallback path.

## Record a change

```bash
gh workflow run cmdb-record.yml --repo TomasBFerreira/infra-platform \
  -f kind=change \
  -f title="One-line summary" \
  -f description="Multi-line OK. What changed, why, when." \
  -f affected_cis="ci_name_1,ci_name_2" \
  -f change_type=normal \
  -f risk=low \
  -f status=completed \
  -f implementation_plan="What was done" \
  -f rollback_plan="How to revert"
```

| Input | Required? | Default |
|-------|-----------|---------|
| `title` | yes | — |
| `description` | recommended | empty |
| `affected_cis` | recommended | empty (comma-separated CI names) |
| `change_type` | yes (enum) | `auto` — others: `standard`, `normal`, `emergency` |
| `risk` | yes (enum) | `low` — others: `medium`, `high` |
| `status` | yes (enum) | `completed` — others: `draft`, `approved`, `in_progress`, `rolled_back`, `cancelled` |
| `implementation_plan` | optional | empty |
| `rollback_plan` | optional | empty |
| `requested_by` | optional | workflow run id |

## Open a problem (something you can't fix immediately)

```bash
gh workflow run cmdb-record.yml --repo TomasBFerreira/infra-platform \
  -f kind=problem-open \
  -f title="Concise problem statement" \
  -f description="Symptoms, when observed, what's blocking the fix" \
  -f affected_cis="ci_name_1" \
  -f severity=warning
```

Severity: `critical` | `warning` | `info`.

## Close a problem

```bash
gh workflow run cmdb-record.yml --repo TomasBFerreira/infra-platform \
  -f kind=problem-close \
  -f problem_id=42 \
  -f title="-" \
  -f resolution="Bumped CPU + added systemd-tmpfiles cleanup. Validated under load."
```

`title` is required by the inputs schema but ignored by the close endpoint — any non-empty placeholder is fine.

## Audit trail

Every record's description gets a trailing `Recorded by: <gha-run-url>` so future audits can follow the GHA logs.

## When the workflow fails

| Symptom | Likely cause |
|---------|--------------|
| `healthz unreachable via benedict` | benedict can't reach `192.168.20.11:30092`. Check the dev k3s worker (VMID 211) is up and the `ops-portal-cmdb` pod is running. |
| `HTTP 400 / 422 from CMDB` | Payload schema mismatch. Check the CMDB struct in `ops-portal-cmdb/internal/store/store.go` — field names + enum values. |

## Related

- [CMDB discipline](/operations/cmdb-discipline) — the workspace rule this workflow exists to support.
```

---

# PAGE: `operations/runbooks/wikijs-sso-bootstrap` — NEW

**Title:** WikiJS SSO bootstrap and recovery

**Tags:** runbook, wikijs, authentik, sso

```markdown
# WikiJS SSO bootstrap and recovery

## The trap

When wikijs is deployed without anyone walking through the install wizard, the first OIDC login can land in either of two bad states:

1. **No OIDC user is ever created.** Authentik authenticates fine and the Proxy Outpost passes the request through to wikijs with `X-Authentik-*` headers, but without an OIDC strategy configured wikijs ignores those headers and treats every request as anonymous. `/administration` returns 401.
2. **OIDC user IS created but in the wrong group.** The Strategy's "Assign to group" default is `Guests`, so first-login users have no admin permissions and `/administration` still 401s.

Both are recoverable from outside the wiki via two one-shot workflows in `infra-platform`.

## State 1 — No OIDC strategy configured

You'll see this if the wikijs DB has zero users with `providerKey != local`. Verify:

```bash
gh workflow run wikijs-debug.yml --repo TomasBFerreira/infra-platform -f log_lines=50
gh run watch
# look at the "users" output — if only admin@databaes.net and guest@example.com, you're in state 1
```

### Fix

Step 1 — reset the local admin password, log in via the **Local** strategy:

```bash
gh workflow run wikijs-reset-local-admin.yml --repo TomasBFerreira/infra-platform
gh run watch
# the workflow prints a temporary password into the log
```

Read the temp password from the log, log into `wikijs.databaes.net/login` with the **Local** strategy (NOT Authentik), email `admin@databaes.net`.

Step 2 — change the password (Profile → Change password).

Step 3 — configure the OIDC strategy (Administration → Authentication → Add Strategy → Generic OpenID Connect):

| Field | Value |
|---|---|
| Display Name | `Authentik` |
| Client ID | from the OAuth2/OpenID Provider in Authentik |
| Client Secret | from the OAuth2/OpenID Provider in Authentik |
| Authorization URL | `https://auth.databaes.net/application/o/authorize/` |
| Token URL | `https://auth.databaes.net/application/o/token/` |
| User Info URL | `https://auth.databaes.net/application/o/userinfo/` |
| Issuer | `https://auth.databaes.net/application/o/<slug>/` (use the actual application slug) |
| Logout URL | `https://auth.databaes.net/application/o/<slug>/end-session/` |
| Allow Self-Registration | ON |
| Assign to Group | `Administrators` (only while you're the sole user; switch to `Guests` and use group-claim mapping once others join) |

Step 4 — in the Authentik provider, ensure the **Redirect URI** matches `https://wikijs.databaes.net/login/<wikijs-strategy-UUID>/callback`. wikijs assigns the UUID at save time — copy it from the saved strategy header.

Step 5 — see [Common gotchas](#common-gotchas) before you test, especially the Encryption Key one.

### Verify

```bash
curl -s https://auth.databaes.net/application/o/<slug>/.well-known/openid-configuration \
  | python3 -m json.tool | grep -i encryption
# Expected: no output. If id_token_encryption_alg_values_supported is listed, fix per § Common gotchas.
```

Log out of wikijs, click **Authentik** on the login page, you should round-trip cleanly.

## State 2 — OIDC user exists but is a Guest

`gh workflow run wikijs-debug.yml` will show your email in the users table with a non-`local` providerKey, but the group-membership query shows you in `Guests` only.

### Fix

```bash
gh workflow run wikijs-grant-admin.yml --repo TomasBFerreira/infra-platform \
  -f email=your-email@databaes.net
```

Idempotent INSERT into `userGroups` mapping you to the `Administrators` group (id=1). Log out and back in for the change to take effect.

## Common gotchas

### "Unexpected token '*'... is not valid JSON" on OIDC callback

Authentik is **encrypting** the id_token (JWE), not just signing (JWS). wikijs's openid-connect strategy can't decrypt JWE and tries to JSON-parse the ciphertext, getting binary garbage.

**Fix:** in Authentik → Applications → Providers → your OAuth2/OpenID Provider → Edit → Advanced protocol settings → **Encryption Key** → set to `---------` (empty). Save.

Verify the discovery doc no longer advertises encryption:
```bash
curl -s https://auth.databaes.net/application/o/<slug>/.well-known/openid-configuration \
  | python3 -m json.tool | grep -i encryption
# Expected: no output.
```

### "Sub drift" after Authentik blue/green flip

Authentik's user `pk` is the OIDC `sub` claim. Across an Authentik prod flip that wipes its DB, pks reassign and the wikijs row keyed by old pk no longer matches the new claim. Symptom: login succeeds at Authentik, wikijs creates a NEW shadow user with no permissions.

**Fix:** UPDATE wikijs `users.providerKey` (or the relevant join row) to the new sub. Similar pattern to the [Grafana RCA](/operations/incidents/index) on 2026-04-23.

### Local strategy still enabled

Don't disable the Local strategy — it's your break-glass account if Authentik ever goes down. Keep its password in `secret/wikijs/prod/local-admin` (TODO — currently still rotated only via `wikijs-reset-local-admin.yml`).

## Related workflows

- `wikijs-debug.yml` — read-only diagnostic (pod log + auth strategies + OIDC config dump)
- `wikijs-reset-local-admin.yml` — random-password reset of `admin@databaes.net`
- `wikijs-grant-admin.yml` — add specified email to the `Administrators` group
```

---

# PAGE: `operations/runbooks/index` — UPDATE

Add the three new runbook links into the existing list. The runbook is structured as a flat list of links; just add:

```markdown
- [Restore a CT or VM from a PBS snapshot](/operations/runbooks/restore-from-pbs) — roll back a host after a bad upgrade
- [PBS is down / not backing up](/operations/runbooks/pbs-down) — health check + recovery for the backup target
- [Recording a CMDB change from outside the cluster](/operations/runbooks/cmdb-record-off-cluster) — the gh workflow run path for sessions/automation
- [WikiJS SSO bootstrap and recovery](/operations/runbooks/wikijs-sso-bootstrap) — local-admin reset + OIDC strategy config
```

---

# PAGE: `architecture/overview` — UPDATE

Add a paragraph (or list item) under whatever "What runs where" / "Topology" section you have:

```markdown
**Backup**: cluster-wide [Proxmox Backup Server](/infrastructure/proxmox-backup-server) (CT 103 on betsy), 10 TB local datastore on betsy's `sdb`, nightly backups of every CT and worker VM. Off-site Backblaze B2 sync planned. To restore a host after a bad upgrade, see [Restore from PBS](/operations/runbooks/restore-from-pbs).
```

---

# PAGE: `reference/vault-paths` — UPDATE

Add to the SSH keys section:

```markdown
| `secret/ssh_keys/pbs_worker` | `private_key`, `public_key` | Manual setup (2026-05-28, consumed by `pbs_pipeline.yml`) |
```

Add to the application secrets section:

```markdown
| `secret/pbs/cluster-storage` | `server, datastore, username, token_secret, fingerprint` | pbs pipeline — used by `pvesm add pbs` on every cluster node |
| `secret/wikijs/prod/local-admin` | `password` *(planned)* | TODO — currently rotated only via the `wikijs-reset-local-admin.yml` workflow |
```

---

# PAGE: `reference/ports-and-prefixes` — UPDATE

If the page has an infrastructure section (Proxmox / vault / etc.), add:

```markdown
| Service | Subnet | IP | Port | Notes |
|---|---|---|---|---|
| Proxmox Backup Server | mgmt | 192.168.50.103 | 8007 | Web UI + API, behind Tailscale only — no Cloudflare route |
```

---

## What I'm not generating

- No retrospective / post-mortem page for the OIDC fix — it's a one-line cause (Encryption Key set), the runbook entry captures the recovery, and CMDB change has the timeline. Adding a post-mortem on top of that is noise.
- Per-CT restore examples — the restore runbook (§ A2 / § B) shows the templates; a session that needs them substitutes the VMID/timestamp.

## After pasting

Once the pages are in, run:

```bash
gh workflow run cmdb-record.yml --repo TomasBFerreira/infra-platform --ref main \
  -f kind=change \
  -f title="Wiki updates: PBS service, restore-from-PBS runbook, cmdb-record runbook, wikijs-sso-bootstrap runbook, homepage refresh" \
  -f affected_cis=wikijs,wikijs-prod \
  -f change_type=auto -f risk=low -f status=completed
```

or let me do it — paste back which page paths you actually landed (you may rename slugs, that's fine) and I'll log the change.
