variable "pve_api" {
  description = "Proxmox API URL"
  type        = string
}

variable "pve_user" {
  description = "Proxmox API token ID"
  type        = string
}

variable "pve_pass" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault token"
  type        = string
  sensitive   = true
}
