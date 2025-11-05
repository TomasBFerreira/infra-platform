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

resource "proxmox_vm_qemu" "network_vm" {
  name         = "network-vm"
  target_node  = "betsy"
  vmid         = 220           
  memory       = 4096          
  cores        = 4

  iso          = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"

  disk {
    type   = "scsi"
    storage = "local-lvm"
    size    = "32G"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Static IP via cloud-init customization:
  ipconfig0 = "ip=192.168.50.200/24,gw=192.168.50.1"

  # SSH public key injection (with cloud-init template):
  sshkeys = data.vault_generic_secret.ssh_key.data["public"]

  # Boot on creation
  boot        = "c"
  onboot      = true
  start       = true

  # Optional: Additional features
  agent       = 1
}

output "network_vm_ip" {
  value = "192.168.50.220"
}

