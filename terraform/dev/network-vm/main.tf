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
    interpreter = ["/bin/bash", "-c"]
    environment = {
      PVE_API  = var.pve_api
      PVE_USER = var.pve_user
      PVE_PASS = var.pve_pass
    }
    command = <<-EOT
      set -e
      apt-get install -y -q curl jq 2>/dev/null || true
      RESPONSE=$(curl -sf -k \
        --data-urlencode "username=$PVE_USER" \
        --data-urlencode "password=$PVE_PASS" \
        "$PVE_API/access/ticket")
      TICKET=$(echo "$RESPONSE" | jq -r '.data.ticket')
      CSRF=$(echo "$RESPONSE"   | jq -r '.data.CSRFPreventionToken')

      curl -sf -k -X PUT "$PVE_API/nodes/benedict/lxc/220/config" \
        -H "CSRFPreventionToken: $CSRF" \
        -b "PVEAuthCookie=$TICKET" \
        --data-urlencode "lxc[0]=lxc.cgroup2.devices.allow: c 10:200 rwm" \
        --data-urlencode "lxc[1]=lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"

      curl -sf -k -X POST "$PVE_API/nodes/benedict/lxc/220/status/reboot" \
        -H "CSRFPreventionToken: $CSRF" \
        -b "PVEAuthCookie=$TICKET"

      sleep 15
    EOT
  }
}

output "network_vm_ip" {
  value = "192.168.50.220"
}
