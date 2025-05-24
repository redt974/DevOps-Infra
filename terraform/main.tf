terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.42.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = var.proxmox_api_token

  ssh {
    agent    = true
    username = "root"
  }

  insecure = false
}

module "ubuntu_vm" {
  source = "./modules/vm-ubuntu"

  vm_hostname         = var.vm_hostname
  domain              = var.domain
  template_tag        = var.template_tag
  target_node         = var.target_node
  onboot              = var.onboot
  memory              = var.memory
  cores               = var.cores
  sockets             = var.sockets
  vm_tags             = var.vm_tags
  proxmox_url         = var.proxmox_url
  proxmox_api_token   = var.proxmox_api_token
}

# module "debian_vm" {
#   source = "./modules/vm-debian"

#   vm_hostname         = var.vm_hostname
#   domain              = var.domain
#   template_tag        = var.template_tag
#   target_node         = var.target_node
#   onboot              = var.onboot
#   memory              = var.memory
#   cores               = var.cores
#   sockets             = var.sockets
#   vm_tags             = var.vm_tags
#   proxmox_url         = var.proxmox_url
#   proxmox_api_token   = var.proxmox_api_token
# }

# module "arch_vm" {
#   source = "./modules/vm-arch"

#   vm_hostname         = var.vm_hostname
#   domain              = var.domain
#   template_tag        = var.template_tag
#   target_node         = var.target_node
#   onboot              = var.onboot
#   memory              = var.memory
#   cores               = var.cores
#   sockets             = var.sockets
#   vm_tags             = var.vm_tags
#   proxmox_url         = var.proxmox_url
#   proxmox_api_token   = var.proxmox_api_token
# }