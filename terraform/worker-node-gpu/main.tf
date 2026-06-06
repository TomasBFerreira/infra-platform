data "vault_generic_secret" "ssh_key" {
  path = "secret/ssh_keys/worker_node_worker"
}

resource "proxmox_virtual_environment_vm" "worker_node_gpu" {
  name      = var.vm_hostname
  vm_id     = var.vmid
  node_name = var.target_node

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  cpu {
    cores   = 6
    sockets = 1
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

  # GPU passthrough. The host must have the card bound to vfio-pci first (see
  # manifests/nvidia-device-plugin/README.md). pcie=false keeps the VM on
  # i440fx so the guest NIC name doesn't change. Passes all functions of the
  # device (VGA + audio) since gpu_pci_id has no function suffix.
  hostpci {
    device = "hostpci0"
    id     = var.gpu_pci_id
    pcie   = false
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
    user_account {
      username = "root"
      keys     = [trimspace(data.vault_generic_secret.ssh_key.data["public_key"])]
    }
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
