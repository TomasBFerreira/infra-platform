variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
<<<<<<< HEAD
  default     = "root"
=======
>>>>>>> dev
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
<<<<<<< HEAD
  default     = "http://192.168.50.169:8200"
}

variable "proxmox_api_url" {
=======
}

variable "pve_api" {
>>>>>>> dev
  description = "Proxmox API URL"
  type        = string
}

<<<<<<< HEAD
variable "proxmox_user" {
  description = "Proxmox user"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
=======
variable "pve_user" {
  description = "Proxmox user"
  type        = string
  sensitive   = true
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
>>>>>>> dev
}