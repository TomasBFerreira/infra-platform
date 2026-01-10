resource "proxmox_lxc" "vault" {
  name        = "vault"
  ostemplate  = var.lxc_template
  target_node = var.target_node
  vmid        = var.lxc_id
  cores       = 2
  memory      = 2048
  disk {
    size = "8G"
    storage = "local-lvm"
  }
  network {
    name = "eth0"
    bridge = "vmbr0"
    ip = var.lxc_ip
    gw = var.lxc_gw
  }
  features {
    nesting = true
  }
  ssh_public_keys = var.ssh_public_keys
  start = true
}
