resource "proxmox_virtual_environment_container" "vault" {
  node_name = var.target_node
  vm_id     = var.lxc_id
  description = "Vault LXC Container"

  clone {
    vm_id = var.lxc_template
  }

  initialization {
    hostname = "vault"
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    size         = 8
  }

  network_interface {
    name = "eth0"
  }

  started = true

  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}
