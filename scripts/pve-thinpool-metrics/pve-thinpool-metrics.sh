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

# ONE lvs call (no race between listings, one I/O pass), all LVs in all VGs. Run with a timeout so a wedged LVM
# can't hang the timer. Columns: vg,lv,attr,size(bytes),pool_lv,data%,meta%.
RAW=$(timeout -k 5 30 "$LVS_BIN" --noheadings --nosuffix --units b --separator , \
  -o vg_name,lv_name,lv_attr,lv_size,pool_lv,data_percent,metadata_percent 2>/dev/null) || {
  echo "lvs failed or timed out; leaving previous metrics (staleness alert will fire)" >&2
  exit 1
}

# One pass. Pools = attr 't...'; thin volumes AND thin snapshots = attr 'V...' with a pool_lv.
# overcommit ratio = (sum of ALL thin volume + snapshot sizes in the pool) / pool size. >1 means the volumes can
# claim more than the pool has -- the only way a pool really runs out (benedict 2026-10-21: 2314 GiB of volumes on
# a 1710 GiB pool). Snapshots count: a snapshot can diverge up to its origin's size, so excluding them could hide
# real risk. A pool at 1.00x with no snapshots (betsy nfs-nvme) sits at high data% harmlessly.
# A pool with empty/non-numeric usage (inactive, erroring) makes us FAIL without refreshing the success timestamp,
# so the "stale" alert fires instead of the pool going silent. Ratio exists for every pool by construction.
# NOTE the ratio is a WORST CASE: a snapshot counts at its origin's full size although it usually shares most blocks.
BODY=$(echo "$RAW" | awk -F, '
  NF<7 && $0 !~ /^[ ]*$/ { bad=1; next }                      # malformed row: fail closed, never skip silently
  NF>=7 { for (i=1;i<=7;i++) gsub(/^ +| +$/,"",$i);
          k = $1 "/" $2;
          if ($3 ~ /^t/) {                                     # thin pool: size and usage must all be numeric
            if ($4 !~ /^[0-9]+$/ || $6 !~ /^[0-9.]+$/ || $7 !~ /^[0-9.]+$/) { bad=1; next }
            psize[k]=$4; dp[k]=$6; mp[k]=$7; vg[k]=$1; lv[k]=$2; n++
          } else if ($3 ~ /^V/ && $5 != "") {                  # thin volume or snapshot: size must be numeric
            if ($4 !~ /^[0-9]+$/) { bad=1; next }
            virt[$1 "/" $5] += $4 } }
  END { if (bad) exit 2;
        print "# HELP lvm_thinpool_data_percent LVM thin pool data usage in percent.";
        print "# TYPE lvm_thinpool_data_percent gauge";
        for (k in psize) printf "lvm_thinpool_data_percent{vg=\"%s\",lv=\"%s\"} %s\n", vg[k], lv[k], dp[k];
        print "# HELP lvm_thinpool_metadata_percent LVM thin pool metadata usage in percent.";
        print "# TYPE lvm_thinpool_metadata_percent gauge";
        for (k in psize) printf "lvm_thinpool_metadata_percent{vg=\"%s\",lv=\"%s\"} %s\n", vg[k], lv[k], mp[k];
        print "# HELP lvm_thinpool_overcommit_ratio Sum of thin volume+snapshot sizes divided by pool size; >1 = overcommitted.";
        print "# TYPE lvm_thinpool_overcommit_ratio gauge";
        for (k in psize) if (psize[k] > 0) printf "lvm_thinpool_overcommit_ratio{vg=\"%s\",lv=\"%s\"} %.4f\n", vg[k], lv[k], virt[k]/psize[k];
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
