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
    username = var.ssh_user
  }

  insecure = true
}

module "ubuntu_vm" {
  source = "./modules/vm-ubuntu"

  vm_hostname         = "${var.vm_hostname}-ubuntu"
  domain              = var.domain
  template_tag        = var.template_tag
  target_node         = var.target_node
  onboot              = var.onboot
  memory              = var.memory
  cores               = var.cores
  sockets             = var.sockets
  vm_tags             = concat(var.vm_tags, ["ubuntu"])
  vm_os               = "ubuntu"
  proxmox_url         = var.proxmox_url
  proxmox_api_token   = var.proxmox_api_token
}

module "debian_vm" {
  source = "./modules/vm-debian"

  vm_hostname         = "${var.vm_hostname}-debian"
  domain              = var.domain
  template_tag        = var.template_tag
  target_node         = var.target_node
  onboot              = var.onboot
  memory              = var.memory
  cores               = var.cores
  sockets             = var.sockets
  vm_tags             = concat(var.vm_tags, ["debian"])
  vm_os               = "debian"
  proxmox_url         = var.proxmox_url
  proxmox_api_token   = var.proxmox_api_token
}

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
#   vm_tags             = concat(var.vm_tags, ["arch"])
#   proxmox_url         = var.proxmox_url
#   proxmox_api_token   = var.proxmox_api_token
# }