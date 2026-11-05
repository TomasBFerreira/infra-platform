# New Relic synthetics inventory

This directory is the repo-managed desired state for internet-facing New Relic synthetic monitors and their first-pass alert wiring.

## What is enabled now

The initial sync only manages anonymous front doors that should answer directly from the public internet:

- `https://databaes.net`
- `https://signup.databaes.net`
- `https://auth.databaes.net`

These provide high-signal coverage for the public edge, Traefik reachability, certificate health, and Authentik availability.

The sync script also manages a shared alert policy:

- `Homelab | Internet synthetic monitors`

and one location-failure alert condition per enabled simple monitor.

That means a failing check can generate a New Relic incident instead of only existing as a red monitor.

Conditions use `conditionDefaults.violationTimeLimitSeconds` = `86400` (24 h, the maximum the location-failure API allows). New Relic force-closes a still-failing violation at this limit and opens a fresh one, which re-notifies. At the old 3600 default, one long outage re-paged about hourly per monitor (2026-11-01..05: ~200 notifications/day from nine DEV monitors).

## Per-monitor `alert` flag

Each monitor entry can set `"alert": false` to keep the synthetic running (data stays in New Relic) but stop creating an alert condition for it. The eight `DEV | ops …` monitors (`ops-dev.databaes.net` and the per-service checks) are set this way: `*-dev.databaes.net` is Tailscale-only by design (see `docs/network.md` § Cloudflare Tunnels), so a public synthetic against it cannot pass unless a Cloudflare route is created by hand, and it only produced noise (2026-11-05). `DEV | dev.tomajflix.app` still alerts because it has a permanent public route.

**Caveat:** setting `alert: false` does not delete a condition that already exists. The sync only deletes conditions with `--allow-delete` (workflow `prune=true`), and `managed_prefixes()` only covers the default `PROD | ` and legacy `Homelab | ` prefixes, so existing `DEV | … down` conditions are never pruned by the script. Delete them in New Relic (or via the alerts API) after merging.

## What is intentionally deferred

Apps behind Authentik SSO are listed in `monitors.json` with `mode: "probe-endpoint"` and `enabled: false`.

That keeps the desired inventory visible without creating noisy or misleading monitors that only prove a redirect worked.

Recommended pattern for those services:

1. Add a narrow synthetic endpoint such as `/synthetic/ping`.
2. Protect it with a static header like `X-Synthetic-Token`.
3. Store that token in Vault, not in GitHub or the repo.
4. Extend the sync script to inject the header for those monitor definitions.

Suggested Vault layout:

- `secret/monitoring/shared/newrelic`
  - `user_api_key`
  - `account_id`
  - `region`
- `secret/monitoring/shared/probe_tokens/<service-slug>`
  - `token`

`account_id` may remain a string in Vault.

## Workflow behavior

`.github/workflows/sync-newrelic-synthetics.yml`:

- validates the monitor inventory
- reads the New Relic credentials from prod Vault using the existing `VAULT_PROD_ADDR` and `VAULT_PROD_TOKEN` repo secrets
- creates or updates repo-managed monitors
- creates the shared alert policy if it does not exist
- creates or updates location-failure alert conditions for enabled simple monitors
- only deletes repo-managed monitors when explicitly told to prune

Only monitors whose names start with `Homelab | ` are considered repo-managed.

The initial implementation does not create notification destinations or incident workflows yet. That part depends on how you want New Relic to notify you (email, Slack, webhook, etc.) and whether those destinations already exist in the account.
