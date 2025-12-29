# GitHub Actions Self-Hosted Runner Setup Guide (Container-Based)

## Overview
This guide helps you set up a GitHub Actions self-hosted runner on your l-ct-dev1 host using Docker containers for Terraform and Ansible. This approach provides better isolation, version management, and consistency for your CI/CD pipelines with access to your separate HashiCorp Vault instance.

## Prerequisites

- Ubuntu/Debian Linux system (l-ct-dev1)
- Root/sudo access
- Docker and Docker Compose installed
- **Separate Vault instance** running at http://localhost:8200 (managed in its own repository)
- GitHub repository access

## Architecture

- **GitHub Runner**: Runs on host system
- **Terraform**: Runs in Docker container (hashicorp/terraform:1.6.4)
- **Ansible**: Runs in Docker container (quay.io/ansible/ansible-core:latest)
- **Vault**: **Separate system** - running independently at http://localhost:8200
- **Shared Network**: Terraform/Ansible containers communicate via Docker bridge network

## Installation Steps

### 1. Install Docker and Prerequisites

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git jq

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Add current user to docker group (optional, for manual testing)
sudo usermod -aG docker $USER

# Verify installation
docker --version
docker-compose --version
```

### 2. Setup Container-Based Infrastructure Tools

```bash
# Navigate to project
cd /app/infra-platform

# Start infrastructure containers (Terraform, Ansible)
docker compose --profile tools pull terraform ansible

# Verify containers can be accessed (they run on-demand)
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version

# Note: Vault is managed separately and should already be running
# Verify Vault connectivity
curl http://localhost:8200/v1/sys/health
```

### 3. Run Runner Installation Script

```bash
cd /app/infra-platform
chmod +x scripts/setup-github-runner.sh
sudo ./scripts/setup-github-runner.sh
```

### 4. Register Runner with GitHub

1. Go to your GitHub repository
2. Navigate to: **Settings** → **Actions** → **Runners** → **New self-hosted runner**
3. Select **Linux** as the OS
4. Copy the registration token from the page
5. Run the configuration commands:

```bash
sudo su - github-runner
cd /opt/github-runner

# Configure the runner with your token
./config.sh --url https://github.com/YOUR_USERNAME/YOUR_REPO --token YOUR_TOKEN

# When prompted:
# - Enter runner name: dev-runner-01 (or any name you prefer)
# - Enter runner group: [Press Enter for default]
# - Enter labels: [Press Enter for default, or add: dev,vault,terraform]
# - Enter work folder: [Press Enter for default: _work]

# Exit back to root
exit
```

### 5. Install Runner as a Service

```bash
# Install the service (as root)
cd /opt/github-runner
sudo ./svc.sh install github-runner

# Start the service
sudo ./svc.sh start

# Check status
sudo ./svc.sh status

# View logs
sudo journalctl -u actions.runner.* -f
```

### 6. Configure Container Access for Runner

The runner needs access to Docker to run Terraform and Ansible containers:

```bash
# Add runner user to docker group
sudo usermod -aG docker github-runner

# Create wrapper scripts for runner
sudo tee /opt/github-runner/terraform << 'EOF'
#!/bin/bash
cd /app/infra-platform
./scripts/run-terraform.sh "$@"
EOF

sudo tee /opt/github-runner/ansible << 'EOF'
#!/bin/bash
cd /app/infra-platform
./scripts/run-ansible.sh "$@"
EOF

# Make scripts executable
sudo chmod +x /opt/github-runner/terraform /opt/github-runner/ansible
sudo chown github-runner:github-runner /opt/github-runner/terraform /opt/github-runner/ansible

# Restart runner service to apply group changes
sudo ./svc.sh stop
sudo ./svc.sh start
```

### 7. Configure Environment Variables

If you want to set persistent environment variables for the runner:

```bash
# Create environment file
sudo mkdir -p /opt/github-runner/.env
sudo tee /opt/github-runner/.env/vault.env << EOF
VAULT_ADDR=http://localhost:8200
VAULT_TOKEN=myroot
EOF

sudo chown github-runner:github-runner /opt/github-runner/.env/vault.env
```

### 8. Update Workflows

The new workflow files have been created:
- `.github/workflows/media-stack_pipeline_self_hosted.yml`
- `.github/workflows/network-vm_pipeline_self_hosted.yml`

You can either:
- **Option A**: Delete the old workflow files and rename the new ones (remove `_self_hosted` suffix)
- **Option B**: Keep both and disable the old workflows in GitHub UI

## Verify Setup

### Test Vault Connection from Runner

```bash
sudo su - github-runner
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot
vault status
vault kv list secret/
exit
```

### Test Terraform Container

```bash
sudo su - github-runner
cd /app/infra-platform
./scripts/run-terraform.sh version
./scripts/run-terraform.sh init -help
exit
```

### Test Ansible Container

```bash
sudo su - github-runner
cd /app/infra-platform
./scripts/run-ansible.sh --version
./scripts/run-ansible.sh galaxy list
exit
```

### Test Container Integration

```bash
# Test that containers can access external Vault
sudo su - github-runner
cd /app/infra-platform
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

