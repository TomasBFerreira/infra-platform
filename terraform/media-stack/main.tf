provider "vault" {
  address = "http://192.168.50.169:8200"
  token   = var.vault_token
}

variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
}

data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/media-stack_worker"
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
  ssh_public_keys = [data.vault_generic_secret.ssh_key.data["public"]]
  start         = true
  target_node   = "betsy"
}
