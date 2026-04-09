variable "authentik_url" {
  description = "Base URL of the Authentik instance (e.g. http://192.168.20.75:9000)"
  type        = string
}

variable "authentik_token" {
  description = "Authentik API token (bootstrap API token obtained via ak shell)"
  type        = string
  sensitive   = true
}
