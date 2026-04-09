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
