output "vms" {
  description = "Toutes les VMs créées"
  value = {
    for vm_name, vm in module.vms :
    vm_name => {
      name    = vm.vm_name
      id      = vm.vm_id
      node    = vm.node_name
      tags    = vm.vm_tags
      ip      = vm.vm_ip
    }
  }
}