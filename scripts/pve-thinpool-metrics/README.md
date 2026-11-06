# pve-thinpool-metrics

Exports LVM thin-pool `data%` / `metadata%` from a Proxmox host as `node_exporter` textfile metrics
(`lvm_thinpool_data_percent`, `lvm_thinpool_metadata_percent`, `lvm_thinpool_overcommit_ratio`, `lvm_thinpool_count`, `lvm_thinpool_last_success_timestamp_seconds`),
so the Grafana rules in `otel-monitoring` (`Thin Pool Above 85%` / `95%` / `Nearly Full` / `Overcommitted` / `Metrics Stale`) can alert before
a pool fills. Origin: benedict `pve/data` hit 100% on 2026-10-21 (see `docs/runbooks.md` § "Proxmox LVM thin pool").

PVE hosts have no config-management pipeline, so this is installed by hand (idempotent) and each install is a CMDB change:
`scp -r scripts/pve-thinpool-metrics root@<pve>:/root/ && ssh root@<pve> bash /root/pve-thinpool-metrics/install.sh`.
Requires the Debian `prometheus-node-exporter` textfile dir (`/var/lib/prometheus/node-exporter`) — present on benedict, heaton, betsy.
Rollback: `systemctl disable --now pve-thinpool-metrics.timer; rm /usr/local/bin/pve-thinpool-metrics.sh /etc/systemd/system/pve-thinpool-metrics.* /var/lib/prometheus/node-exporter/lvm_thinpool.prom`.

The stale rule's host list (`benedict|heaton|betsy`) is hardcoded in `otel-monitoring`: add new PVE nodes there.
`lvm_thinpool_overcommit_ratio` = (sum of thin volume + thin snapshot sizes) / pool size. The Grafana data% alerts only fire when it is > 1.05 (a pool at 1.00x with no snapshots can't run out; betsy `nfs-nvme-pool_data` sits at 83% for that reason), except the metadata% alerts (ungated) and the *Nearly Full* warning (data > 99% for 1h, any ratio). The ratio is a worst case: a snapshot counts at its origin's full size. Single `lvs` call; any pool with empty/non-numeric usage makes the script fail closed. **Roll the script out to every host BEFORE deploying the rules**, otherwise the stale rule fires per pool on hosts still on the old script.
