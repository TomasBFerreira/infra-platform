resource "proxmox_lxc" "zigbee_iot" {
  vmid       = var.vmid
  hostname   = var.vm_hostname
  ostemplate = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  cores      = 1
  memory     = 512

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

  # Privileged: the Zigbee USB dongle (/dev/ttyUSB0) is passed through from the
  # host, and an unprivileged CT maps the device to an inaccessible uid
  # (nobody:nogroup) so Zigbee2MQTT can't open the serial port. Privileged =
  # container root == host root, so the passed-through device just works.
  unprivileged = false

  features {
    nesting = true
  }

  ssh_public_keys = data.vault_generic_secret.ssh_key.data["public_key"]
  start           = true
  onboot          = true
  target_node     = var.target_node

  startup = "order=4,up=30"
}

output "zigbee_iot_ip" {
  value = var.ip_address
}
