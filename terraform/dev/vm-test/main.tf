module "test_vm" {
  source = "../../modules/proxmox-vm"

  # Minimal config for testing
  name        = "test-vm-minimal"
  description = "Minimal test VM"
  vmid        = 300
  target_node = "benedict"

  # Hardware - minimal
  cores   = 1
  sockets = 1
  memory  = 512

  # Clone from template
  clone_template = "ubuntu-24.04-cloudinit-template"
  bios           = "ovmf"
  boot_order     = "order=scsi0;net0"

  # Network - basic
  network_ip      = "192.168.50.300/24"
  network_gateway = "192.168.50.1"

  # Disk - minimal, match template
  disk_type   = "scsi"
  disk_size   = "8G"
  disk_format = "qcow2"

  # Cloud-init
  cloudinit_enabled = true
}
