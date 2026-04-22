# Look up the existing tomas user by username to get their internal PK.
data "authentik_user" "tomas" {
  username = "tomas"
}

# Create the media-admin group and bind tomas as a member.
# Authentik forwards group names in the X-authentik-groups header (pipe-separated),
# so the name here must match exactly what Traefik forwardAuth consumes.
resource "authentik_group" "media_admin" {
  name  = "media-admin"
  users = [data.authentik_user.tomas.id]
}

# Ops Portal role groups. Mapped to portal roles by go-lib/authz:
#   ops-admins    -> admin
#   ops-operators -> operator
#   ops-viewers   -> viewer
# Admin satisfies operator and viewer (Role.AtLeast), so tomas is bound
# to ops-admins only; ops-operators/ops-viewers start empty and are
# populated per user as the portal's user base grows.
resource "authentik_group" "ops_admins" {
  name  = "ops-admins"
  users = [data.authentik_user.tomas.id]
}

resource "authentik_group" "ops_operators" {
  name = "ops-operators"
}

resource "authentik_group" "ops_viewers" {
  name = "ops-viewers"
}
