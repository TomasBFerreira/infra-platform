variable "vault_token" {
  description = "Vault access token (bootstrap vault, CT 200)"
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Vault server address (bootstrap vault, CT 200)"
  type        = string
}

variable "pve_api" {
  description = "Proxmox API URL (prod node — betsy)"
  type        = string
}

variable "pve_user" {
  description = "Proxmox user (e.g. root@pam)"
  type        = string
  sensitive   = true
}

variable "pve_pass" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "ssh_user" {
  description = "SSH user for the CT"
  type        = string
}

variable "vmid" {
  description = "Proxmox VM ID (fixed at 103 for PBS — see infra-platform CLAUDE.md)"
  type        = number
  default     = 103
}

variable "ip_address" {
  description = "IP address for the CT (management subnet, fixed at 192.168.50.103)"
  type        = string
  default     = "192.168.50.103"
}

variable "vm_hostname" {
  description = "Hostname for the CT"
  type        = string
  default     = "pbs"
}

variable "target_node" {
  description = "Proxmox target node — must be betsy (the 10 TB backup HDD is attached there)"
  type        = string
  default     = "betsy"
}

variable "network_bridge" {
  description = "Proxmox network bridge — vmbr0 (management subnet) for cluster-wide PBS"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Default gateway — 192.168.50.1 for the management subnet"
  type        = string
  default     = "192.168.50.1"
}
