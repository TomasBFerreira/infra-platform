# Fetch SSH public key from bootstrap Vault (CT 200) to provision the new CT
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/vault_ct_worker"
}

resource "proxmox_lxc" "vault_ct" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = 1
  memory     = 512

  rootfs {
    storage = "local-lvm"
    size    = "8G"
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
  target_node     = "benedict"
}

output "vault_ct_ip" {
  value = var.ip_address
}
