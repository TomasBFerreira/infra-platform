#!/bin/bash
# Delete the network-vm LXC (vmid 220) on all nodes before Terraform apply
# Requires proxmoxer (pip install proxmoxer) and API credentials via environment variables
# Usage: ./scripts/delete-network-vm.sh

set -e

PVE_API_URL="${TF_VAR_pve_api:-$PVE_API}"  # fallback to either env var
PVE_USER="${TF_VAR_pve_user:-$PVE_USER}"
PVE_PASS="${TF_VAR_pve_pass:-$PVE_PASS}"
VMID=251

if [[ -z "$PVE_API_URL" || -z "$PVE_USER" || -z "$PVE_PASS" ]]; then
  echo "Missing Proxmox API credentials. Set TF_VAR_pve_api, TF_VAR_pve_user, TF_VAR_pve_pass or PVE_API, PVE_USER, PVE_PASS."
  exit 0  # Don't fail the workflow, just skip
fi

# Try to delete the LXC on all nodes (benedict, betsy, vladimir)
nodes=(benedict betsy vladimir)
for node in "${nodes[@]}"; do
  echo "Checking for LXC $VMID on node $node..."
  curl -sk -u "$PVE_USER:$PVE_PASS" "$PVE_API_URL/api2/json/nodes/$node/lxc/$VMID/status/current" | grep -q 'status' || continue
  echo "Deleting LXC $VMID on $node..."
  curl -sk -X DELETE -u "$PVE_USER:$PVE_PASS" "$PVE_API_URL/api2/json/nodes/$node/lxc/$VMID"
done
