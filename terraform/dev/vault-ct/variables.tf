variable "vault_token" {
  description = "Vault access token (dev vault on CT 200)"
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Vault server address (dev vault on CT 200)"
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
