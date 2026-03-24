data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/rancher_worker"
}

resource "proxmox_lxc" "rancher" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = 2
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

  # K3s requires a privileged LXC — unprivileged containers cannot manage
  # cgroups or bind iptables rules, preventing the K3s API server from starting.
  unprivileged = false

  features {
    nesting = true
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  onboot          = true
  target_node     = var.target_node

  startup = "order=6,up=60"
}

output "rancher_ip" {
  value = var.ip_address
}
