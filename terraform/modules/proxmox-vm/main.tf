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

resource "proxmox_vm_qemu" "vm" {
  name        = var.name
  desc        = var.description
  vmid        = var.vmid
  target_node = var.target_node
  force_create = false
  
  # VM configuration
  agent       = var.qemu_agent_enabled ? 1 : 0
  cores       = var.cores
  sockets     = var.sockets
  memory      = var.memory
  
  # Boot configuration
  boot    = var.boot_order
  onboot  = var.start_on_boot
  
  # BIOS and machine type
  bios    = var.bios
  scsihw  = var.scsihw
  
  # OS configuration
  clone      = var.clone_template != "" ? var.clone_template : null
  full_clone = var.clone_template != "" ? var.full_clone : null
  iso        = var.clone_template == "" ? var.iso : null
  
  # Network configuration
  network {
    model  = var.network_model
    bridge = var.network_bridge
  }

  # Set ipconfig0 and nameserver as top-level arguments (for cloud-init IP/gateway/DNS)
  ipconfig0   = var.cloudinit_enabled ? "ip=${var.network_ip},gw=${var.network_gateway}" : null
  nameserver  = var.cloudinit_enabled && var.nameserver != "" ? var.nameserver : null
  
  # Disk configuration
  disk {
    type    = var.disk_type
    storage = var.disk_storage
    size    = var.disk_size
    format  = var.disk_format
    ssd     = var.disk_ssd
    discard = var.disk_discard
  }

  # Lifecycle: ignore disk changes to prevent provider crashes on read-back
  # This is a workaround for telmate/proxmox v2.9.14 type conversion issues
  lifecycle {
    ignore_changes = [disk]
  }

}
