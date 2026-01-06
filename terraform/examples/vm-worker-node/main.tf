terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_user
  pm_api_token_secret = var.proxmox_password
  pm_tls_insecure     = true
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

# Example: Worker Node VM for Docker containers
module "worker_vm" {
  source = "../../modules/proxmox-vm"
  
  vmid = 111
  name = "worker-node-01"
  description = "Docker worker node for container workloads"
  
  cores   = 4
  sockets = 1
  memory  = 8192
  
  # Use Ubuntu 24.04 ISO
  iso = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
  
  # Disk configuration
  disk_storage = "local-lvm"
  disk_size    = "100G"
  disk_format  = "raw"
  disk_ssd     = 1
  disk_discard = "on"
  
  # Network configuration (for cloud-init or manual setup)
  network_bridge = "vmbr0"
  network_model  = "virtio"
  
  # Cloud-init configuration (if you create a cloud-init template)
  # cloudinit_enabled = true
  # cloudinit_user    = "ubuntu"
  # network_ip        = "192.168.50.111/24"
  # network_gateway   = "192.168.50.1"
  # ssh_key_vault_path = "secret/ssh_keys/worker_node_01"
  
  # For now, cloud-init disabled for manual installation
  cloudinit_enabled = false
  
  start_on_boot = true
  target_node   = var.target_node
}

# Example: Additional Worker Node VM
module "worker_vm_02" {
  source = "../../modules/proxmox-vm"
  
  vmid = 112
  name = "worker-node-02"
  description = "Docker worker node for container workloads"
  
  cores   = 4
  sockets = 1
  memory  = 8192
  
  iso = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
  
  disk_storage = "local-lvm"
  disk_size    = "100G"
  
  network_bridge = "vmbr0"
  
  cloudinit_enabled = false
  
  start_on_boot = true
  target_node   = var.target_node
}
