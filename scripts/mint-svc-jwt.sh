#!/bin/bash
#
# Mints a short-lived HS256 service-JWT for calling an ops-portal-*
# /svc/** endpoint from a GitHub Actions bash step — no Go toolchain
# needed, just openssl (present on every runner image used here).
#
# Mirrors ops-portal-go-lib/svcjwt's token shape exactly: HS256, claims
# {iss, aud, iat, exp}, header X-Service-Token. The signing secret must be
# the SAME value the target service's TRUSTED_SERVICE_KEYS trusts for that
# issuer — see the calling workflow's comments for which Vault path holds
# it (convention: secret/ops-portal/$ENV/svc-jwt/<callee>-callers, a JSON
# map of {issuer: secret} shared between the callee's TRUSTED_SERVICE_KEYS
# and every caller minting a token for that issuer name).
#
# Usage:
#   source scripts/mint-svc-jwt.sh
#   TOKEN=$(mint_svc_jwt "renovate-orchestrator" "updates" "$SECRET" [ttl_seconds])
#
# Prints the token to stdout. Default TTL is 300s, matching svcjwt.DefaultTTL.

mint_svc_jwt() {
  local iss="$1" aud="$2" secret="$3" ttl="${4:-300}"
  if [ -z "$iss" ] || [ -z "$aud" ] || [ -z "$secret" ]; then
    echo "mint_svc_jwt: usage: mint_svc_jwt <issuer> <audience> <secret> [ttl_seconds]" >&2
    return 1
  fi

  local now exp header payload b64header b64payload signing_input signature
  now=$(date -u +%s)
  exp=$((now + ttl))
  header='{"alg":"HS256","typ":"JWT"}'
  payload=$(printf '{"iss":"%s","aud":"%s","iat":%d,"exp":%d}' "$iss" "$aud" "$now" "$exp")

  b64header=$(printf '%s' "$header" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  b64payload=$(printf '%s' "$payload" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  signing_input="${b64header}.${b64payload}"
  signature=$(printf '%s' "$signing_input" | openssl dgst -sha256 -hmac "$secret" -binary | base64 -w0 | tr '+/' '-_' | tr -d '=')

  printf '%s.%s' "$signing_input" "$signature"
}
