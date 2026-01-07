terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "proxmox" {
  pm_api_url          = var.pve_api
  pm_api_token_id     = var.pve_user
  pm_api_token_secret = var.pve_pass
  pm_tls_insecure     = true
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}
