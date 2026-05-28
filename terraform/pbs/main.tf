# Proxmox Backup Server — cluster-wide backup target.
#
# Single-slot deployment (documented exception to rule #5, alongside
# github-runner): PBS holds the only authoritative copy of the cluster
# backup chain. Flipping slots without preserving the datastore would
# lose backup history; preserving it requires brief downtime + cert
# rotation on every flip with no operational benefit. PBS lives on
# betsy because the 10 TB backup HDD is physically attached there.
#
# The bind-mount of /mnt/backup-storage → /backup-storage is intentionally
# NOT set via the telmate `mountpoint` block (provider has a long history
# of regressions around bind-mount syntax across releases). Ansible runs
# `pct set ... -mp0` against the betsy host before the in-CT install
# proceeds; see ansible/pbs/pbs_setup.yml.
#
# Privileged CT: PBS datastore code writes as uid 34 (backup user) and
# unprivileged-LXC uid remapping makes the host-side dir permissions
# fight ugly. Privileged is the standard pattern for storage-handling
# CTs in this homelab.

data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/pbs_worker"
}

resource "proxmox_lxc" "pbs" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = 2
  memory     = 2048
  swap       = 1024

  rootfs {
    storage = "local-lvm"
    size    = "8G"
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

  # Boot after vault (1) and network (2); backups aren't boot-critical.
  startup = "order=10,up=30"
}

output "pbs_ip" {
  value = var.ip_address
}

output "pbs_vmid" {
  value = var.vmid
}
