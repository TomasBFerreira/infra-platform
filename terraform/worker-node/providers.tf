terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

locals {
  # bpg/proxmox expects the Proxmox base URL, not the /api2/json path
  pve_endpoint = replace(var.pve_api, "/api2/json", "")
}

provider "proxmox" {
  endpoint  = local.pve_endpoint
  username  = var.pve_user
  password  = var.pve_pass
  insecure  = true
}

provider "vault" {
  address          = var.vault_address
  token            = var.vault_token
  skip_child_token = true
}
