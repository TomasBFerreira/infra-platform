terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
<<<<<<< HEAD
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
=======
>>>>>>> dev
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "proxmox" {
<<<<<<< HEAD
  pm_api_url          = var.proxmox_api_url
  pm_user             = var.proxmox_user
  pm_password         = var.proxmox_password
=======
  pm_api_url          = var.pve_api
  pm_api_token_id     = var.pve_user
  pm_api_token_secret = var.pve_pass
>>>>>>> dev
  pm_tls_insecure     = true
  pm_log_enable       = true
  pm_log_file         = "terraform-plugin-proxmox.log"
  pm_debug            = true
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}