#!/bin/bash
# Export LVM thin-pool usage as node_exporter textfile metrics on a Proxmox host.
# Why: on 2026-10-21 benedict's pve/data pool hit 100% unnoticed and destroyed a
# Postgres data dir (reports/2026-11-06-incidents-postgres-thinpool.md). node_exporter
# has no LVM-thin collector, so this fills the gap. Read-only: only runs `lvs`.
set -u
export LC_ALL=C   # lvs honours LC_NUMERIC; a comma decimal would corrupt the CSV/metric values
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
LVS_BIN="${LVS_BIN:-lvs}"   # override only for tests
OUT="${OUT:-/var/lib/prometheus/node-exporter/lvm_thinpool.prom}"
DIR=$(dirname "$OUT")
[ -d "$DIR" ] || { echo "textfile dir $DIR missing" >&2; exit 1; }

# `lv_attr` starting with 't' = thin pool. Run with a timeout so a wedged LVM can't hang the timer.
RAW=$(timeout -k 5 30 "$LVS_BIN" --noheadings --nosuffix --separator , \
  -o vg_name,lv_name,data_percent,metadata_percent --select 'lv_attr=~^t' 2>/dev/null) || {
  echo "lvs failed or timed out; leaving previous metrics (staleness alert will fire)" >&2
  exit 1
}

# One pass: validate every row (numeric data%/metadata%) and emit both families + a pool count.
# A pool whose percentages are empty/non-numeric (inactive, erroring) makes us FAIL without
# refreshing the success timestamp, so the "stale" alert fires instead of the pool going silent.
BODY=$(echo "$RAW" | awk -F, '
  NF>=4 { gsub(/ /,"",$1); gsub(/ /,"",$2); gsub(/ /,"",$3); gsub(/ /,"",$4);
          if ($3 !~ /^[0-9.]+$/ || $4 !~ /^[0-9.]+$/) { bad=1; next }
          d = d sprintf("lvm_thinpool_data_percent{vg=\"%s\",lv=\"%s\"} %s\n",$1,$2,$3);
          m = m sprintf("lvm_thinpool_metadata_percent{vg=\"%s\",lv=\"%s\"} %s\n",$1,$2,$4);
          n++ }
  END { if (bad) exit 2;
        print "# HELP lvm_thinpool_data_percent LVM thin pool data usage in percent.";
        print "# TYPE lvm_thinpool_data_percent gauge"; printf "%s", d;
        print "# HELP lvm_thinpool_metadata_percent LVM thin pool metadata usage in percent.";
        print "# TYPE lvm_thinpool_metadata_percent gauge"; printf "%s", m;
        print "# HELP lvm_thinpool_count Number of thin pools found.";
        print "# TYPE lvm_thinpool_count gauge"; print "lvm_thinpool_count " (n+0) }') || {
  echo "a thin pool reported empty/non-numeric usage; leaving previous metrics (staleness alert will fire)" >&2
  exit 1
}

TMP=$(mktemp "$OUT.XXXXXX")
trap 'rm -f "$TMP"' EXIT
{
  echo "$BODY"
  echo '# HELP lvm_thinpool_last_success_timestamp_seconds Unix time of the last successful lvs scrape.'
  echo '# TYPE lvm_thinpool_last_success_timestamp_seconds gauge'
  echo "lvm_thinpool_last_success_timestamp_seconds $(date +%s)"
} > "$TMP"
chmod 644 "$TMP"
mv "$TMP" "$OUT"   # atomic: node_exporter never reads a half-written file
trap - EXIT
