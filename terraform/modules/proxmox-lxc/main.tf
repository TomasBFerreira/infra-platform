terraform {
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

# Fetch SSH key from Vault if provided
data "vault_generic_secret" "ssh_key" {
  count = var.ssh_key_vault_path != "" ? 1 : 0
  path  = var.ssh_key_vault_path
}

resource "proxmox_lxc" "container" {
  vmid        = var.vmid
  hostname    = var.hostname
  description = var.description
  ostemplate  = var.ostemplate
  cores       = var.cores
  memory      = var.memory
  swap        = var.swap
  
  nameserver = var.nameserver
  searchdomain = var.searchdomain
  
  rootfs {
    storage = var.rootfs_storage
    size    = var.rootfs_size
  }

  network {
    name   = var.network_name
    bridge = var.network_bridge
    ip     = var.network_ip
    gw     = var.network_gateway
  }
  
  unprivileged = var.unprivileged
  
  features {
    nesting = var.feature_nesting
    keyctl  = var.feature_keyctl
    fuse    = var.feature_fuse
  }
  
  # Set SSH key if provided via Vault
  ssh_public_keys = var.ssh_key_vault_path != "" ? data.vault_generic_secret.ssh_key[0].data["public"] : var.ssh_public_keys
  
  start       = var.start_on_boot
  target_node = var.target_node
  
  onboot = var.start_on_boot
}
