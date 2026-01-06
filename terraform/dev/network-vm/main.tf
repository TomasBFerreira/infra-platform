
# Fetch SSH public key for the VM from Vault
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/network-vm_worker"
}

resource "proxmox_lxc" "network_vm" {
  vmid        = 251
  hostname    = "network-vm"
  ostemplate  = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores       = 2
  memory      = 2048

  rootfs {
    storage = "local-lvm"
    size    = "25G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "192.168.50.220/24"
    gw     = "192.168.50.1"
  }

  unprivileged = true

  features {
    nesting = true
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public"]
  start           = true
  target_node     = "benedict"
}

# Output the VM's IP address
output "network_vm_ip" {
  value = "192.168.50.220"
}
