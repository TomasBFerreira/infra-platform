# nvidia-device-plugin

Cluster manifests that make a GPU schedulable on the prod k3s cluster
(`worker-node-gpu-01`, VMID 121, betsy — GTX 970). Applied by the
`worker-node-gpu` Ansible playbook after k3s comes up; can also be applied by
hand:

```bash
k3s kubectl apply -k manifests/nvidia-device-plugin/
```

`RuntimeClass/nvidia` + the device-plugin DaemonSet are the only in-cluster
pieces. They depend on node- and host-level setup that the `worker-node-gpu`
Terraform + Ansible now provision (see below). First enabled **2026-06-06** —
history in `/app/issues/gpu-passthrough-deferred.md`.

## Full enablement recipe (what the pipeline reproduces)

1. **Proxmox host (betsy) — bind the GPU to `vfio-pci`.** *Not pipeline-managed*
   (host-level config). The card must be on `vfio-pci`, not `nvidia`/`nouveau`:
   - `/etc/modprobe.d/vfio.conf`: `options vfio-pci ids=10de:13c2,10de:0fbb` +
     `softdep nvidia pre: vfio-pci` (+ nouveau).
   - blacklist `nouveau`/`nvidia`; add `vfio vfio_iommu_type1 vfio_pci` to
     `/etc/modules`; `update-initramfs -u`.
   - IOMMU must be on (`intel_iommu=on`); the GTX 970 is alone in IOMMU group 15
     (clean — no ACS override). PVE also rebinds vfio at VM start when the card
     is idle, so this is belt-and-suspenders.
2. **VM (Terraform).** `terraform/worker-node-gpu/main.tf` attaches the device
   via `hostpci` using `var.gpu_pci_id` (default `0000:26:00`). Kept on i440fx
   (`pcie = false`) so the guest NIC name doesn't change.
3. **Guest driver + runtime (Ansible).** `worker-node-gpu_setup.yml` installs the
   **proprietary** `nvidia-headless-535-server` (the `-open` modules don't
   support Maxwell), `nvidia-container-toolkit`, sets `fs.inotify.max_user_*`
   (the device plugin's FS watcher fails with "too many open files" on a busy
   node otherwise), and restarts k3s so it templates the `nvidia` containerd
   runtime.
4. **Cluster (these manifests).** RuntimeClass + device-plugin DaemonSet.

Verify: `kubectl get node worker-node-gpu-01 -o jsonpath='{.status.capacity.nvidia\.com/gpu}'` → `1`.

## Consuming the GPU

Add to any workload that should transcode/compute on the GPU (e.g. Jellyfin):

```yaml
spec:
  template:
    spec:
      runtimeClassName: nvidia
      containers:
        - name: <app>
          resources:
            limits:
              nvidia.com/gpu: 1
          env:
            - name: NVIDIA_VISIBLE_DEVICES
              value: all
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: compute,video,utility   # `video` = NVENC/NVDEC
```

> As of 2026-06-06 nothing consumes the GPU (Plex/Jellyfin were removed; a
> `feat/jellyfin-seerr-migration` branch is pending). The plugin is harmless
> when idle.
