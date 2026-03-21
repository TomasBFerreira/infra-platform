data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/worker_node_worker"
}

resource "proxmox_vm_qemu" "worker_node" {
  name        = var.vm_hostname
  vmid        = var.vmid
  target_node = var.target_node

  # Clone from a cloud-init template VM (see runbooks.md — "Create cloud-init template")
  clone      = var.template_name
  full_clone = true

  cores   = 4
  sockets = 1
  memory  = 8192

  # SCSI controller required for iothread
  scsihw = "virtio-scsi-pci"

  disk {
    slot     = "scsi0"
    type     = "scsi"
    storage  = "local-lvm"
    size     = "50G"
    iothread = 1
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-init configuration
  os_type    = "cloud-init"
  ipconfig0  = "ip=${var.ip_address}/24,gw=192.168.50.1"
  nameserver = "192.168.50.1"
  ciuser     = "root"
  sshkeys    = data.vault_generic_secret.ssh_key.data["public_key"]

  # Required for console access and guest agent
  serial {
    id   = 0
    type = "socket"
  }

  agent = 1

  lifecycle {
    ignore_changes = [
      # Prevents drift on network MAC addr and disk after initial clone
      network,
      disk,
    ]
  }
}

output "worker_node_ip" {
  value = var.ip_address
}
