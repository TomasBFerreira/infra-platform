output "infra_node_ip" {
  description = "IP address of infra node"
  value       = module.infra_lxc.ip_address
}

output "network_node_ip" {
  description = "IP address of network node"
  value       = module.network_lxc.ip_address
}

output "monitoring_node_ip" {
  description = "IP address of monitoring node"
  value       = module.monitoring_lxc.ip_address
}

output "backup_node_ip" {
  description = "IP address of backup node"
  value       = module.backup_lxc.ip_address
}
