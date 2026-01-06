output "vm_id" {
  description = "The VMID of the virtual machine"
  value       = proxmox_vm_qemu.vm.vmid
}

output "name" {
  description = "The name of the virtual machine"
  value       = proxmox_vm_qemu.vm.name
}

output "ip_address" {
  description = "The IP address of the virtual machine"
  value       = var.network_ip != "" ? split("/", var.network_ip)[0] : null
}

output "network_ip_cidr" {
  description = "The IP address with CIDR notation"
  value       = var.network_ip
}
