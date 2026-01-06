terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.10"
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

  # Set ipconfig0 as a top-level argument (for cloud-init IP/gateway)
  ipconfig0 = var.cloudinit_enabled ? "ip=${var.network_ip},gw=${var.network_gateway}" : null
  
  # Disk configuration
  disk {
    type    = var.disk_type
    storage = var.disk_storage
    size    = var.disk_size
    format  = var.disk_format
    ssd     = var.disk_ssd
    discard = var.disk_discard
  }
  
  # Cloud-init configuration (if enabled)
  # ipconfig0 and nameserver are now set in the network block above
  
  # SSH keys via cloud-init or Vault
  sshkeys = var.cloudinit_enabled ? (
    var.ssh_key_vault_path != "" ? data.vault_generic_secret.ssh_key[0].data["public"] : var.ssh_public_keys
  ) : ""
  
  ciuser     = var.cloudinit_enabled ? var.cloudinit_user : null
  cipassword = var.cloudinit_enabled && var.cloudinit_password != "" ? var.cloudinit_password : null
  
  # Additional cloud-init options
  searchdomain = var.cloudinit_enabled ? var.searchdomain : null
  
  # Serial console
  serial {
    id   = 0
    type = "socket"
  }
  
  # VGA configuration
  vga {
    type   = var.vga_type
    memory = var.vga_memory
  }
  
  # Lifecycle management
  # Ignore all changes after creation to work around provider v2.9.14 read-back crash
  lifecycle {
    ignore_changes = all
  }
}
