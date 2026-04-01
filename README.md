# Infrastructure Platform

Container-based infrastructure management using Terraform and Ansible with **separate** HashiCorp Vault for secrets management.

## Architecture

This platform uses Docker containers to provide a consistent, isolated environment for infrastructure operations:

- **Terraform Container**: `hashicorp/terraform:1.6.4` - Infrastructure provisioning
- **Ansible Container**: `quay.io/ansible/ansible-core:latest` - Configuration management  
- **Vault**: **Separate system** - Running independently at `http://localhost:8200`
- **GitHub Runner**: Self-hosted runner for CI/CD pipelines

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- SSH keys configured for target systems
- Access to Proxmox API (if using Proxmox provider)

### Setup

1. **Ensure Vault is running separately:**
```bash
# Check Vault status (should be running from separate repository)
curl http://localhost:8200/v1/sys/health
```

2. **Test infrastructure tools:**
```bash
# Test container access
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version
```

### Usage

#### Terraform Operations
```bash
# Initialize Terraform
./scripts/run-terraform.sh init

# Plan changes
./scripts/run-terraform.sh plan

# Apply changes
./scripts/run-terraform.sh apply

# Destroy infrastructure
./scripts/run-terraform.sh destroy
```

#### Ansible Operations
```bash
# Install collections
./scripts/run-ansible.sh galaxy collection install community.general

# Run playbook
./scripts/run-ansible.sh playbook -i inventory.yml playbook.yml

# Check connectivity
./scripts/run-ansible.sh inventory -i inventory.yml --list-hosts
```

## Project Structure

```
├── docker-compose.yml          # Container orchestration
├── scripts/
│   ├── run-terraform.sh       # Terraform container wrapper
│   ├── run-ansible.sh         # Ansible container wrapper
│   └── setup-github-runner.sh # GitHub runner setup
├── terraform/
│   └── dev/                   # Development environments
├── ansible/
│   └── dev/                   # Development playbooks
├── .github/workflows/         # CI/CD pipelines
└── docs/                      # Documentation
```

## Container Management

### Tool Containers
```bash
# Terraform and Ansible containers run on-demand via wrapper scripts
# They don't need to be running continuously

# Test container access
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version

# View running containers (should only see Vault if it's running)
docker ps
```

### Update Containers
```bash
# Pull latest versions
docker compose pull terraform ansible

# Test updated versions
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version
```

## GitHub Actions Integration

The platform includes self-hosted GitHub Actions workflows that use the container-based tools:

- `media-stack_pipeline_self_hosted.yml` - Media stack deployment
- `network-vm_pipeline_self_hosted.yml` - Network VM management

See `docs/GITHUB_RUNNER_SETUP.md` for complete setup instructions.

## Vault Integration

Vault is **managed separately** and runs independently at `http://localhost:8200`:

1. **External Vault**: Running from separate repository
2. **Secret Storage**: SSH keys, passwords, and configuration
3. **Integration**: Terraform and Ansible access Vault via host network

### Vault Operations
```bash
# Check Vault status (external)
curl http://localhost:8200/v1/sys/health

# Login (development token)
export VAULT_TOKEN=myroot
export VAULT_ADDR=http://localhost:8200

# List secrets
vault kv list secret/
```

## Security Considerations

- **Container Isolation**: Tools run in isolated containers
- **SSH Keys**: Mounted read-only into containers
- **Vault Token**: Use GitHub Secrets for production tokens
- **Network Access**: Containers communicate via dedicated network
- **Version Pinning**: Specific container versions are pinned

## Troubleshooting

### Container Issues
```bash
# Check container status
docker ps

# View logs
docker-compose logs [service]

# Restart containers
docker-compose restart [service]
```

### Permission Issues
```bash
# Check Docker group membership
groups $USER | grep docker

# Add user to docker group
sudo usermod -aG docker $USER
```

### Volume Issues
```bash
# Check volume mounts
docker-compose config | grep volumes

# Test SSH key access
docker-compose run --rm terraform ls -la /root/.ssh
```

## Development

### Adding New Terraform Modules
1. Create module in `terraform/dev/`
2. Update container volumes if needed
3. Test with `./scripts/run-terraform.sh`

### Adding New Ansible Playbooks
1. Create playbook in `ansible/dev/`
2. Update inventory files
3. Test with `./scripts/run-ansible.sh`

### Container Customization
Edit `docker-compose.yml` to:
- Change container versions
- Add environment variables
- Modify volume mounts
- Adjust network settings

## Benefits of Container-Based Approach

- ✅ **Version Isolation**: Exact tool versions pinned in containers
- ✅ **Clean Host**: No system-wide installations required
- ✅ **Consistent Environment**: Same containers work across machines
- ✅ **Better Security**: Tools isolated from host system
- ✅ **Easy Updates**: Update by changing container versions
- ✅ **Persistent Caching**: Volume mounts preserve plugins and collections
- ✅ **Network Isolation**: Containers communicate via dedicated network
- ✅ **Resource Management**: Container resource limits available
- ✅ **Parallel Execution**: Multiple container instances can run simultaneously

## Support

For issues and questions:

1. Check container logs: `docker-compose logs`
2. Verify network connectivity: `docker network inspect`
3. Test tool access: `./scripts/run-terraform.sh version`
4. Review documentation in `docs/` directory
# Test change
