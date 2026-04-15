# Infra-platform backlog

Running list of planned / proposed additions. Not tracked in Linear or
issues — this file is the canonical surface. Group by priority; bump
entries up when the driving signal gets stronger.

## P1 — high value / near term

(none currently)

## P2 — medium value

- **Ephemeral / JIT GitHub Actions runners**
  Today each registered repo holds a persistent `Runner.Listener` process
  (~150–250 MB RSS each) idling on the runner LXC. With ~17 dev repos
  registered this costs several GB of baseline memory and scales linearly
  as we onboard more apps. Nightly `runner-restart.timer` (added 2026-04-15)
  reclaims leaked RSS but does not reduce the baseline.

  Move to ephemeral runners: each job spins up a fresh listener via a
  just-in-time (JIT) registration token, the runner exits when the job
  completes, and idle memory drops to near zero. Two viable shapes:
  1. **GitHub JIT tokens + small controller** — a lightweight service on
     the runner LXC (or management LXC) listens for `workflow_job` webhooks,
     mints JIT tokens via the GitHub API, and launches short-lived runner
     containers/processes per job.
  2. **actions-runner-controller on k3s** — operator-style; watches webhooks
     and schedules runner pods. More moving parts but handles autoscaling
     and cleanup natively.

  Blockers:
  - Personal-account repos can only register **repo-level** runners (no
    org-level), so the controller must know which repo each job belongs to
    and hold a PAT scoped per-repo.
  - Requires persistent working-directory assumptions to change — several
    pipelines hardcode `cd /app/infra-platform` instead of using
    `$GITHUB_WORKSPACE`. Those need to migrate first.

  Trigger to revisit: sustained >70% memory utilisation on any runner LXC,
  or >~25 registered repos on a single env.

- **LXC memory alerting + auto-cleanup hook**
  Scrape runner LXCs with node_exporter, alert at >80% memory in Grafana,
  and wire the alert to a `cleanup-runner.yml` workflow that SSHs in and
  restarts services. Only worth doing once the nightly timer proves
  insufficient — alert-driven restarts can fire mid-job and kill in-flight
  CI if not gated carefully.

## P3 — nice to have / long tail

(none currently)

## Done

- **Recovery from runner LXC reprovisioning** — PR #137, 2026-04-15.
  `registered-repos.yml` + pipeline replay step.
- **Nightly runner-listener RSS reclaim timer** — added 2026-04-15.
  `runner-restart.timer` in `ansible/github-runner/github-runner_setup.yml`.
