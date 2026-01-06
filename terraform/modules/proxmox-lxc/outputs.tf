output "container_id" {
  description = "The VMID of the LXC container"
  value       = proxmox_lxc.container.vmid
}

output "hostname" {
  description = "The hostname of the LXC container"
  value       = proxmox_lxc.container.hostname
}

output "ip_address" {
  description = "The IP address of the LXC container"
  value       = split("/", var.network_ip)[0]
}

output "network_ip_cidr" {
  description = "The IP address with CIDR notation"
  value       = var.network_ip
}
