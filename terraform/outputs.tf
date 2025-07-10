# Outputs pour le module de création de VM Ubuntu sur Proxmox
output "ubuntu_vm_name" {
  description = "Nom de la VM créée"
  value = module.ubuntu_vm.vm_name
}

output "ubuntu_vm_id" {
  description = "ID interne de la VM"
  value = module.ubuntu_vm.vm_id
}

output "ubuntu_node_name" {
  description = "Noeud Proxmox où est déployée la VM"
  value = module.ubuntu_vm.node_name
}

output "ubuntu_vm_tags" {
  description = "Tags associés à la VM"
  value = module.ubuntu_vm.vm_tags
}

output "ubuntu_vm_ip" {
  value = module.ubuntu_vm.vm_ip
  description = "Adresse IP de la VM Ubuntu"
}

# Outputs pour le module de création de VM Debian sur Proxmox
output "debian_vm_name" {
  description = "Nom de la VM créée"
  value = module.debian_vm.vm_name
}

output "debian_vm_id" {
  description = "ID interne de la VM"
  value = module.debian_vm.vm_id
}

output "debian_node_name" {
  description = "Noeud Proxmox où est déployée la VM"
  value = module.debian_vm.node_name
}

output "debian_vm_tags" {
  description = "Tags associés à la VM"
  value = module.debian_vm.vm_tags
}

output "debian_vm_ip" {
  value = module.debian_vm.vm_ip
  description = "Adresse IP de la VM Debian"
}

# # Outputs pour le module de création de VM Arch sur Proxmox
# output "arch_vm_name" {
#   description = "Nom de la VM créée"
#   value = module.arch_vm.vm_name
# }

# output "arch_vm_id" {
#   description = "ID interne de la VM"
#   value = module.arch_vm.vm_id
# }

# output "arch_node_name" {
#   description = "Noeud Proxmox où est déployée la VM"
#   value = module.arch_vm.node_name
# }

# output "arch_vm_tags" {
#   description = "Tags associés à la VM"
#   value = module.arch_vm.vm_tags
# }

# output "arch_vm_ip" {
#   value = module.arch_vm.vm_ip
#   description = "Adresse IP de la VM Arch"
# }