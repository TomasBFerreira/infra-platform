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

and one synthetic alert condition per enabled simple monitor.

That means a failing check can generate a New Relic incident instead of only existing as a red monitor.

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
- reads the New Relic credentials from Vault
- creates or updates repo-managed monitors
- creates the shared alert policy if it does not exist
- creates or updates synthetic alert conditions for enabled simple monitors
- only deletes repo-managed monitors when explicitly told to prune

Only monitors whose names start with `Homelab | ` are considered repo-managed.

The initial implementation does not create notification destinations or incident workflows yet. That part depends on how you want New Relic to notify you (email, Slack, webhook, etc.) and whether those destinations already exist in the account.
