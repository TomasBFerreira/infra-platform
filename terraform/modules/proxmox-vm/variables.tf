variable "vmid" {
  description = "VM ID for the virtual machine"
  type        = number
}

variable "name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "description" {
  description = "Description of the virtual machine"
  type        = string
  default     = ""
}

variable "target_node" {
  description = "Proxmox node to deploy on"
  type        = string
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "boot_order" {
  description = "Boot order (e.g., 'order=scsi0;ide2;net0')"
  type        = string
  default     = "order=scsi0"
}

variable "start_on_boot" {
  description = "Start VM on boot"
  type        = bool
  default     = true
}

variable "bios" {
  description = "BIOS type (seabios or ovmf)"
  type        = string
  default     = "seabios"
}

variable "scsihw" {
  description = "SCSI hardware type"
  type        = string
  default     = "virtio-scsi-pci"
}

variable "qemu_agent_enabled" {
  description = "Enable QEMU guest agent"
  type        = bool
  default     = true
}

variable "clone_template" {
  description = "Template to clone from (leave empty to use ISO)"
  type        = string
  default     = ""
}

variable "full_clone" {
  description = "Use full clone instead of linked clone"
  type        = bool
  default     = true
}

variable "iso" {
  description = "ISO image to use (only if not cloning)"
  type        = string
  default     = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
}

variable "network_model" {
  description = "Network card model"
  type        = string
  default     = "virtio"
}

variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "network_ip" {
  description = "IP address with CIDR for cloud-init (e.g., '192.168.50.100/24')"
  type        = string
  default     = ""
}

variable "network_gateway" {
  description = "Network gateway for cloud-init"
  type        = string
  default     = ""
}

variable "disk_type" {
  description = "Disk type (e.g., 'scsi', 'virtio', 'ide')"
  type        = string
  default     = "scsi"
}

variable "disk_storage" {
  description = "Storage location for disk"
  type        = string
  default     = "shared-ssd-nfs"
}

variable "disk_size" {
  description = "Size of disk (e.g., '32G', '64G', '500M'). Must include unit."
  type        = string
  default     = "32G"
}

variable "disk_format" {
  description = "Disk format (e.g., 'raw', 'qcow2')"
  type        = string
  default     = "raw"
}

variable "disk_ssd" {
  description = "Enable SSD emulation"
  type        = number
  default     = 1
}

variable "disk_discard" {
  description = "Enable discard/TRIM support"
  type        = string
  default     = "on"
}

variable "cloudinit_enabled" {
  description = "Enable cloud-init configuration"
  type        = bool
  default     = true
}

variable "cloudinit_user" {
  description = "Cloud-init user"
  type        = string
  default     = "ubuntu"
}

variable "cloudinit_password" {
  description = "Cloud-init password (leave empty for SSH key only)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "nameserver" {
  description = "DNS nameservers (space-separated)"
  type        = string
  default     = "1.1.1.1 8.8.8.8"
}

variable "searchdomain" {
  description = "DNS search domain"
  type        = string
  default     = ""
}

variable "ssh_key_vault_path" {
  description = "Vault path to SSH key (e.g., 'secret/ssh_keys/vm_name'). Leave empty to skip Vault."
  type        = string
  default     = ""
}

variable "ssh_public_keys" {
  description = "SSH public keys to add (used if ssh_key_vault_path is empty)"
  type        = string
  default     = ""
}

variable "vga_type" {
  description = "VGA card type"
  type        = string
  default     = "serial0"
}

variable "vga_memory" {
  description = "VGA memory in MB"
  type        = number
  default     = 16
}
