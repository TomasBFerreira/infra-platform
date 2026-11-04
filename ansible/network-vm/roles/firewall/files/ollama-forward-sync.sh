#!/usr/bin/env bash
# Maintain a TCP forward so QA and dev k3s pods can reach the Ollama host (a personal
# Windows PC on the tailnet) through this gateway's LAN VIP.
#
# WHY THIS EXISTS
# Pods have no route to tailnet addresses (100.x). This gateway is on the
# tailnet, so it DNATs  <GW_VIP>:11434  ->  <OLLAMA_UPSTREAM>  and MASQUERADEs
# out of tailscale0. Used by the Qwen incident-remediation experiment, see
# /app/issues/local-llm-remediation-qwen-2026-11-04.md.
#
# SCOPE (deliberately tight)
#  - Acts only when this host's LAN VIP is in OLLAMA_ALLOWED_SUBNET (QA 192.168.30,
#    dev 192.168.20, set per env by ansible). Elsewhere (prod) it is a no-op and
#    removes any stale rule.
#  - Only that worker subnet may use it (-s <subnet>.0/24).
#  - One destination host:port, nothing else.
# Idempotent, creds-free; re-asserted on boot + every 2 min by the timer, like
# dns-forward-dnat (a runtime-only iptables rule is lost on reboot).
#
# Config: /etc/default/ollama-forward  (written by ansible)
#   OLLAMA_UPSTREAM=100.113.78.67   OLLAMA_PORT=11434   OLLAMA_ALLOWED_SUBNET=192.168.30
set -euo pipefail

# Serialize runs: the timer tick, a boot run and a manual/ansible run can overlap, and
# delete-then-add under concurrency leaves duplicate rules.
exec 9>/run/ollama-forward.lock
flock 9

OLLAMA_UPSTREAM=""
OLLAMA_PORT=11434
OLLAMA_ALLOWED_SUBNET="192.168.30"
# shellcheck disable=SC1091
[ -r /etc/default/ollama-forward ] && . /etc/default/ollama-forward

GW_IP=$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 \
        | grep -E '^192\.168\.(10|20|30)\.(55|56)$' | head -n1) || true
if [ -z "${GW_IP:-}" ]; then
  logger -t ollama-forward "no gateway LAN VIP (.55/.56) on this host; skipping"
  exit 0
fi
PREFIX=${GW_IP%.*}

remove_managed() {
  # Delete every rule this script manages (matched on dport + comment tag).
  local line
  while read -r line; do
    [ -z "$line" ] && continue
    # shellcheck disable=SC2086
    iptables -t nat -D PREROUTING ${line#-A PREROUTING } 2>/dev/null || true
  done < <(iptables -t nat -S PREROUTING | grep -- "--comment ollama-forward" || true)
  while read -r line; do
    [ -z "$line" ] && continue
    # shellcheck disable=SC2086
    iptables -t nat -D POSTROUTING ${line#-A POSTROUTING } 2>/dev/null || true
  done < <(iptables -t nat -S POSTROUTING | grep -- "--comment ollama-forward" || true)
}

if [ "$PREFIX" != "$OLLAMA_ALLOWED_SUBNET" ] || [ -z "$OLLAMA_UPSTREAM" ]; then
  remove_managed
  logger -t ollama-forward "not enabled for ${GW_IP} (allowed ${OLLAMA_ALLOWED_SUBNET}.x); no rules"
  exit 0
fi

# Validate upstream is a bare IPv4 so config can't smuggle iptables options.
if ! [[ "$OLLAMA_UPSTREAM" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || ! [[ "$OLLAMA_PORT" =~ ^[0-9]{2,5}$ ]]; then
  logger -t ollama-forward "invalid OLLAMA_UPSTREAM/OLLAMA_PORT; leaving rules unchanged"
  exit 1
fi

DNAT_SPEC=(-s "${PREFIX}.0/24" -d "${GW_IP}/32" -p tcp --dport "$OLLAMA_PORT"
  -m comment --comment ollama-forward -j DNAT --to-destination "${OLLAMA_UPSTREAM}:${OLLAMA_PORT}")
MASQ_SPEC=(-s "${PREFIX}.0/24" -d "${OLLAMA_UPSTREAM}/32" -o tailscale0 -p tcp --dport "$OLLAMA_PORT"
  -m comment --comment ollama-forward -j MASQUERADE)

# Only rewrite when the live rules differ from the desired state. Delete-then-add on every
# 2-min tick would open a brief window where new connections to the forward are refused.
if [ "$(iptables -t nat -S PREROUTING  | grep -c -- '--comment ollama-forward')" = 1 ] \
   && [ "$(iptables -t nat -S POSTROUTING | grep -c -- '--comment ollama-forward')" = 1 ] \
   && iptables -t nat -C PREROUTING  "${DNAT_SPEC[@]}" 2>/dev/null \
   && iptables -t nat -C POSTROUTING "${MASQ_SPEC[@]}" 2>/dev/null; then
  exit 0
fi

remove_managed
iptables -t nat -A PREROUTING  "${DNAT_SPEC[@]}"
iptables -t nat -A POSTROUTING "${MASQ_SPEC[@]}"

logger -t ollama-forward "asserted ${GW_IP}:${OLLAMA_PORT} -> ${OLLAMA_UPSTREAM}:${OLLAMA_PORT} (src ${PREFIX}.0/24)"
