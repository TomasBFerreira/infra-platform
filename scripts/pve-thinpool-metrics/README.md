# pve-thinpool-metrics

Exports LVM thin-pool `data%` / `metadata%` from a Proxmox host as `node_exporter` textfile metrics
(`lvm_thinpool_data_percent`, `lvm_thinpool_metadata_percent`, `lvm_thinpool_last_success_timestamp_seconds`),
so the Grafana rules in `otel-monitoring` (`Thin Pool Above 85%` / `95%` / `Collector Stale`) can alert before
a pool fills. Origin: benedict `pve/data` hit 100% on 2026-10-21 (see `docs/runbooks.md` § "Proxmox LVM thin pool").

PVE hosts have no config-management pipeline, so this is installed by hand (idempotent) and each install is a CMDB change:
`scp -r scripts/pve-thinpool-metrics root@<pve>:/root/ && ssh root@<pve> bash /root/pve-thinpool-metrics/install.sh`.
Requires the Debian `prometheus-node-exporter` textfile dir (`/var/lib/prometheus/node-exporter`) — present on benedict, heaton, betsy.
Rollback: `systemctl disable --now pve-thinpool-metrics.timer; rm /usr/local/bin/pve-thinpool-metrics.sh /etc/systemd/system/pve-thinpool-metrics.* /var/lib/prometheus/node-exporter/lvm_thinpool.prom`.

Also exports `lvm_thinpool_count`. A pool with empty/non-numeric usage makes the script fail without refreshing the timestamp, so the stale alert fires. The stale rule's host list (`benedict|heaton|betsy`) is hardcoded in `otel-monitoring`: add new PVE nodes there.
