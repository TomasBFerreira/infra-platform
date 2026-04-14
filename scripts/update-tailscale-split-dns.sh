#!/usr/bin/env bash
# Query the Tailscale API for all currently-active subnet-router devices,
# collect their Tailscale IPv4 addresses, and POST them as the split-DNS
# nameservers for databaes.net so Tailscale clients resolve *.databaes.net
# via AdGuard on those network-vms.
#
# Required env:
#   TAILSCALE_API_KEY  - API key with DNS write scope
#   TAILSCALE_TAILNET  - e.g. taild7df92.ts.net
set -euo pipefail

: "${TAILSCALE_API_KEY:?TAILSCALE_API_KEY is required}"
: "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET is required}"

API="https://api.tailscale.com/api/v2/tailnet/${TAILSCALE_TAILNET}"
AUTH="Authorization: Bearer ${TAILSCALE_API_KEY}"

# Fetch devices tagged tag:subnet-router that are authorized.
# Take the first IPv4 address of each (Tailscale IP, 100.x.x.x).
devices_json=$(curl -sS -f -H "$AUTH" "${API}/devices")

ips_json=$(printf '%s' "$devices_json" | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
ips = []
for d in data.get("devices", []):
    tags = d.get("tags") or []
    if "tag:subnet-router" not in tags:
        continue
    if d.get("authorized") is False:
        continue
    for a in d.get("addresses", []):
        # Skip IPv6 — split-DNS nameservers are IPv4
        if ":" in a:
            continue
        ips.append(a)
        break
ips = sorted(set(ips))
print(json.dumps(ips))
PY
)

echo "Active subnet-router Tailscale IPs: $ips_json"

if [[ "$ips_json" == "[]" ]]; then
  echo "No active subnet-router devices found — refusing to wipe split-DNS" >&2
  exit 1
fi

# POST upserts the domains specified without touching others.
payload=$(printf '{"databaes.net": %s}' "$ips_json")
echo "POSTing: $payload"

curl -sS -f -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -d "$payload" \
  "${API}/dns/split-dns"

echo
echo "Tailscale split-DNS for databaes.net now points to: $ips_json"
