data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/sso_worker"
}

resource "proxmox_lxc" "sso" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = 4
  memory     = 4096

  rootfs {
    storage = "local-lvm"
    size    = "20G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "${var.ip_address}/24"
    gw     = "192.168.50.1"
  }

  unprivileged = false

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  target_node     = var.target_node
}

output "sso_ip" {
  value = var.ip_address
}
