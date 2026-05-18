# Renovate — dependency upgrade automation

Renovate runs on a schedule against the repos listed in `renovate/config.js`
and opens PRs when there's a newer version of any tracked dependency
(container image, GitHub Action, etc.). Each PR triggers a CMDB-notify
workflow in the target repo, which records the proposal as a `cmdb_changes`
entry and surfaces it in Slack via the GitHub Slack app.

## Architecture

```
infra-platform                                        nextcloud (example)
┌──────────────────────────────────┐                 ┌──────────────────────────────────┐
│ .github/workflows/renovate.yml   │                 │ renovate.json                    │
│   schedule: 08:17 + 20:17 UTC    │                 │   (per-repo Renovate config)     │
│   runs on arc-pilot-dev (ARC)    │   GH API        │                                  │
│   1. read GH-App creds from vault│ ─── opens ───→  │ ┌──────────────────────────────┐ │
│   2. mint installation token     │   PRs here      │ │ Renovate PR                  │ │
│   3. exec `renovate`             │                 │ │ author: renovate[bot]        │ │
└──────────────────────────────────┘                 │ │ label:  renovate             │ │
                                                     │ └──────────────┬───────────────┘ │
┌──────────────────────────────────┐                 │                │ on PR events    │
│ .github/workflows/                │  workflow_call │ ┌──────────────▼───────────────┐ │
│   cmdb-notify-renovate.yml       │ ←──────────────│  .github/workflows/             │ │
│   (reusable, runs on [s-h,prod]) │                 │  renovate-cmdb-notify.yml      │ │
│   POST /api/cmdb/changes          │                 │                                  │
│   → 192.168.10.21:30092           │                 └──────────────────────────────────┘
└──────────────────────────────────┘
                                       Slack: GitHub app subscription on
                                       repo "pulls +label:renovate" →
                                       #upgrades channel
```

## One-time setup

### 1. Create the Renovate GitHub App

Separate from the ARC app — Renovate needs PR-write perms that ARC doesn't.

In github.com → Settings → Developer settings → GitHub Apps → New GitHub App:

- **Name**: `Renovate (databaes)` (must be globally unique on github.com)
- **Homepage URL**: `https://github.com/TomasBFerreira/infra-platform`
- **Webhook**: disabled (we don't use webhooks; Renovate polls)
- **Permissions** (repository):
  - Contents: **Read & write**
  - Issues: Read & write   (for the dependency dashboard issue)
  - Pull requests: **Read & write**
  - Workflows: Read & write   (so Renovate can update `.github/workflows/*` GHA versions)
  - Metadata: Read
- **Where can this GitHub App be installed**: Only on this account
- Generate a private key (`.pem`) — download and keep safe

After creation, note the **App ID** and **Installation ID** (the latter is
visible in the install URL once you install it).

### 2. Install the app on the pilot repo

Install URL → choose **TomasBFerreira/nextcloud** only for the pilot.
Add more repos later as we widen scope.

### 3. Seed credentials into the dev env vault

The orchestrator runs in the dev k3s cluster (ARC pilot), so the credentials
live in the **dev env vault** (not bootstrap):

```bash
vault kv put secret/renovate/github-app \
  app_id=<numeric app id> \
  installation_id=<numeric installation id> \
  private_key=@/path/to/renovate.private-key.pem
```

### 4. Wire Slack notifications

In the `#upgrades` Slack channel (create it if missing):

```
/github subscribe TomasBFerreira/nextcloud pulls +label:renovate
```

Repeat per-repo as we onboard new ones. The `+label:renovate` filter limits
the firehose to Renovate's PRs (every Renovate PR is auto-labelled per
`renovate/config.js`).

## Operations

### Test run without opening PRs

```
gh workflow run renovate.yml --repo TomasBFerreira/infra-platform \
  -f dry_run=full -f log_level=debug
```

Watch the logs — Renovate will list every update it WOULD propose without
actually opening any PRs.

### Onboarding a new repo

1. Add the repo to `repositories` in `renovate/config.js`.
2. Add a `renovate.json` at the root of that repo (see
   `TomasBFerreira/nextcloud` for the reference shape).
3. Add a `.github/workflows/renovate-cmdb-notify.yml` in that repo that
   `uses:` the reusable workflow at
   `TomasBFerreira/infra-platform/.github/workflows/cmdb-notify-renovate.yml@main`.
4. Install the Renovate GitHub App on the new repo via the app's install URL.
5. `/github subscribe <owner>/<repo> pulls +label:renovate` in `#upgrades`.

### Common gotchas

- **The `cmdb-notify-renovate.yml` reusable workflow pins `runs-on:
  [self-hosted, prod]`** because the prod CMDB NodePort is only reachable from
  the prod subnet (192.168.10.0/24). Don't change to ARC until ARC is
  extended to a prod scale set with the same network reachability.
- **CMDBChange.Status** valid values are `draft | approved | in_progress |
  completed | rolled_back | cancelled`. The notify workflow uses `draft` for
  PR-opened (proposal) and `completed` for PR-merged. Anything else will be
  rejected at the API layer.
- **Renovate's Dependency Dashboard** is an issue auto-created in each managed
  repo. Don't close it — Renovate reopens it.

## Related

- `manifests/arc/scale-sets.yml` — the `arc-pilot-dev` scale set the
  orchestrator runs on.
- `/app/.claude/rules/cmdb-discipline.md` — why every change becomes a
  cmdb_changes entry, even Renovate proposals.
- Wiki `/operations/runbooks/` — long-form versions of these notes once the
  pilot ships.
