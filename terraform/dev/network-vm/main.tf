# Fetch SSH public key for the VM from Vault
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/network_vm_worker"
}

resource "proxmox_lxc" "network_vm" {
  vmid       = 220
  hostname   = "network-vm"
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
    ip     = "192.168.50.220/24"
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

resource "null_resource" "configure_tun" {
  depends_on = [proxmox_lxc.network_vm]

  provisioner "local-exec" {
    command = <<-EOT
      grep -q 'lxc.cgroup2.devices.allow: c 10:200 rwm' /etc/pve/lxc/220.conf \
        || echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/220.conf
      grep -q 'lxc.mount.entry: /dev/net/tun' /etc/pve/lxc/220.conf \
        || echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> /etc/pve/lxc/220.conf
      pct reboot 220
      sleep 10
    EOT
  }
}

output "network_vm_ip" {
  value = "192.168.50.220"
}
