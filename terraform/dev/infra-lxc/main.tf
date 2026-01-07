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

  backend "local" {
    path = "terraform.tfstate"
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

# Use the reusable LXC module
module "infra_lxc" {
  source = "../../modules/proxmox-lxc"

  vmid        = 221
  hostname    = "infra-node-dev"
  description = "Infrastructure services (Ansible, Terraform, Vault)"

  cores  = 2
  memory = 2048
  swap   = 512

  network_ip      = "192.168.50.221/24"
  network_gateway = "192.168.50.1"

  rootfs_size = "32G"

  # SSH key from Vault
  ssh_key_vault_path = "secret/ssh_keys/infra-lxc_worker"

  target_node = "benedict"
}

output "infra_lxc_ip" {
  value = module.infra_lxc.ip_address
}
