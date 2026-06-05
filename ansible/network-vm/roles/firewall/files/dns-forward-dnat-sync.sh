#!/usr/bin/env bash
# Maintain a DNS-forward DNAT so clients that point their resolver at this
# gateway's LAN VIP get answers from the env's live AdGuard-lxc.
#
# WHY THIS EXISTS
# The k3s worker(s) in dev/qa/prod hardcode DNS = the gateway VIP (.55/.56) in
# netplan. The gateway runs no DNS itself; it must DNAT :53 to the adguard-lxc.
# That DNAT used to be applied by hand, which meant it (a) vanished on every
# gateway reboot -> whole cluster lost external DNS, ARC runners crashloop,
# "deploys hang queued"; and (b) hardcoded one adguard slot, so it broke on
# every adguard blue/green flip (the flip destroys the old slot CT the DNAT
# still pointed at). See /app/issues/heaton-qa-node-down-2026-06-05.md.
#
# This script re-asserts the DNAT on boot and every 2 min, rediscovering
# whichever adguard slot is currently answering :53. Idempotent and creds-free.
set -euo pipefail

# This gateway's LAN VIP — the address clients put in resolv.conf: 192.168.<env>.{55,56}
GW_IP=$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 \
        | grep -E '^192\.168\.(10|20|30)\.(55|56)$' | head -n1) || true
if [ -z "${GW_IP:-}" ]; then
  logger -t dns-forward-dnat "no gateway LAN VIP (.55/.56) on this host; skipping"
  exit 0
fi
PREFIX=${GW_IP%.*}

# AdGuard-lxc slots for this subnet are .97 (blue) / .98 (green). Pick the first
# that accepts a TCP connection on :53 (AdGuard listens on tcp+udp :53).
TARGET=""
for octet in 97 98; do
  cand="${PREFIX}.${octet}"
  if timeout 2 bash -c ">/dev/tcp/${cand}/53" 2>/dev/null; then
    TARGET="$cand"; break
  fi
done
if [ -z "$TARGET" ]; then
  # No live adguard — do NOT tear down existing rules; a transient probe failure
  # must not cause a DNS outage. Leave whatever is in place and retry next tick.
  logger -t dns-forward-dnat "no live adguard at ${PREFIX}.97/.98; leaving DNAT unchanged"
  exit 0
fi

# Remove any managed :53 DNAT for GW_IP and any :53 MASQUERADE for .97/.98, then
# re-add pointing at the live TARGET. Rules are reconstructed from `-S` output so
# the -m udp/-m tcp match modules line up exactly for deletion.
while read -r line; do
  [ -z "$line" ] && continue
  # shellcheck disable=SC2086
  iptables -t nat -D PREROUTING ${line#-A PREROUTING } 2>/dev/null || true
done < <(iptables -t nat -S PREROUTING | grep -E -- "-d ${GW_IP}/32 .*--dport 53 -j DNAT" || true)

while read -r line; do
  [ -z "$line" ] && continue
  # shellcheck disable=SC2086
  iptables -t nat -D POSTROUTING ${line#-A POSTROUTING } 2>/dev/null || true
done < <(iptables -t nat -S POSTROUTING | grep -E -- "-d ${PREFIX}\.(97|98)/32 .*--dport 53 -j MASQUERADE" || true)

iptables -t nat -A PREROUTING  -d "${GW_IP}/32"  -p udp --dport 53 -j DNAT --to-destination "${TARGET}:53"
iptables -t nat -A PREROUTING  -d "${GW_IP}/32"  -p tcp --dport 53 -j DNAT --to-destination "${TARGET}:53"
iptables -t nat -A POSTROUTING -d "${TARGET}/32" -p udp --dport 53 -j MASQUERADE
iptables -t nat -A POSTROUTING -d "${TARGET}/32" -p tcp --dport 53 -j MASQUERADE

logger -t dns-forward-dnat "asserted ${GW_IP}:53 -> ${TARGET}:53"
