data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/worker_node_worker"
}

resource "proxmox_virtual_environment_vm" "worker_node_gpu" {
  name      = var.vm_hostname
  vm_id     = var.vmid
  node_name = var.target_node

  # q35 is required for proper PCIe passthrough (hostpci with pcie=true).
  machine = "q35"

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  cpu {
    cores   = 6
    sockets = 1
    # "host" exposes all host CPU features — needed for NVENC/NVDEC instruction sets.
    type    = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 50
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    model  = "virtio"
    bridge = var.network_bridge
  }

  # GTX 970 (GM204) passthrough — both functions (VGA + audio) in IOMMU group 15.
  # The GPU is bound to vfio-pci on the host and is not used by the hypervisor.
  hostpci {
    device = "hostpci0"
    id     = var.gpu_pci_id
    pcie   = true
    rombar = true
    xvga   = false
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = [var.gateway]
    }
    user_account {
      username = "root"
      keys     = [trimspace(data.vault_generic_secret.ssh_key.data["public_key"])]
    }
  }

  # Serial console for Ansible/SSH access (separate from GPU display output).
  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

  agent {
    enabled = true
    timeout = "15m"
  }

  lifecycle {
    ignore_changes = [
      network_device,
      disk,
    ]
  }
}

output "worker_node_gpu_ip" {
  value = var.ip_address
}
