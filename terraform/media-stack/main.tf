variable "ssh_public_key" {
  description = "The public SSH key for accessing the media worker"
  type        = string
}

resource "proxmox_lxc" "media_worker" {
  vmid          = 200
  hostname      = "media-worker"
  ostemplate    = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  cores         = 4
  memory        = 4096
  rootfs {
    storage     = "local-lvm"
    size        = "32G"
  }
  network {
    name        = "eth0"
    bridge      = "vmbr0"
    ip          = "192.168.50.200/24"
    gw          = "192.168.50.1"
  }
  unprivileged  = true
  features {
    nesting     = true
  }
  ssh_public_keys = [var.ssh_public_key]
  start         = true
  target_node   = "betsy"
}
