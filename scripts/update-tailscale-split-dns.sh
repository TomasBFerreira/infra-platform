#!/usr/bin/env bash
# Query the Tailscale API for all currently-active AdGuard-bearing devices,
# collect their Tailscale IPv4 addresses, and PATCH them as the split-DNS
# nameservers for databaes.net so Tailscale clients resolve *.databaes.net
# via AdGuard on those hosts.
#
# Filter is by hostname pattern, not by Tailscale tag, because the auth
# keys for this tailnet default-apply tag:subnet-router to every joined
# device — including traefik-lxc instances that don't run DNS at all.
# Filtering on tag would include those and degrade resolution UX.
#
# Required env:
#   TAILSCALE_API_KEY  - API key with DNS write scope
#   TAILSCALE_TAILNET  - e.g. taild7df92.ts.net
set -euo pipefail

: "${TAILSCALE_API_KEY:?TAILSCALE_API_KEY is required}"
: "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET is required}"

API="https://api.tailscale.com/api/v2/tailnet/${TAILSCALE_TAILNET}"
AUTH="Authorization: Bearer ${TAILSCALE_API_KEY}"

# Fetch all authorized devices, then keep only those whose hostname matches
# the AdGuard-bearing patterns (network-vm during the parallel-run, plus
# adguard-lxc going forward). Drop the network-vm half once Phase 3c of the
# network-vm split lands (issues/network-vm-split-2026-05-19.md) — then
# only adguard-lxc remains.
curl -sS -f -H "$AUTH" "${API}/devices" > /tmp/ts_devices.json

ips_json=$(python3 <<'PY'
import json, re
with open("/tmp/ts_devices.json") as f:
    data = json.load(f)
# Match e.g. "dev-network-vm-blue", "prod-adguard-lxc-green".
ADGUARD_HOST = re.compile(r"^(dev|qa|prod)-(network-vm|adguard-lxc)-(blue|green)$")
ips = []
for d in data.get("devices", []):
    if d.get("authorized") is False:
        continue
    host = (d.get("hostname") or "").lower()
    if not ADGUARD_HOST.match(host):
        continue
    for a in d.get("addresses", []):
        if ":" in a:
            continue
        ips.append(a)
        break
print(json.dumps(sorted(set(ips))))
PY
)

echo "Active AdGuard-bearing Tailscale IPs: $ips_json"

if [[ "$ips_json" == "[]" ]]; then
  echo "No active AdGuard-bearing devices found — refusing to wipe split-DNS" >&2
  exit 1
fi

# PATCH upserts the domains specified without touching others; POST replaces all.
payload=$(printf '{"databaes.net": %s}' "$ips_json")
echo "PATCHing: $payload"

curl -sS -f -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d "$payload" \
  "${API}/dns/split-dns"

echo
echo "Tailscale split-DNS for databaes.net now points to: $ips_json"
