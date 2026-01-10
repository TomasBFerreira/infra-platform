variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "Proxmox node/host where LXC will be created"
  type        = string
}

variable "lxc_template" {
  description = "LXC template VM ID to clone from"
  type        = number
}

variable "lxc_id" {
  description = "LXC VM ID"
  type        = number
}

variable "lxc_ip" {
  description = "LXC IP address with CIDR"
  type        = string
}

variable "lxc_gw" {
  description = "Gateway IP for LXC"
  type        = string
}

variable "ssh_public_keys" {
  description = "SSH public keys for LXC"
  type        = string
}
