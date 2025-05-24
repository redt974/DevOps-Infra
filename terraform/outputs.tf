# Outputs pour le module de création de VM Ubuntu sur Proxmox
output "vm_name" {
  description = "Nom de la VM créée"
  value = module.ubuntu_vm.vm_name
}

output "vm_id" {
  description = "ID interne de la VM"
  value = module.ubuntu_vm.vm_id
}

output "node_name" {
  description = "Noeud Proxmox où est déployée la VM"
  value = module.ubuntu_vm.node_name
}

output "vm_tags" {
  description = "Tags associés à la VM"
  value = module.ubuntu_vm.vm_tags
}

# # Outputs pour le module de création de VM Debian sur Proxmox
# output "vm_name" {
#   description = "Nom de la VM créée"
#   value = module.debian_vm.vm_name
# }

# output "vm_id" {
#   description = "ID interne de la VM"
#   value = module.debian_vm.vm_id
# }

# output "node_name" {
#   description = "Noeud Proxmox où est déployée la VM"
#   value = module.debian_vm.node_name
# }

# output "vm_tags" {
#   description = "Tags associés à la VM"
#   value = module.debian_vm.vm_tags
# }

# # Outputs pour le module de création de VM Arch sur Proxmox
# output "vm_name" {
#   description = "Nom de la VM créée"
#   value = module.arch_vm.vm_name
# }

# output "vm_id" {
#   description = "ID interne de la VM"
#   value = module.arch_vm.vm_id
# }

# output "node_name" {
#   description = "Noeud Proxmox où est déployée la VM"
#   value = module.arch_vm.node_name
# }

# output "vm_tags" {
#   description = "Tags associés à la VM"
#   value = module.arch_vm.vm_tags
# }
