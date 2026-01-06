output "worker_vm_01_id" {
  description = "VM ID of worker node 01"
  value       = module.worker_vm.vm_id
}

output "worker_vm_01_name" {
  description = "Name of worker node 01"
  value       = module.worker_vm.name
}

output "worker_vm_02_id" {
  description = "VM ID of worker node 02"
  value       = module.worker_vm_02.vm_id
}

output "worker_vm_02_name" {
  description = "Name of worker node 02"
  value       = module.worker_vm_02.name
}
