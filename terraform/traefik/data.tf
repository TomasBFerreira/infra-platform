data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/traefik_worker"
}
