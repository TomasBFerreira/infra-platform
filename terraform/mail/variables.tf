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

# --- Single-slot placement -------------------------------------------------
# Defaults target the DEV mail CT. The eventual cluster-wide production mail
# singleton overrides these (e.g. vmid=104, ip=192.168.50.104, target_node=betsy,
# network_bridge=vmbr0, gateway=192.168.50.1) — same pattern as PBS. See the
# header in main.tf and the assignment table in infra-platform/CLAUDE.md.

variable "vmid" {
  description = "Proxmox VM ID (dev mail = 204; see infra-platform CLAUDE.md)"
  type        = number
  default     = 204
}

variable "ip_address" {
  description = "IP address for the CT, without prefix length (dev mail = 192.168.20.4)"
  type        = string
  default     = "192.168.20.4"
}

variable "vm_hostname" {
  description = "Hostname for the CT"
  type        = string
  default     = "mail-dev"
}

variable "target_node" {
  description = "Proxmox target node (dev = benedict)"
  type        = string
  default     = "benedict"
}

variable "network_bridge" {
  description = "Proxmox network bridge (dev = vmbr20)"
  type        = string
  default     = "vmbr20"
}

variable "gateway" {
  description = "Default gateway (dev = 192.168.20.1)"
  type        = string
  default     = "192.168.20.1"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MiB (Stalwart is light; headroom for docker + Rspamd-style filtering)"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Root filesystem size (mail data, queue, DKIM keys, docker images)"
  type        = string
  default     = "20G"
}
