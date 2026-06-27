#!/usr/bin/env bash
# Determine the Tailscale IPv4 addresses that should serve split-DNS for
# databaes.net, then PATCH them as the nameserver set so Tailscale clients
# resolve *.databaes.net via AdGuard on those hosts.
#
# Preferred source is ACTIVE_ADGUARD_HOSTS_JSON from Vault-backed active-slot
# records because that tracks the blue/green source of truth directly while
# still resolving to the correct Tailscale IPs through the Tailscale API.
# If that env var is unset, fall back to ACTIVE_ADGUARD_IPS_JSON, then to
# broad Tailscale device discovery.
#
# Required env:
#   TAILSCALE_API_KEY  - API key with DNS write scope
#   TAILSCALE_TAILNET  - e.g. taild7df92.ts.net
# Optional env:
#   ACTIVE_ADGUARD_HOSTS_JSON - JSON array of active AdGuard hostnames
#                               (for example ["qa-adguard-lxc-blue"])
#   ACTIVE_ADGUARD_IPS_JSON   - JSON array of IPv4 strings to publish as the
#                               split-DNS nameserver set for databaes.net
set -euo pipefail

: "${TAILSCALE_API_KEY:?TAILSCALE_API_KEY is required}"
: "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET is required}"

API="https://api.tailscale.com/api/v2/tailnet/${TAILSCALE_TAILNET}"
AUTH="Authorization: Bearer ${TAILSCALE_API_KEY}"

curl -sS -f -H "$AUTH" "${API}/devices" > /tmp/ts_devices.json

if [[ -n "${ACTIVE_ADGUARD_HOSTS_JSON:-}" ]]; then
  ips_json=$(python3 <<'PY'
import json, os

with open("/tmp/ts_devices.json") as f:
    data = json.load(f)

hosts = json.loads(os.environ["ACTIVE_ADGUARD_HOSTS_JSON"])
if not isinstance(hosts, list) or not all(isinstance(host, str) for host in hosts):
    raise SystemExit("ACTIVE_ADGUARD_HOSTS_JSON must be a JSON array of strings")

targets = {host.lower() for host in hosts}
ips = []
for d in data.get("devices", []):
    host = (d.get("hostname") or "").lower()
    if host not in targets:
        continue
    for a in d.get("addresses", []):
        if ":" in a:
            continue
        if a not in ips:
            ips.append(a)
        break

missing = sorted(targets - {(d.get("hostname") or "").lower() for d in data.get("devices", [])})
if missing:
    import sys
    print(f"WARNING: Could not resolve AdGuard hosts in Tailscale API (skipping): {missing}", file=sys.stderr)
if not ips:
    raise SystemExit("No active AdGuard hosts resolved — refusing to wipe split-DNS")

print(json.dumps(ips))
PY
  )
  echo "Using Vault-derived active AdGuard hostnames: ${ACTIVE_ADGUARD_HOSTS_JSON}"
  echo "Resolved active AdGuard Tailscale IPs: $ips_json"
elif [[ -n "${ACTIVE_ADGUARD_IPS_JSON:-}" ]]; then
  ips_json=$(python3 <<'PY'
import json, os, sys
raw = os.environ["ACTIVE_ADGUARD_IPS_JSON"]
try:
    ips = json.loads(raw)
except json.JSONDecodeError as exc:
    raise SystemExit(f"ACTIVE_ADGUARD_IPS_JSON is not valid JSON: {exc}")
if not isinstance(ips, list) or not all(isinstance(ip, str) for ip in ips):
    raise SystemExit("ACTIVE_ADGUARD_IPS_JSON must be a JSON array of strings")
seen = set()
ordered = []
for ip in ips:
    if ":" in ip:
        continue
    if ip in seen:
        continue
    seen.add(ip)
    ordered.append(ip)
print(json.dumps(ordered))
PY
  )
  echo "Using Vault-derived active AdGuard Tailscale IPs: $ips_json"
else
  ips_json=$(python3 <<'PY'
import json, re
with open("/tmp/ts_devices.json") as f:
    data = json.load(f)
# Match e.g. "dev-adguard-lxc-blue", "prod-adguard-lxc-green".
ADGUARD_HOST = re.compile(r"^(dev|qa|prod)-adguard-lxc-(blue|green)$")
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

  echo "Using discovered AdGuard-bearing Tailscale IPs: $ips_json"
fi

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
