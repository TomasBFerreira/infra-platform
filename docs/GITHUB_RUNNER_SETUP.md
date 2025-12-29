# GitHub Actions Self-Hosted Runner Setup Guide

## Overview
This guide helps you set up a GitHub Actions self-hosted runner on your l-ct-dev1 host to run CI/CD pipelines locally with access to your HashiCorp Vault instance.

## Prerequisites

- Ubuntu/Debian Linux system (l-ct-dev1)
- Root/sudo access
- Docker installed (if needed for workflows)
- Terraform installed
- Ansible installed
- Vault CLI installed
- HashiCorp Vault running at http://localhost:8200

## Installation Steps

### 1. Install Prerequisites on Runner Host

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git jq unzip

# Install Terraform (if not already installed)
wget https://releases.hashicorp.com/terraform/1.6.4/terraform_1.6.4_linux_amd64.zip
unzip terraform_1.6.4_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform --version

# Install Vault CLI (if not already installed)
wget https://releases.hashicorp.com/vault/1.21.0/vault_1.21.0_linux_amd64.zip
unzip vault_1.21.0_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version

# Install Ansible
sudo apt install -y python3-pip
pip3 install ansible hvac
ansible-galaxy collection install community.general community.hashi_vault

# Install Docker (if needed)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### 2. Run Runner Installation Script

```bash
cd /app/infra-platform
chmod +x scripts/setup-github-runner.sh
sudo ./scripts/setup-github-runner.sh
```

### 3. Register Runner with GitHub

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

### 4. Install Runner as a Service

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

### 5. Configure Environment Variables (Optional)

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

### 6. Update Workflows

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

### Test Terraform

```bash
sudo su - github-runner
cd /opt/github-runner/_work/YOUR_REPO/YOUR_REPO
terraform --version
exit
```

### Test Ansible

```bash
sudo su - github-runner
ansible --version
ansible-galaxy collection list
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

### Docker Permission Issues (if using Docker)
```bash
# Add runner to docker group
sudo usermod -aG docker github-runner

# Restart runner service
sudo ./svc.sh stop
sudo ./svc.sh start
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

## Benefits of Self-Hosted Runner

- ✅ Direct access to local Vault instance (no network exposure needed)
- ✅ Access to local network resources (Proxmox, VMs, etc.)
- ✅ Faster builds (no need to download tools each time)
- ✅ No GitHub Actions minutes consumption
- ✅ Better integration with local infrastructure
- ✅ Persistent environment and caching

## Next Steps

1. Test the runner with a simple workflow
2. Monitor the first few pipeline runs
3. Adjust runner resources if needed
4. Consider setting up multiple runners for parallel jobs
5. Set up monitoring/alerting for runner health
