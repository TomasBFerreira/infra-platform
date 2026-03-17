# Fetch SSH public key for the VM from Vault
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/network_vm_worker"
}

resource "proxmox_lxc" "network_vm" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = 2
  memory     = 2048

  rootfs {
    storage = "local-lvm"
    size    = "25G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "${var.ip_address}/24"
    gw     = "192.168.50.1"
  }

  unprivileged = true

  features {
    nesting = true
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  target_node     = var.target_node
}


output "network_vm_ip" {
  value = var.ip_address
}
