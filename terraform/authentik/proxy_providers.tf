# Proxy providers + applications for services gated behind Traefik forwardAuth.
#
# Before this file landed, these providers existed only as UI-created state in
# each env's Authentik Postgres. The 2026-04-13 blue/green flip of sso-prod
# wiped them (the pipeline's backup/restore only preserves what was in the
# previous dump, which had already been clipped by an earlier flip). All
# 8 services below then 404'd on forwardAuth for 9 days — the embedded
# outpost returns "404 page not found" when no proxy provider matches the
# incoming Host header, and Traefik forwards that 404 unchanged to the user.
# Encoding the providers in Terraform makes them durable across flips.
#
# Naming convention:
#   - authentik_provider_proxy.forward[<key>]   — proxy provider (forward_single)
#   - authentik_application.proxy[<key>]        — application wrapper (required
#                                                  to bind groups/policies)
#   - Object name on both: "<display> (<env>)"  — used by the workflow to
#                                                  discover which providers to
#                                                  attach to the embedded outpost
#   - External host on prod: <key>.databaes.net
#                  on dev:  <key>-dev.databaes.net  (same pattern for qa)

locals {
  host_suffix = var.environment == "prod" ? "" : "-${var.environment}"

  # Keys double as Terraform resource instance names AND as the hostname
  # subdomain under databaes.net. Values are human-readable display names.
  proxy_services = {
    tomajflix   = "Tomaj Flix"
    prowlarr    = "Prowlarr"
    radarr      = "Radarr"
    sonarr      = "Sonarr"
    seerr       = "Seerr"
    semaphore   = "Semaphore"
    stremiotest = "Stremio Test"
    jacketttest = "Jackett Test"
  }
}

# Authentik ships with these two flows by default; same as what the admin UI
# pre-selects when you create a proxy provider through the form. Looking them
# up via data sources keeps us decoupled from their per-env PK values.
data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

resource "authentik_provider_proxy" "forward" {
  for_each = local.proxy_services

  name               = "${each.value} (${var.environment})"
  mode               = "forward_single"
  external_host      = "https://${each.key}${local.host_suffix}.databaes.net"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
}

resource "authentik_application" "proxy" {
  for_each = local.proxy_services

  name              = "${each.value} (${var.environment})"
  slug              = "${each.key}-${var.environment}"
  protocol_provider = authentik_provider_proxy.forward[each.key].id
  meta_launch_url   = "https://${each.key}${local.host_suffix}.databaes.net/"
}