# Test from Terraform container
./scripts/run-terraform.sh version && echo "Terraform container works"

# Test from Ansible container
./scripts/run-ansible.sh --version && echo "Ansible container works"

# Test Vault connectivity
curl -s http://localhost:8200/v1/sys/health && echo "Vault accessible"
exit
```

## Troubleshooting

### Runner Not Showing Online
```bash
# Check service status
sudo systemctl status actions.runner.*

# Check logs
sudo journalctl -u actions.runner.* -n 50

# Restart service
sudo ./svc.sh stop
sudo ./svc.sh start
```

### Permission Issues
```bash
# Ensure runner user has correct permissions
sudo chown -R github-runner:github-runner /opt/github-runner
```

### Vault Connection Issues
```bash
# Test from runner user
sudo su - github-runner
curl http://localhost:8200/v1/sys/health
```

### Docker Permission Issues
```bash
# Check if runner is in docker group
groups github-runner | grep docker

# If not, add and restart
sudo usermod -aG docker github-runner
sudo ./svc.sh stop
sudo ./svc.sh start

# Test container access
sudo -u github-runner docker ps
```

### Container Network Issues
```bash
# Check container network
docker network ls

# Test connectivity between containers
docker network inspect infra-platform_infra-network

# Restart containers if needed
docker-compose down
docker-compose --profile services up -d
```

### Volume Mount Issues
```bash
# Check volume mounts
docker-compose config | grep -A5 -B5 volumes

# Test SSH key access
docker-compose run --rm terraform ls -la /root/.ssh
```

## Container Management

### Start/Stop Infrastructure Containers
```bash
# Note: Terraform and Ansible containers run on-demand via wrapper scripts
# They don't need to be running continuously

# Test container access
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version

# View running containers (should only see Vault from separate system)
docker ps

# Clean up any stopped containers
docker container prune
```

### Update Container Images
```bash
# Pull latest versions
docker compose pull terraform ansible

# Test updated versions
./scripts/run-terraform.sh version
./scripts/run-ansible.sh --version
```

### Clean Up Containers
```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes (careful!)
docker volume prune
```

## Maintenance

### Update Runner
```bash
sudo ./svc.sh stop
sudo su - github-runner
cd /opt/github-runner
./config.sh remove --token YOUR_REMOVAL_TOKEN
# Download new version and extract
# Re-register with ./config.sh
exit
sudo ./svc.sh install github-runner
sudo ./svc.sh start
```

### Remove Runner
```bash
# Stop service
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# Remove registration
sudo su - github-runner
cd /opt/github-runner
./config.sh remove --token YOUR_REMOVAL_TOKEN
exit

# Clean up
sudo rm -rf /opt/github-runner
sudo userdel -r github-runner
```

## Security Considerations

1. **Vault Token**: Consider using a more secure token management approach in production
2. **Runner Access**: The runner has access to your local network and Vault
3. **Secrets**: Use GitHub Secrets for sensitive credentials (Proxmox passwords, etc.)
4. **Network**: Ensure proper firewall rules are in place
5. **Updates**: Keep the runner software updated

## Benefits of Container-Based Approach

- ✅ **Version Isolation**: Exact Terraform/Ansible versions pinned in containers
- ✅ **Clean Host**: No system-wide installations required
- ✅ **Consistent Environment**: Same containers work across different machines
- ✅ **Better Security**: Tools isolated from host system
- ✅ **Easy Updates**: Update by changing container versions
- ✅ **Persistent Caching**: Volume mounts preserve plugins and collections
- ✅ **Network Isolation**: Containers communicate via dedicated network
- ✅ **Resource Management**: Container resource limits available
- ✅ **Parallel Execution**: Multiple container instances can run simultaneously

## Container Configuration Details

### Terraform Container
- **Image**: hashicorp/terraform:1.6.4
- **Features**: Plugin caching, SSH key mounting, workspace mounting
- **Cache**: Persistent volume for provider plugins

### Ansible Container
- **Image**: quay.io/ansible/ansible-core:latest
- **Features**: Collection cache, SSH key mounting, workspace mounting
- **Cache**: Persistent volume for collections and roles

### Vault Container
- **Image**: **Separate system** - not managed in this compose file
- **Features**: Data persistence, configuration mounting
- **Network**: Exposed on host port 8200 (accessible from Terraform/Ansible containers)
- **Management**: See separate Vault repository for configuration

## Security Considerations

1. **Vault Token**: Consider using GitHub Secrets for production tokens
2. **Docker Socket**: Runner has Docker access - ensure proper security
3. **SSH Keys**: Mounted read-only into containers
4. **Network Isolation**: Containers on dedicated bridge network, Vault accessible via host
5. **Volume Permissions**: Proper ownership of mounted volumes
6. **Container Images**: Use specific version tags, not `latest`
7. **Runner Access**: Runner has access to local network and containers
8. **Vault Separation**: Vault is managed separately - ensure proper access controls
