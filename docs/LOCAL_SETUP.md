# Local Development Setup

This guide covers setting up the infrastructure platform for local development with your self-hosted GitHub Actions runner.

## Environment Variables

For local development, you can set environment variables instead of GitHub secrets:

### Option 1: Shell Environment Variables
```bash
# Add to ~/.bashrc or run in your terminal
export PVE_API="https://your-proxmox-host:8006/api2/json"
export PVE_USER="root@pam" 
export PVE_PASS="your-proxmox-password"
export SSH_USER="root"
```

### Option 2: .env File
```bash
# Create .env file in project root
cp .env.example .env
# Edit .env with your actual values
```

### Option 3: GitHub Secrets (Optional)
You can still use GitHub secrets if you prefer:
1. Go to repository Settings → Secrets and variables → Actions
2. Add these secrets:
   - `PVE_API`: Your Proxmox API URL
   - `PVE_USER`: Proxmox username (e.g., "root@pam")
   - `PVE_PASS`: Proxmox password
   - `SSH_USER`: SSH user for VMs (usually "root")

## Proxmox (PVE) Configuration

### What is PVE?
PVE = Proxmox Virtualization Environment - your hypervisor platform.

### Current Setup
Your Terraform files are configured for:
- **Target Node**: "betsy" (both media-stack and network-vm)
- **VM IDs**: 
  - Media Stack: 200
  - Network VM: 220
- **Network**: 192.168.50.x subnet

### Multiple Nodes?
If you have multiple Proxmox nodes:

1. **Update target_node** in Terraform files:
   ```hcl
   # In terraform/dev/media-stack/main.tf
   target_node = "your-node-name"
   
   # In terraform/dev/network-vm/main.tf  
   target_node = "your-node-name"
   ```

2. **Consider node-specific variables**:
   ```hcl
   variable "target_node" {
     description = "Proxmox target node"
     default     = "betsy"
   }
   
   # Then use: target_node = var.target_node
   ```

3. **Network considerations**:
   - Ensure VM IPs don't conflict across nodes
   - Check network bridges are consistent
   - Verify firewall rules allow inter-node communication

## Quick Start

### 1. Set Environment Variables
```bash
# Choose one option:
export PVE_API="https://192.168.50.1:8006/api2/json"  # Your Proxmox host
export PVE_USER="root@pam"
export PVE_PASS="your-password"
export SSH_USER="root"
```

### 2. Test Local Access
```bash
# Test Terraform access
./scripts/run-terraform.sh -chdir=terraform/dev/media-stack init
./scripts/run-terraform.sh -chdir=terraform/dev/media-stack plan

# Test Ansible access (if VM exists)
./scripts/run-ansible.sh --version
```

### 3. Push to Dev Branch
```bash
# Make changes and push
git add .
git commit -m "feat: Update Proxmox configuration"
git push origin dev
```

## Node-Specific Configuration

### Different Nodes per Environment
If you want different nodes for different environments:

```hcl
# terraform/dev/media-stack/main.tf
variable "target_node" {
  description = "Proxmox target node for media stack"
  default     = "betsy"  # Change this per your setup
}

resource "proxmox_lxc" "media_stack_worker" {
  # ... other config ...
  target_node = var.target_node
}
```

### Environment-Based Nodes
You could use environment variables:
```hcl
target_node = getenv("MEDIA_STACK_NODE", "betsy")
```

Then set in your environment:
```bash
export MEDIA_STACK_NODE="node1"
export NETWORK_VM_NODE="node2"
```

## Troubleshooting

### Proxmox API Issues
```bash
# Test API access
curl -k "https://your-proxmox-host:8006/api2/json/version" \
  --data "username=root@pam!your-token" \
  --data "password=your-password"
```

### Terraform Provider Issues
```bash
# Check Proxmox provider version
./scripts/run-terraform.sh -chdir=terraform/dev/media-stack init

# Test provider connection
./scripts/run-terraform.sh -chdir=terraform/dev/media-stack validate
```

### Node Connectivity
```bash
# Test SSH to existing VMs
ssh root@192.168.50.211  # Media stack
ssh root@192.168.50.251  # Network VM
```

## Security Notes

### Local Development
- Environment variables are fine for local dev
- Don't commit actual passwords to git
- Consider using Proxmox tokens instead of passwords

### Production Considerations
- Use GitHub secrets for production workflows
- Consider Proxmox API tokens with limited permissions
- Use SSH keys instead of passwords where possible

## Next Steps

1. **Configure your Proxmox details** in environment variables
2. **Test local access** with wrapper scripts
3. **Push changes** to dev branch to test workflow
4. **Monitor GitHub Actions** to ensure everything works
5. **Adjust node configurations** as needed for your setup
