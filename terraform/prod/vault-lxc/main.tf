resource "proxmox_virtual_environment_lxc_container" "vault" {
  node_name = var.target_node
  vm_id     = var.lxc_id
  hostname  = "vault"

  initialization {
    hostname = "vault"
  }

  clone {
    vm_id = var.lxc_template
  }

  cores    = 2
  memory   = 2048

  disk {
    datastore_id = "local-lvm"
    size         = 8
  }

  network_device {
    name   = "eth0"
    bridge = "vmbr0"  
  }

  started = true
}
