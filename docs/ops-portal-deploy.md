# ops-portal — multi-service deploy

The ops-portal is 7 Go microservices + 1 Angular shell, each in its own repo with its own `deploy.yml` (push-to-main + `workflow_dispatch`). This doc covers when order matters and how to deploy them all at once.

## TL;DR

- **Existing env, just redeploying:** any order works. Trigger `infra-platform → Deploy ops-portal (meta)` with `mode=parallel`, or fire each repo's `deploy.yml` individually.
- **Fresh env / new worker node:** order matters for two bootstrap steps below. Use `mode=ordered`.

## Service inventory

| # | Repo | NodePort | Owns |
|---|------|----------|------|
| 1 | ops-portal-identity | 30091 | Authentik CRUD wrapper |
| 2 | ops-portal-cmdb | 30092 | Configuration items, changes, cmdb_incidents |
| 3 | ops-portal-audit | 30093 | NATS `audit.events.>` aggregator |
| 4 | ops-portal-infrastructure | 30094 | k8s + Proxmox + `/svc/execute` |
| 5 | ops-portal-domain | 30098 | Traefik routes + maintenance pages |
| 6 | ops-portal-deployments | 30097 | GitHub sync + Kaniko builds |
| 7 | ops-portal-incidents | 30096 | Incidents + AI remediation worker |
| 8 | ops-portal-shell | 30180 | Angular UI (talks to all the above) |

## Bootstrap order (fresh env only)

Two services have **side-effects on cluster state** that other services assume have already run. Hit them first, in this order, before the rest:

1. **identity** — applies the cluster-bootstrap NFS provisioner + local-path busybox patch. Without this, every other service's PVC stays Pending.
2. **cmdb** — applies `cluster-bootstrap/nats/`. Audit, incidents, domain, infrastructure, deployments all assume NATS is reachable (they soft-fail when it isn't, but you'll get a degraded cluster until it's up).

After 1 + 2, the remaining six can deploy in any order — they all soft-fail on missing dependencies (audit logs without NATS, AI worker prompts without CMDB tier lookups, etc.).

The recommended order in `deploy-ops-portal.yml`'s `ordered` mode:

```
identity → cmdb → audit → infrastructure → domain → deployments → incidents → shell
```

Shell is last so its Authentik proxy provider has all the per-service hostnames to whitelist. Putting it earlier just means an extra round of forward-auth 502s until the Authentik app reconciler catches up.

## Triggering the meta workflow

GitHub Actions → `infra-platform → Deploy ops-portal (meta)` → Run workflow:

| Input | What it does |
|-------|--------------|
| `env` | `dev` or `prod` |
| `worker_node_ip` | optional override; blank = resolve from Vault per-repo |
| `mode` | `ordered` (sequential, waits for each) or `parallel` (fires all at once) |
| `services` | comma-separated subset (default: all 8). Use to redeploy just one or two — e.g. `incidents,shell`. |

The meta workflow does NOT expose `wipe_postgres`. If you need to recreate a Postgres PVC (volume-mode switch), trigger that one repo's `deploy.yml` directly with the flag set — bulk-firing it would silently destroy CMDB / audit / incidents / identity / domain DB state.

## Pre-reqs (before any deploy can succeed)

These are **not** part of the ops-portal repos and must already exist on the target env:

- k3s worker node (CT 11 in dev) reachable on the LAN, with NFS server running on benedict
- Vault unsealed at the bootstrap address; the meta workflow reads `worker-node/<env>/active-slot` from it
- Authentik running with admin token in Vault at `secret/authentik/admin-token`
- Traefik dynamic config repo (`traefik-gitops`) accepting `github-actions[bot]` pushes
- AdGuard rewrite for any new `*-dev.databaes.net` hostname (see `feedback_new_app_adguard.md` in claude-memory)

If any of these are missing, fix them via the per-component `infra-platform` workflow (`vault-ct_pipeline_self_hosted`, `worker-node_pipeline_self_hosted`, etc.) first.

## Per-repo deploy what-it-does

All 8 repos follow the same shape (intentional — change in one means change in all):

1. Build + push image to `ghcr.io/tomasbferreira/<svc>:<sha>` and `:latest`
2. Resolve worker IP from Vault (or use the input override)
3. Fetch SSH key from Vault, `scp` k3s.yaml off the worker, rewrite `127.0.0.1` → worker IP
4. Airgap push: `crane pull --format=tarball` → `scp` to worker → `k3s ctr images import`
5. Idempotent `kubectl create namespace` + `kubectl create secret … --dry-run=client | kubectl apply -f -`
6. (services with Postgres) Apply migrations Job — `pg_tables` guard, NOT golang-migrate
7. `kustomize edit set image && kubectl apply -k overlays/<env>`
8. Open NodePort in worker firewall (ufw + iptables)
9. `kubectl rollout status` — fails the job if not ready in 5 min
10. Record `worker_node_ip` to Vault at `secret/<service>/<env>/active-deployment`
11. Upsert Traefik route in `traefik-gitops` (host or path-prefix depending on the service)

So the meta workflow is just a fan-out — each repo still does the heavy lifting in its own runner and namespace.
