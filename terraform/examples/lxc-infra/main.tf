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

# Example: Infra LXC Container
module "infra_lxc" {
  source = "../../modules/proxmox-lxc"

  vmid     = 210
  hostname = "infra-node"

  cores  = 2
  memory = 2048
  swap   = 512

  network_ip      = "192.168.50.221/24"
  network_gateway = "192.168.50.1"

  rootfs_size = "32G"

  # Enable SSH key from Vault
  ssh_key_vault_path = "secret/ssh_keys/infra_node"

  target_node = var.target_node
}

# Example: Network LXC Container (for Traefik + Cloudflared)
module "network_lxc" {
  source = "../../modules/proxmox-lxc"

  vmid        = 220
  hostname    = "network-node"
  description = "Traefik LB and Cloudflared tunnel"

  cores  = 2
  memory = 2048
  swap   = 512

  network_ip      = "192.168.50.251/24"
  network_gateway = "192.168.50.1"

  rootfs_size = "25G"

  # Enable SSH key from Vault
  ssh_key_vault_path = "secret/ssh_keys/network_node"

  target_node = var.target_node
}

# Example: Monitoring LXC Container
module "monitoring_lxc" {
  source = "../../modules/proxmox-lxc"

  vmid        = 230
  hostname    = "monitoring-node"
  description = "Prometheus, Grafana, and monitoring stack"

  cores  = 4
  memory = 4096
  swap   = 1024

  network_ip      = "192.168.50.230/24"
  network_gateway = "192.168.50.1"

  rootfs_size = "50G"

  # Enable SSH key from Vault
  ssh_key_vault_path = "secret/ssh_keys/monitoring_node"

  target_node = var.target_node
}

# Example: Backup LXC Container
module "backup_lxc" {
  source = "../../modules/proxmox-lxc"

  vmid        = 240
  hostname    = "backup-node"
  description = "Backup and restore services"

  cores  = 2
  memory = 2048
  swap   = 512

  network_ip      = "192.168.50.240/24"
  network_gateway = "192.168.50.1"

  rootfs_size = "100G"

  # Enable SSH key from Vault
  ssh_key_vault_path = "secret/ssh_keys/backup_node"

  target_node = var.target_node
}
