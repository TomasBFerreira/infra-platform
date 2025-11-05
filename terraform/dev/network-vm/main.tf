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
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = true
}

provider "vault" {
  address = "http://192.168.50.169:8200"
  token   = var.vault_token
}

variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
  default     = "root"
}

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox user"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

# Fetch SSH key from Vault
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/media-stack_worker"
}

resource "proxmox_lxc" "network_vm" {
  vmid        = 220
  hostname    = "network-vm"
  ostemplate  = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  cores       = 2
  memory      = 2048
  
  rootfs {
    storage = "local-lvm"
    size    = "25G"
  }
  
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "192.168.50.220/24"
    gw     = "192.168.50.1"
  }
  
  unprivileged = true
  
  features {
    nesting = true
  }
  
  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public"]
  start           = true
  target_node     = "betsy"
}

output "network_vm_ip" {
  value = "192.168.50.220"
}
