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
  address = var.vault_address
  token   = var.vault_token
}

variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://localhost:8200"
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

# Create LXC container
resource "proxmox_lxc" "media_stack_worker" {
  vmid        = 200
  hostname    = "media-worker"
  ostemplate  = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  cores       = 4
  memory      = 4096
  
  # Explicit DNS configuration
  nameserver = "1.1.1.1 8.8.8.8"
  
  rootfs {
    storage = "local-lvm"
    size    = "32G"
  }
  
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "192.168.50.200/24"
    gw     = "192.168.50.1"
  }
  
  unprivileged = true
  
  features {
    nesting = true
  }
  
  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public"]
  start           = true
  target_node     = "betsy"

  # Provisioner to ensure SSH key is properly set up
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /root/.ssh",
      "echo '${data.vault_generic_secret.ssh_key.data["public"]}' > /root/.ssh/authorized_keys",
      "chmod 700 /root/.ssh",
      "chmod 600 /root/.ssh/authorized_keys"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = data.vault_generic_secret.ssh_key.data["private"]
      host        = "192.168.50.200"
    }
  }
}

output "media_worker_ip" {
  value = "192.168.50.200"
}
