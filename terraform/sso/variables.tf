variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Vault server address"
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
  description = "SSH user for the LXC"
  type        = string
}

variable "vmid" {
  description = "Proxmox VM ID"
  type        = number
}

variable "ip_address" {
  description = "IP address for the LXC (without prefix length)"
  type        = string
}

variable "vm_hostname" {
  description = "Hostname for the LXC"
  type        = string
}

variable "target_node" {
  description = "Proxmox target node name"
  type        = string
}
