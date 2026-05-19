#!/usr/bin/env bash
# Re-assert AdGuard DNS rewrites for every env's dev/QA/prod hostnames against
# the current Tailscale IP of the env's owning network-vm, discovered live via
# `tailscale status --json`. Idempotent: deletes managed-domain rewrites whose
# answer no longer matches the discovered peer IP and re-inserts.
#
# Why this exists: the Ansible role in the same directory writes rewrites
# correctly at the moment it runs, but it sources peer IPs from hardcoded
# vars (`adguard_env_tailscale_ips`). A Tailscale re-registration rotates an
# IP; vars aren't updated; clients resolving *-dev.databaes.net land on a
# dead peer and hit ERR_CONNECTION_TIMED_OUT. This script is the safety net:
# it trusts the tailnet, not the vars file.
#
# Env var inputs (loaded from /etc/adguard-rewrite-sync.env):
#   ADGUARD_URL       e.g. http://127.0.0.1:3000
#   ADGUARD_USER      admin username
#   ADGUARD_PASS      admin password
#   DEV_DOMAINS       space-separated — dev hostnames managed here
#   QA_DOMAINS        space-separated — qa hostnames managed here
#   PROD_DOMAINS      space-separated — prod hostnames managed here
#   DEV_HOSTNAME_RE   regex matching the dev netvm's Tailscale hostname (e.g. ^dev-network-vm-)
#   QA_HOSTNAME_RE    regex matching the qa netvm's Tailscale hostname
#   PROD_HOSTNAME_RE  regex matching the prod netvm's Tailscale hostname

set -euo pipefail

# shellcheck disable=SC1091
. /etc/adguard-rewrite-sync.env

: "${ADGUARD_URL:?}"
: "${ADGUARD_USER:?}"
: "${ADGUARD_PASS:?}"

curl_ag() { curl -sS --fail -u "${ADGUARD_USER}:${ADGUARD_PASS}" "$@"; }

status_json=$(tailscale status --json)

# Resolve an env's TS IPv4 by matching netvm hostname regex against Self + Peer.
# Prefers an "online" peer (we treat Self as always online). Returns empty if
# none found — caller decides whether that's fatal.
resolve_env_ip() {
  local re=$1
  jq -r --arg re "${re}" '
    def online(p): (p.Online // false) or (p.HostName // "" | test("^$"));
    ((.Self | select(.HostName | test($re)) | .TailscaleIPs[0]),
     (.Peer | to_entries | map(.value)
        | map(select(.HostName | test($re)))
        | sort_by((.Online // false) | not)
        | .[0].TailscaleIPs[0])
    ) // empty' <<<"${status_json}" | grep -Ev '^$' | head -n1
}

upsert_batch() {
  local ip=$1; shift
  local domains=("$@")
  [[ ${#domains[@]} -eq 0 ]] && return 0
  [[ -z "${ip}" ]] && { echo "rewrite-sync: no IP for batch (${domains[*]:0:3}…) — skipping" >&2; return 0; }
  local existing
  existing=$(curl_ag "${ADGUARD_URL}/control/rewrite/list")
  for d in "${domains[@]}"; do
    # Delete any existing rewrite for this domain whose answer != ip.
    echo "${existing}" \
      | jq -r --arg d "${d}" --arg a "${ip}" \
          '.[] | select(.domain == $d and .answer != $a) | @json' \
      | while IFS= read -r row; do
          curl_ag -H 'Content-Type: application/json' \
            -X POST "${ADGUARD_URL}/control/rewrite/delete" \
            -d "${row}" >/dev/null || true
        done
    # Idempotent add — 409 if (domain, answer) already present, which is fine.
    curl_ag -H 'Content-Type: application/json' \
      -X POST "${ADGUARD_URL}/control/rewrite/add" \
      -d "$(jq -cn --arg d "${d}" --arg a "${ip}" '{domain:$d, answer:$a}')" \
      -o /dev/null || true
  done
}

dev_ip=$(resolve_env_ip "${DEV_HOSTNAME_RE:-^dev-network-vm-}")
qa_ip=$(resolve_env_ip "${QA_HOSTNAME_RE:-^qa-network-vm-}")
prod_ip=$(resolve_env_ip "${PROD_HOSTNAME_RE:-^prod-network-vm-}")

echo "rewrite-sync: dev=${dev_ip:-?} qa=${qa_ip:-?} prod=${prod_ip:-?}"

# shellcheck disable=SC2086
upsert_batch "${dev_ip}"  ${DEV_DOMAINS:-}
# shellcheck disable=SC2086
upsert_batch "${qa_ip}"   ${QA_DOMAINS:-}
# shellcheck disable=SC2086
upsert_batch "${prod_ip}" ${PROD_DOMAINS:-}

echo "rewrite-sync: done"
