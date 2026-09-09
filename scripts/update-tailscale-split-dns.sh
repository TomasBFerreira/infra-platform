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
# GOTCHA (found 2026-09-09, see /app/issues/tailscale-splitdns-hostname-mismatch-2026-09-09.md):
# the LXCs' real Tailscale hostname is just "adguard-lxc-<slot>" — NOT
# "<env>-adguard-lxc-<slot>". Every env's AdGuard registers under the same
# base hostname; Tailscale disambiguates same-name devices with its own
# "-1"/"-2"/"-3" DNS suffix (registration-order-based, unrelated to env),
# so matching on a guessed "<env>-adguard-lxc-<slot>" string can never hit
# a real device — this previously left split-DNS silently unrefreshed
# (or wiped, since the script correctly refuses to PATCH with an empty
# set — the actual failure mode observed was "stays on whatever was last
# set, however long ago that was"). The one field that DOES carry the env
# is each device's ACL tags (tag:dev / tag:qa / tag:prod, confirmed via
# `tailscale status --json`'s Self.Tags on the live dev AdGuard CT) — so
# ACTIVE_ADGUARD_HOSTS_JSON below is now a JSON array of {"env","slot"}
# objects, matched against hostname-prefix + tag together, not a
# pre-joined hostname string. The regex fallback path gets the same fix.
#
# Required env:
#   TAILSCALE_API_KEY  - API key with DNS write scope
#   TAILSCALE_TAILNET  - e.g. taild7df92.ts.net
# Optional env:
#   ACTIVE_ADGUARD_HOSTS_JSON - JSON array of {"env":"dev","slot":"blue"}
#                               objects, one per env whose active AdGuard
#                               slot should serve split-DNS
#   ACTIVE_ADGUARD_IPS_JSON   - JSON array of IPv4 strings to publish as the
#                               split-DNS nameserver set for databaes.net
#                               (bypasses Tailscale API device lookup
#                               entirely — use when you already know the
#                               exact Tailscale IPs, e.g. from `tailscale
#                               ip -4` run directly on each host)
set -euo pipefail

: "${TAILSCALE_API_KEY:?TAILSCALE_API_KEY is required}"
: "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET is required}"

API="https://api.tailscale.com/api/v2/tailnet/${TAILSCALE_TAILNET}"
AUTH="Authorization: Bearer ${TAILSCALE_API_KEY}"

curl -sS -f -H "$AUTH" "${API}/devices" > /tmp/ts_devices.json

if [[ -n "${ACTIVE_ADGUARD_HOSTS_JSON:-}" ]]; then
  ips_json=$(python3 <<'PY'
import json, os, sys

with open("/tmp/ts_devices.json") as f:
    data = json.load(f)

entries = json.loads(os.environ["ACTIVE_ADGUARD_HOSTS_JSON"])
if not isinstance(entries, list):
    raise SystemExit("ACTIVE_ADGUARD_HOSTS_JSON must be a JSON array")

devices = data.get("devices", [])
ips, missing = [], []
for e in entries:
    # Current format: {"env": "dev", "slot": "blue"}. A plain string is
    # tolerated (old callers) but parsed on a best-effort basis — it can't
    # reliably match since real hostnames carry no env prefix.
    if isinstance(e, dict):
        env, slot = e.get("env"), e.get("slot")
    else:
        parts = str(e).split("-adguard-lxc-", 1)
        env, slot = (parts[0], parts[1]) if len(parts) == 2 else (None, None)

    want_host = f"adguard-lxc-{slot}".lower() if slot else None
    want_tag = f"tag:{env}" if env else None

    match = None
    for d in devices:
        if d.get("authorized") is False:
            continue
        host = (d.get("hostname") or "").lower()
        tags = d.get("tags") or []
        if want_host and host != want_host:
            continue
        if want_tag and want_tag not in tags:
            continue
        match = d
        break

    if not match:
        missing.append(e)
        continue
    for a in match.get("addresses", []):
        if ":" in a:
            continue
        if a not in ips:
            ips.append(a)
        break

if missing:
    print(f"WARNING: Could not resolve AdGuard hosts in Tailscale API (skipping): {missing}", file=sys.stderr)
if not ips:
    raise SystemExit("No active AdGuard hosts resolved — refusing to wipe split-DNS")

print(json.dumps(ips))
PY
  )
  echo "Using Vault-derived active AdGuard slots: ${ACTIVE_ADGUARD_HOSTS_JSON}"
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
import json
with open("/tmp/ts_devices.json") as f:
    data = json.load(f)
devices = data.get("devices", [])
# One AdGuard per env, by tag — not by a guessed "<env>-adguard-lxc-*"
# hostname (real hostnames are just "adguard-lxc-<slot>", identical
# across envs; only the ACL tags carry which env a device belongs to).
ips = []
for env in ("dev", "qa", "prod"):
    want_tag = f"tag:{env}"
    for d in devices:
        if d.get("authorized") is False:
            continue
        host = (d.get("hostname") or "").lower()
        tags = d.get("tags") or []
        if not host.startswith("adguard-lxc-") or want_tag not in tags:
            continue
        for a in d.get("addresses", []):
            if ":" in a:
                continue
            if a not in ips:
                ips.append(a)
            break
        break  # first authorized match per env
print(json.dumps(ips))
PY
  )

  echo "Using discovered AdGuard-bearing Tailscale IPs: $ips_json"
fi

if [[ "$ips_json" == "[]" ]]; then
  echo "No active AdGuard-bearing devices found — refusing to wipe split-DNS" >&2
  exit 1
fi

# PATCH upserts the domains specified without touching others; POST replaces all.
# tomajflix.app is also routed through AdGuard so dev.tomajflix.app rewrites
# are served to Tailscale clients (otherwise the query goes to public CF DNS).
payload=$(printf '{"databaes.net": %s, "tomajflix.app": %s}' "$ips_json" "$ips_json")
echo "PATCHing: $payload"

curl -sS -f -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d "$payload" \
  "${API}/dns/split-dns"

echo
echo "Tailscale split-DNS for databaes.net + tomajflix.app now points to: $ips_json"
