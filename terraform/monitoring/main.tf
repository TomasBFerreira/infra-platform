# Fetch SSH public key from bootstrap Vault (CT 200) to provision the new CT
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/monitoring_worker"
}

resource "proxmox_lxc" "monitoring" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = var.cores
  memory     = var.memory

  rootfs {
    storage = "local-lvm"
    size    = "30G"
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = "${var.ip_address}/24"
    gw     = var.gateway
  }

  unprivileged = false

  features {
    nesting = true
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  onboot          = true
  target_node     = var.target_node

  startup = "order=3,up=30"
}

output "monitoring_ip" {
  value = var.ip_address
}
