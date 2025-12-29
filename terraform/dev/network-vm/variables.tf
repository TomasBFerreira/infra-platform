variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
  default     = "myroot"
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://localhost:8200"
}

variable "pve_api" {
  description = "Proxmox API URL"
  type        = string
}

variable "pve_user" {
  description = "Proxmox user"
  type        = string
}

variable "pve_pass" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "ssh_user" {
  description = "SSH user for the VM"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the VM"
  type        = string
  default     = ""
}