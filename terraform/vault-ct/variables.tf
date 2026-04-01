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
  description = "Proxmox API URL"
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
  description = "Proxmox VM ID"
  type        = number
}

variable "ip_address" {
  description = "IP address for the CT (without prefix length)"
  type        = string
}

variable "vm_hostname" {
  description = "Hostname for the CT"
  type        = string
}

variable "target_node" {
  description = "Proxmox target node name"
  type        = string
}

variable "network_bridge" {
  description = "Proxmox network bridge for the CT (e.g. vmbr10 for prod, vmbr20 for dev, vmbr30 for qa)"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the CT (e.g. 192.168.10.1 for prod, 192.168.20.1 for dev, 192.168.30.1 for qa)"
  type        = string
}
