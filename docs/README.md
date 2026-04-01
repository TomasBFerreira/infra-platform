# infra-platform Documentation

Homelab infrastructure managed via Terraform + Ansible + GitHub Actions on a self-hosted runner.

## Contents

| Document | Description |
|----------|-------------|
| [architecture.md](architecture.md) | Overall system architecture and component overview |
| [network.md](network.md) | IP scheme, Proxmox nodes, Cloudflare tunnel, Traefik |
| [vaults.md](vaults.md) | Vault architecture, secrets inventory, recovery |
| [pipelines.md](pipelines.md) | CI/CD pipelines — what they do and how to run them |
| [services.md](services.md) | Deployed services — SSO, network-vm, vault-ct |
| [runbooks.md](runbooks.md) | Operational runbooks for common tasks and recovery |