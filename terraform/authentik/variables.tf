variable "authentik_url" {
  description = "Base URL of the Authentik instance (e.g. http://192.168.20.75:9000)"
  type        = string
}

variable "authentik_token" {
  description = "Authentik API token (bootstrap API token obtained via ak shell)"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Target environment (dev|qa|prod). Non-prod envs get a -dev/-qa suffix on the subdomain of each proxy provider's external host."
  type        = string
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, prod."
  }
}
