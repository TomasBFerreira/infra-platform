terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
  
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = true
}

provider "vault" {
  address = "http://192.168.50.169:8200"
  token   = var.vault_token
}

variable "vault_token" {
  description = "Vault access token"
  type        = string
  sensitive   = true
  default     = "root"
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

# Fetch SSH key from Vault
data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/media-stack_worker"
}
