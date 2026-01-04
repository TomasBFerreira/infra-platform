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
  pm_log_enable       = true
  pm_log_file         = "terraform-plugin-proxmox.log"
  pm_debug            = true
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}