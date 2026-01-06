
module "network_vm" {
  source = "../../modules/proxmox-vm"

  # VM identification
  name        = "network-vm"
  description = "Network services VM (router, firewall, DNS)"
  vmid        = 251
  target_node = "benedict"

  # Hardware specs
  cores           = 2
  sockets         = 1
  memory          = 2048
  qemu_agent_enabled = true

  # OS/Boot configuration
  # iso               = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
  clone_template    = "9000"
  boot_order        = "order=virtio0;ide2"
  bios              = "seabios"
  scsihw            = "virtio-scsi-pci"

  # Network configuration
  network_model   = "virtio"
  network_bridge  = "vmbr0"
  network_ip      = "192.168.50.251/24"
  network_gateway = "192.168.50.1"

  # Disk configuration
  disk_type    = "virtio"
  disk_storage = "local-lvm"
  disk_size    = "25G"
  disk_format  = "qcow2"
  disk_ssd     = 1
  disk_discard = "on"

  # Cloud-init configuration
  cloudinit_enabled  = true
  cloudinit_user     = "ubuntu"
  ssh_key_vault_path = "secret/ssh_keys/network-vm_worker"
  nameserver         = "8.8.8.8"
  searchdomain       = ""

  # Boot options
  start_on_boot = true

  # VGA configuration
  vga_type   = "virtio"
  vga_memory = 16

  depends_on = []
}

# Output the VM's IP address
output "network_vm_ip" {
  value       = "192.168.50.251"
  description = "Network VM IP address"
}
