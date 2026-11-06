#!/bin/bash
# Idempotent installer. Run as root ON a Proxmox host (benedict/heaton/betsy):
#   scp -r scripts/pve-thinpool-metrics root@<pve>:/root/ && ssh root@<pve> bash /root/pve-thinpool-metrics/install.sh
# (copy into /root, not /tmp: this runs as root and installs a root-run script)
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
[ "$(stat -c %u "$D")" = "0" ] || { echo "refusing: $D is not root-owned" >&2; exit 1; }
TF=/var/lib/prometheus/node-exporter
[ -d "$TF" ] || { echo "missing $TF: needs the Debian prometheus-node-exporter textfile dir" >&2; exit 1; }
install -m 0755 "$D/pve-thinpool-metrics.sh" /usr/local/bin/pve-thinpool-metrics.sh
install -m 0644 "$D/pve-thinpool-metrics.service" /etc/systemd/system/
install -m 0644 "$D/pve-thinpool-metrics.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pve-thinpool-metrics.timer
systemctl start pve-thinpool-metrics.service
echo "--- exported metrics:"; cat /var/lib/prometheus/node-exporter/lvm_thinpool.prom
