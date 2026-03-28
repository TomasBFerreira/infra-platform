# GitHub Actions Runner Setup

## Architecture

Two-tier runner setup: a permanent **management runner** on the bootstrap vault (CT 200) and per-env **env runners** provisioned by the github-runner pipeline.

| Runner | CT | Label | Purpose |
|--------|----|-------|---------|
| management | CT 200 (192.168.50.200) | `[self-hosted, management]` | Runs github-runner pipeline only; never destroyed |
| env runner — dev | CT 201 (192.168.20.101) | `[self-hosted, linux, dev]` | Runs all dev pipelines |
| env runner — prod | CT 101 (192.168.10.101) | `[self-hosted, linux, prod]` | Runs all prod pipelines |
| env runner — qa | CT 301 (192.168.30.101) | `[self-hosted, linux, qa]` | Runs all qa pipelines |

**Why two tiers?** The github-runner pipeline provisions and destroys the env runner CT. If the pipeline ran on the env runner itself, it would destroy its own host mid-run. CT 200 is never touched by any pipeline so it's a stable bootstrap point — even a full env teardown can be recovered by triggering the github-runner pipeline.

## Provisioning an env runner

Run the github-runner pipeline (it runs on the management runner on CT 200):

```bash
gh workflow run github-runner_pipeline_self_hosted.yml \
  --repo TomasBFerreira/infra-platform \
  --field environment=dev \
  --field github_repo=TomasBFerreira/infra-platform
```

Or via GitHub UI: **infra-platform → Actions → GitHub Runner Pipeline → Run workflow**

The pipeline:
1. Destroys any existing runner CT at that VMID
2. Provisions a fresh Debian 12 LXC via Terraform
3. Runs `ansible/github-runner/github-runner_setup.yml` which:
   - Installs dependencies (Docker, Vault CLI, GitHub CLI, Ansible, Terraform)
   - Installs the Proxmox access SSH key (from bootstrap vault)
   - Installs and registers the GitHub Actions runner binary
   - Clones `/app/infra-platform` as a persistent working directory
4. Saves runner state to bootstrap vault at `secret/github-runner/<env>/state`

## Registering a runner for an additional repo

Each repo that needs CI/CD on the shared env runner LXC uses the `register-runner.yml` workflow. See [runbooks.md](runbooks.md#registering-a-github-actions-runner-for-a-new-repo).

## Runner filesystem layout (env runner)

```
/opt/github-runners/
    tomasbferreira-infra-platform/   # runner for this repo
        bin/Runner.Listener          # runner binary
        _work/                       # job workspace
        .runner                      # registration state
    <other-repo-slug>/               # additional registered repos (one dir per repo)

/app/infra-platform/                 # persistent clone (pipelines cd here)
/app/traefik-gitops/                 # persistent clone (network-vm/semaphore/torrent pipelines)
```

## Management runner (CT 200)

CT 200 runs both the bootstrap vault and the management runner. Installed tools:

| Tool | Path | Purpose |
|------|------|---------|
| terraform | `/usr/bin/terraform` | Runs Terraform directly (no Docker on CT 200) |
| vault | system (`apt`) | Reads secrets from bootstrap vault |
| gh | system (`apt`) | Sets GitHub secrets |
| ansible | system (`apt`) | Runs Ansible playbooks |
| Proxmox SSH key | `/root/.ssh/id_ed25519` | SSHes to Proxmox for pct commands |

Runner service: `actions.runner.TomasBFerreira-infra-platform.github-runner-management`

**Terraform on CT 200 runs without Docker.** `scripts/run-terraform.sh` detects Docker unavailability and falls back to the direct `terraform` binary. This is expected on CT 200.

## Updating the runner binary version

Change `runner_version` in `ansible/github-runner/github-runner_setup.yml`, then re-run the github-runner pipeline for each env.

## Troubleshooting

See [runbooks.md — GitHub Actions runner is stuck](runbooks.md#github-actions-runner-is-stuck).
