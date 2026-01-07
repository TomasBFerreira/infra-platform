module "test_vm" {
  source = "../../modules/proxmox-vm"

  name        = "test-vm"
  description = "Test VM for workflow validation"
  vmid        = 300
  target_node = "benedict"

  cores           = 1
  sockets         = 1
  memory          = 1024
  qemu_agent_enabled = true

  clone_template    = "ubuntu-24.04-cloudinit-template"
  boot_order        = "order=virtio0;ide2"
  bios              = "seabios"
  scsihw            = "virtio-scsi-pci"

  network_model   = "virtio"
  network_bridge  = "vmbr0"
  network_ip      = "192.168.50.300/24"
  network_gateway = "192.168.50.1"

  disk_type    = "virtio"
  disk_storage = "shared-ssd-nfs"
  disk_size    = "8G"
  disk_format  = "qcow2"
  disk_ssd     = 1
  disk_discard = "on"

  cloudinit_enabled  = true
  cloudinit_user     = "ubuntu"
}
