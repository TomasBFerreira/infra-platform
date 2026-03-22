# Fetch SSH public key from bootstrap Vault (CT 200) to provision the new CT
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/github_runner_worker"
}

resource "proxmox_lxc" "github_runner" {
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
    bridge = "vmbr0"
    ip     = "${var.ip_address}/24"
    gw     = "192.168.50.1"
  }

  unprivileged = true

  features {
    nesting = true
    keyctl  = true  # required for Docker in unprivileged LXC
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  onboot          = true
  target_node     = var.target_node

  # Boot after vault (1), network (2), and sso (3) — runners depend on all three
  startup = "order=5,up=30"
}

output "github_runner_ip" {
  value = var.ip_address
}
