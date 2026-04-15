# Security hardening — open items

Running list of known-weak areas to address in a dedicated hardening pass.
Not a replacement for a proper threat model — just a capture point so things
don't get forgotten. Add as you notice more; tick off and leave dated notes
as you close them.

## GitHub Actions / CI

- **GH_PAT scope is too broad.** `secret/github-runner/gh_pat` is used to
  register runners and mint registration tokens. Should be the minimum
  scopes needed for `actions/runners/registration-token` — no `repo:*` write
  beyond what registration strictly requires. Rotate on a schedule.
- **Self-hosted runners run as root.** `runner_user: root` in
  `ansible/github-runner/github-runner_setup.yml`. Any workflow anyone
  dispatches can run arbitrary code as root on the LXC. Move to a
  dedicated non-root user with only the capabilities it needs (docker
  group, specific sudoers entries).
- **Runner registration workflows are dispatchable by anyone with write
  access.** `register-runner.yml` and `github-runner_pipeline_self_hosted.yml`
  accept arbitrary `github_repo` input and will register a runner against
  it. Add an allowlist check (intersect with `registered-repos.yml`) and
  require explicit approval via a protected environment.
- **No branch protection on workflows.** Deploy workflows run on whatever
  branch is dispatched. Require `main` for anything touching prod.

## Vault

- **Bootstrap root token is used everywhere.** `VAULT_BOOTSTRAP_ROOT_TOKEN`
  and `VAULT_DEV_TOKEN` are injected into most pipelines. Switch to
  scoped AppRole or JWT auth per-workflow with least-privilege policies.
- **No audit log review.** Enable Vault audit device to a durable sink
  (not just stdout on the Vault LXC) and actually review it.
- **Vault is reachable from every runner LXC and every deployed CT.**
  Network-restrict to the CI management network + specific service CTs.

## SSH / runner LXCs

- **`github_runner_worker` SSH key is in `root` authorized_keys on every
  env runner LXC.** Any compromise of that key grants root on all three.
  Split into per-env keys with per-env Vault paths.
- **No fail2ban / login monitoring on runner LXCs.**
- **No host firewall on runner LXCs** — only inbound SSH from the
  management network should be allowed.

## Deployed services

- **Grafana admin password is in a Vault KV field accessible to any
  deploy pipeline.** Move to Vault's password rotation or at least
  restrict read access.
- **OIDC client secrets live alongside admin passwords** in the same
  Vault mount. Separate policies for OIDC vs. bootstrap secrets.
- **No TLS between otelcol and backends** inside monitoring-lxc docker
  network. Low risk today but worth fixing before any cross-host flow.

## Observability

- **Deploy pipeline has no post-deploy data-ingestion health check.**
  Tracked in `otel-monitoring/docs/problems.md` (LOW). Belongs here too
  since a silently broken pipeline also breaks audit trails.

## Process

- **No dependency scanning on the deployed apps** (Renovate, Dependabot,
  Trivy) — or if present it's not feeding anywhere actionable.
- **No review of `secret/**` read access** — write down who/what can read
  which paths and prune.
- **No recovery drill** — the `registered-repos.yml` recovery flow has
  never actually been exercised by destroying and rebuilding a runner
  LXC on purpose. Do this once before you rely on it.
