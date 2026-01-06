# Terraform Proxmox Templates

Reusable Terraform modules for creating LXC containers and VMs in Proxmox.

## Modules

### 1. `proxmox-lxc`
Creates Debian-based LXC containers with optional Vault integration for SSH keys.

**Features:**
- Configurable CPU, memory, swap
- Network configuration with static IP
- Docker support via nesting feature
- SSH key deployment from Vault
- Automatic provisioning of SSH authorized_keys

### 2. `proxmox-vm`
Creates QEMU virtual machines with support for both ISO installation and template cloning.

**Features:**
- Configurable CPU, memory, disk
- ISO-based installation or template cloning
- Cloud-init support (optional)
- SSH key deployment from Vault or direct input
- QEMU guest agent support
- Serial console access

## Directory Structure

```
terraform/
├── modules/
│   ├── proxmox-lxc/          # Reusable LXC module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── proxmox-vm/           # Reusable VM module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── examples/
│   ├── lxc-infra/            # Example: Infra, Network, Monitoring, Backup LXCs
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── vm-worker-node/       # Example: Ubuntu 24.04 worker VMs
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── dev/                      # Your existing dev environment
    ├── media-stack/
    └── network-vm/
```

## Quick Start

### Using the LXC Module

```hcl
module "my_container" {
  source = "../../modules/proxmox-lxc"
  
  vmid     = 200
  hostname = "my-container"
  
  cores  = 2
  memory = 2048
  
  network_ip      = "192.168.50.200/24"
  network_gateway = "192.168.50.1"
  
  rootfs_size = "32G"
  
  # Option 1: Use SSH key from Vault
  ssh_key_vault_path = "secret/ssh_keys/my_container"
  
  # Option 2: Provide SSH key directly (if not using Vault)
  # ssh_public_keys = "ssh-ed25519 AAAAC3... user@host"
  
  target_node = "benedict"
}
```

### Using the VM Module

```hcl
module "my_vm" {
  source = "../../modules/proxmox-vm"
  
  vmid = 100
  name = "my-vm"
  
  cores  = 4
  memory = 8192
  
  # Option 1: Use ISO for fresh installation
  iso = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
  
  # Option 2: Clone from template (comment out iso above)
  # clone_template = "ubuntu-24.04-template"
  # full_clone     = true
  
  disk_storage = "local-lvm"
  disk_size    = "100G"
  
  network_bridge = "vmbr0"
  
  # Enable cloud-init if using a cloud-init template
  cloudinit_enabled = false
  
  # If cloud-init is enabled:
  # cloudinit_enabled = true
  # cloudinit_user    = "ubuntu"
  # network_ip        = "192.168.50.100/24"
  # network_gateway   = "192.168.50.1"
  # ssh_key_vault_path = "secret/ssh_keys/my_vm"
  
  target_node = "benedict"
}
```

## Examples

### 1. Infrastructure LXC Containers

See `examples/lxc-infra/` for:
- Infra node (Ansible, Terraform, Vault)
- Network node (Traefik LB, Cloudflared tunnel)
- Monitoring node (Prometheus, Grafana)
- Backup node (Restic, Borg, etc.)

**Deploy:**
```bash
cd terraform/examples/lxc-infra
terraform init
terraform plan
terraform apply
```

### 2. Worker Node VMs

See `examples/vm-worker-node/` for Ubuntu 24.04 worker nodes for Docker containers.

**Deploy:**
```bash
cd terraform/examples/vm-worker-node
terraform init
terraform plan
terraform apply
```

After VM is created, you'll need to:
1. Boot from the ISO and complete Ubuntu installation
2. Install Docker and other required packages
3. Configure networking and SSH

## Module Variables

