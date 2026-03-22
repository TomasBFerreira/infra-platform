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

  # Privileged LXC: Docker requires CAP_NET_ADMIN to set network namespace
  # sysctls (net.ipv4.ip_unprivileged_port_start) introduced in Docker 26+.
  # lxc.sysctl.net.* is not supported on PVE 7.x so we use a privileged
  # container instead. Acceptable for a CI runner (trusted code only).
  unprivileged = false

  features {
    nesting = true
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
