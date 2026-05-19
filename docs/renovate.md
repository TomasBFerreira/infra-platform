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

After creation, note the **App ID**. (The Installation ID is not needed —
`actions/create-github-app-token@v1` auto-discovers the installation from
the `owner` parameter.)

### 2. Install the app on the pilot repo

Install URL → choose **TomasBFerreira/nextcloud** only for the pilot.
Add more repos later as we widen scope.

### 3. Seed credentials into the BOOTSTRAP vault

Despite the CLAUDE.md secrets table suggesting otherwise, **every workflow
in this repo authenticates against the bootstrap vault (CT 200,
192.168.50.200)**, not the env vaults. The env vaults' CI tokens are not
wired into GitHub Actions secrets — `VAULT_TOKEN` exists but the value
behind it isn't a working dev-env-vault token. Use bootstrap.

```bash
vault kv put -address=$VAULT_BOOTSTRAP_ADDR secret/renovate/github-app \
  app_id=<numeric app id> \
  private_key=@/path/to/renovate.private-key.pem
```

Or via HTTP API from a host with mgmt-network reach (e.g. benedict or betsy)
— this is the path I used during pilot bootstrap on 2026-05-18:

```bash
# Get the root token off the bootstrap vault CT itself (benedict in this homelab):
ssh root@192.168.50.4 'pct exec 200 -- jq -r .root_token /root/vault-init.json'

# Then write:
PEM=$(cat renovate.private-key.pem)
curl -X POST \
  -H "X-Vault-Token: <bootstrap-root-token>" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg id <app-id> --arg pk "$PEM" \
        '{data:{app_id:$id, private_key:$pk}}')" \
  http://192.168.50.200:8200/v1/secret/data/renovate/github-app
```

The orchestrator workflow authenticates with `secrets.VAULT_RENOVATE_TOKEN`,
a scoped periodic token (`period=768h`) attached to the `renovate` vault
policy. The policy allows read+list on `secret/data/renovate/*` and
`secret/metadata/renovate/*` and nothing else. To rotate the token, on a
host with bootstrap-vault root-token access:

```bash
ROOT=$(ssh root@192.168.50.4 'pct exec 200 -- jq -r .root_token /root/vault-init.json')
NEW_TOKEN=$(curl -sS -H "X-Vault-Token: $ROOT" \
  -d '{"policies":["renovate"],"period":"768h","display_name":"renovate","no_default_policy":true,"renewable":true}' \
  http://192.168.50.200:8200/v1/auth/token/create | jq -r .auth.client_token)
echo -n "$NEW_TOKEN" | gh secret set VAULT_RENOVATE_TOKEN --repo TomasBFerreira/infra-platform
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