### LXC Module (`proxmox-lxc`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vmid` | number | - | **Required.** VM ID for the container |
| `hostname` | string | - | **Required.** Hostname for the container |
| `network_ip` | string | - | **Required.** IP with CIDR (e.g., "192.168.50.200/24") |
| `target_node` | string | - | **Required.** Proxmox node name |
| `cores` | number | 2 | Number of CPU cores |
| `memory` | number | 2048 | Memory in MB |
| `rootfs_size` | string | "32G" | Root filesystem size |
| `ssh_key_vault_path` | string | "" | Vault path for SSH key (optional) |
| `ssh_public_keys` | string | "" | SSH public keys (if not using Vault) |

### VM Module (`proxmox-vm`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vmid` | number | - | **Required.** VM ID |
| `name` | string | - | **Required.** VM name |
| `target_node` | string | - | **Required.** Proxmox node name |
| `cores` | number | 2 | Number of CPU cores |
| `memory` | number | 2048 | Memory in MB |
| `disk_size` | string | "32G" | Disk size |
| `iso` | string | "local:iso/ubuntu-24.04.3-live-server-amd64.iso" | ISO image to use |
| `clone_template` | string | "" | Template to clone (leave empty to use ISO) |
| `cloudinit_enabled` | bool | false | Enable cloud-init |
| `network_ip` | string | "" | IP with CIDR (for cloud-init) |
| `ssh_key_vault_path` | string | "" | Vault path for SSH key (optional) |

See `variables.tf` in each module for complete list of variables.

## SSH Key Management

Both modules support two ways to manage SSH keys:

### Option 1: Vault (Recommended)
Store SSH keys in Vault and reference them:

```hcl
ssh_key_vault_path = "secret/ssh_keys/container_name"
```

The module will automatically fetch the `public` and `private` fields from Vault.

### Option 2: Direct Input
Provide SSH public key directly:

```hcl
ssh_public_keys = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@host"
```

## Cloud-Init for VMs

To use cloud-init with VMs:

1. Create a cloud-init enabled template in Proxmox
2. Enable cloud-init in your module:
```hcl
cloudinit_enabled = true
cloudinit_user     = "ubuntu"
network_ip         = "192.168.50.100/24"
network_gateway    = "192.168.50.1"
ssh_key_vault_path = "secret/ssh_keys/my_vm"
```

## Integration with Existing Setup

Your existing dev setup can be migrated to use these modules:

**Before:**
```
terraform/dev/media-stack/main.tf  # Custom LXC definition
terraform/dev/network-vm/main.tf   # Custom LXC definition
```

**After:**
```hcl
module "media_stack" {
  source = "../../modules/proxmox-lxc"
  # ... configuration
}

module "network_vm" {
  source = "../../modules/proxmox-lxc"
  # ... configuration
}
```

## Tips

1. **LXC vs VM**: Use LXC for lightweight services (Traefik, monitoring agents). Use VMs for workloads needing full kernel (Docker, K8s, databases).

2. **Resource Allocation**: 
   - Media containers: 4 cores, 4GB RAM
   - Network/proxy: 2 cores, 2GB RAM
   - Monitoring: 4 cores, 4GB RAM
   - Worker nodes: 4+ cores, 8+ GB RAM

3. **Storage**: Use `local-lvm` for production workloads, `local` for templates and ISOs.

4. **Networking**: Ensure your network configuration matches your Proxmox setup (bridge name, IP ranges, gateway).

## Next Steps

1. Review the examples in `examples/`
2. Copy and customize for your environment
3. Set up Vault with SSH keys (or use direct SSH key input)
4. Deploy with `terraform apply`
5. Use Ansible for post-deployment configuration

## Troubleshooting

**Issue: SSH key not deploying**
- Check Vault path and field names (`public` and `private`)
- Verify SSH key format (OpenSSH format, proper newlines)

**Issue: LXC container won't start**
- Check Proxmox logs: `journalctl -xe`
- Verify template exists: `pveam list local`

**Issue: VM stuck at boot**
- Verify ISO exists in Proxmox storage
- Check boot order configuration
- Enable serial console for debugging

## Support

For issues or questions, check:
- Terraform Proxmox provider docs: https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
- Proxmox documentation: https://pve.proxmox.com/pve-docs/
