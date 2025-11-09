variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
  default     = "root"
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://192.168.50.169:8200"
}

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox user"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}