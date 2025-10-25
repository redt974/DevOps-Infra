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

variable "vm_counts" {
  type = map(number)
  default = {
    ubuntu = 3
    debian = 2
    arch   = 1
  }
}

locals {
  vm_list = flatten([
    for os, count in var.vm_counts : [
      for i in range(1, count + 1) : {
        os      = os
        index   = i
        name    = "${var.vm_hostname}-${os}${i}"
      }
    ]
  ])
}

resource "proxmox_virtual_environment_file" "cloud_meta_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data = yamlencode({
      instance_id    = sha1(var.vm_hostname)
      local_hostname = var.vm_hostname
    })
    file_name = "${var.vm_hostname}.${var.domain}-ci-meta.yml"
  }
}

module "vms" {
  source = "./modules/vm"
  for_each = { for vm in local.vm_list : vm.name => vm }

  vm_hostname       = each.value.name
  domain            = var.domain
  template_tag      = var.template_tag
  target_node       = var.target_node
  onboot            = var.onboot
  memory            = var.memory
  cores             = var.cores
  sockets           = var.sockets
  disk              = var.disk
  vm_tags           = concat(var.vm_tags, [each.value.os])
  vm_os             = each.value.os
  proxmox_url       = var.proxmox_url
  proxmox_api_token = var.proxmox_api_token

  user_data = file("${path.root}/cloud-init/${each.value.name}.local/user_data.yml")
}