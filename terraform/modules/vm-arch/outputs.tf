output "vm_name" {
  description = "Nom de la VM créée"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "vm_id" {
  description = "ID interne de la VM"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "node_name" {
  description = "Noeud Proxmox où est déployée la VM"
  value       = proxmox_virtual_environment_vm.vm.node_name
}

output "vm_tags" {
  description = "Tags associés à la VM"
  value       = proxmox_virtual_environment_vm.vm.tags
}

output "vm_ip" {
  value = flatten(proxmox_virtual_environment_vm.vm.ipv4_addresses)
}