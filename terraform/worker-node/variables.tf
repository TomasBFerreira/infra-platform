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

variable "vmid" {
  description = "Proxmox VM ID"
  type        = number
}

variable "ip_address" {
  description = "IP address for the VM (without prefix length)"
  type        = string
}

variable "vm_hostname" {
  description = "Hostname for the VM"
  type        = string
}

variable "target_node" {
  description = "Proxmox target node name"
  type        = string
}

variable "template_vmid" {
  description = "VMID of the Proxmox cloud-init template VM to clone (must exist on target node)"
  type        = number
  default     = 9000
}

variable "network_bridge" {
  description = "Proxmox network bridge for the CT (e.g. vmbr10 for prod, vmbr20 for dev, vmbr30 for qa)"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the CT (e.g. 192.168.10.1 for prod, 192.168.20.1 for dev, 192.168.30.1 for qa)"
  type        = string
}
