# Stalwart mail server — self-hosted SMTP/IMAP/JMAP for databaes.net.
#
# Single-slot deployment (documented exception to rule #5, alongside
# github-runner and pbs): a mail server is stateful — it holds mailboxes,
# the outbound queue, and the DKIM signing keys. Blue/green flipping would
# either lose queued/stored mail on each flip or require copying the maildir
# + key material with downtime on every change, for no operational benefit
# (one mail system serves the whole domain, not per-env).
#
# Outbound deliverability: this homelab is on a residential IP behind
# Cloudflare tunnels (which don't carry SMTP), and residential ranges are on
# Spamhaus PBL with port 25 blocked. Stalwart therefore relays outbound mail
# through a smarthost (Brevo) configured in ansible/mail/. Stalwart still owns
# the mailboxes and signs DKIM; only the final delivery hop is relayed.
#
# No public Traefik route (rule #6): SMTP/IMAP are not HTTP and can't sit
# behind Authentik forwardAuth. The CT is reached internally by Authentik on
# the submission port and reaches the outside world only via the relay. The
# Stalwart web admin UI is bound to the internal/Tailscale interface only.
#
# Dev validates the full pattern + account-recovery flow. The production
# cluster-wide mail singleton reuses this module with prod placement vars.

data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/mail_worker"
}

resource "proxmox_lxc" "mail" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = var.cores
  memory     = var.memory
  swap       = 512

  rootfs {
    storage = "local-lvm"
    size    = var.disk_size
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = "${var.ip_address}/24"
    gw     = var.gateway
  }

  # Unprivileged is fine — Stalwart runs in a container and handles no host
  # storage devices (unlike PBS). Nesting is required to run docker inside.
  unprivileged = true

  features {
    nesting = true
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  onboot          = true
  target_node     = var.target_node

  # Boot after vault (1) and network (2); mail isn't boot-critical.
  startup = "order=10,up=30"
}

output "mail_ip" {
  value = var.ip_address
}

output "mail_vmid" {
  value = var.vmid
}
