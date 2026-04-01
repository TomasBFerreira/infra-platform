data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/worker_node_worker"
}

resource "proxmox_virtual_environment_vm" "worker_node" {
  name      = var.vm_hostname
  vm_id     = var.vmid
  node_name = var.target_node

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 50
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    model  = "virtio"
    bridge = var.network_bridge
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = [var.gateway]
    }
    user_account {
      username = "root"
      keys     = [trimspace(data.vault_generic_secret.ssh_key.data["public_key"])]
    }
  }

  # Match template: serial0=socket, vga=serial0
  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

  agent {
    enabled = true
    timeout = "15m"
  }

  lifecycle {
    ignore_changes = [
      network_device,
      disk,
    ]
  }
}

output "worker_node_ip" {
  value = var.ip_address
}
