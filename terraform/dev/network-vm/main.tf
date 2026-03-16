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
    interpreter = ["python3", "-c"]
    environment = {
      PVE_API  = var.pve_api
      PVE_USER = var.pve_user
      PVE_PASS = var.pve_pass
    }
    command = <<-PYEOF
      import urllib.request, urllib.parse, json, ssl, os, time
      ctx = ssl.create_default_context()
      ctx.check_hostname = False
      ctx.verify_mode = ssl.CERT_NONE
      api  = os.environ['PVE_API']
      user = os.environ['PVE_USER']
      pw   = os.environ['PVE_PASS']

      auth_data = urllib.parse.urlencode({'username': user, 'password': pw}).encode()
      with urllib.request.urlopen(urllib.request.Request(f'{api}/access/ticket', data=auth_data), context=ctx) as r:
        resp = json.loads(r.read())
      ticket = resp['data']['ticket']
      csrf   = resp['data']['CSRFPreventionToken']
      headers = {'CSRFPreventionToken': csrf, 'Cookie': f'PVEAuthCookie={ticket}', 'Content-Type': 'application/x-www-form-urlencoded'}

      cfg = urllib.parse.urlencode({'lxc[0]': 'lxc.cgroup2.devices.allow: c 10:200 rwm', 'lxc[1]': 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file'}).encode()
      req = urllib.request.Request(f'{api}/nodes/benedict/lxc/220/config', data=cfg, method='PUT', headers=headers)
      with urllib.request.urlopen(req, context=ctx): pass

      req = urllib.request.Request(f'{api}/nodes/benedict/lxc/220/status/reboot', data=b'', method='POST', headers=headers)
      with urllib.request.urlopen(req, context=ctx): pass

      time.sleep(15)
    PYEOF
  }
}

output "network_vm_ip" {
  value = "192.168.50.220"
}
