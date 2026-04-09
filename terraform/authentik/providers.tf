terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.10"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
