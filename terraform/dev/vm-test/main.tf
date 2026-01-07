module "test_vm" {
  source = "../../modules/proxmox-vm"

  # Minimal config for testing
  name        = "test-vm-minimal"
  description = "Minimal test VM"
  vmid        = 300
  target_node = "benedict"

  # Hardware - minimal
  cores  = 1
  memory = 512

  # Clone from template
  clone_template = "ubuntu-24.04-cloudinit-template"
  bios           = "ovmf"

  # Network - basic
  network_ip      = "192.168.50.300/24"
  network_gateway = "192.168.50.1"

  # Disk - minimal
  disk_size = "8G"

  # Cloud-init
  cloudinit_enabled = true
}
