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

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}
