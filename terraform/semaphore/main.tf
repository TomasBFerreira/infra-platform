# Fetch SSH public key from bootstrap Vault (CT 200) to provision the new CT
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/semaphore_worker"
}

resource "proxmox_lxc" "semaphore" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = 2
  memory     = 2048

  rootfs {
    storage = "local-lvm"
    size    = "20G"
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = "${var.ip_address}/24"
    gw     = var.gateway
  }

  unprivileged = true

  features {
    nesting = true
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  onboot          = true
  target_node     = var.target_node

  startup = "order=7,up=30"
}

output "semaphore_ip" {
  value = var.ip_address
}
