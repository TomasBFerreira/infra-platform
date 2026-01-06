variable "vmid" {
  description = "VM ID for the LXC container"
  type        = number
}

variable "hostname" {
  description = "Hostname for the LXC container"
  type        = string
}

variable "description" {
  description = "Description of the LXC container"
  type        = string
  default     = ""
}

variable "ostemplate" {
  description = "OS template for the LXC container"
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "swap" {
  description = "Swap in MB"
  type        = number
  default     = 512
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

variable "rootfs_storage" {
  description = "Storage location for rootfs"
  type        = string
  default     = "local-lvm"
}

variable "rootfs_size" {
  description = "Size of rootfs (e.g., '32G')"
  type        = string
  default     = "32G"
}

variable "network_name" {
  description = "Network interface name"
  type        = string
  default     = "eth0"
}

variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "network_ip" {
  description = "IP address with CIDR (e.g., '192.168.50.200/24')"
  type        = string
}

variable "network_gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.50.1"
}

variable "unprivileged" {
  description = "Run as unprivileged container"
  type        = bool
  default     = true
}

variable "feature_nesting" {
  description = "Enable nesting feature (for Docker)"
  type        = bool
  default     = true
}

variable "feature_keyctl" {
  description = "Enable keyctl feature"
  type        = bool
  default     = false
}

variable "feature_fuse" {
  description = "Enable fuse feature"
  type        = bool
  default     = false
}

variable "ssh_key_vault_path" {
  description = "Vault path to SSH key (e.g., 'secret/ssh_keys/container_name'). Leave empty to skip Vault."
  type        = string
  default     = ""
}

variable "ssh_public_keys" {
  description = "SSH public keys to add (used if ssh_key_vault_path is empty)"
  type        = string
  default     = ""
}

variable "start_on_boot" {
  description = "Start container on boot"
  type        = bool
  default     = true
}

variable "target_node" {
  description = "Proxmox node to deploy on"
  type        = string
}
