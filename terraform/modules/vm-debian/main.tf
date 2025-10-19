terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.42.0"
    }
  }
}

data "proxmox_virtual_environment_vms" "template" {
  node_name = var.target_node
  tags      = [var.template_tag]
}

resource "proxmox_virtual_environment_file" "cloud_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data = templatefile("${path.module}/../../cloud-init/${var.vm_hostname}.${var.domain}/user_data.yml",
      {
        local_hostname = var.vm_hostname
        domain         = var.domain
      }
    )
    file_name = "${var.vm_hostname}.${var.domain}-ci-user.yml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_meta_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data = templatefile("${path.module}/../../cloud-init/${var.vm_hostname}.${var.domain}/meta_data.yml",
      {
        instance_id    = sha1(var.vm_hostname)
        local_hostname = var.vm_hostname
      }
    )

    file_name = "${var.vm_hostname}.${var.domain}-ci-meta_data.yml"
  }
}

locals {
  template_vm = [
    for vm in data.proxmox_virtual_environment_vms.template.vms :
    vm if can(regex(lower(var.vm_os), lower(vm.name)))
  ][0]
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = "${var.vm_hostname}.${var.domain}"
  node_name = var.target_node

  on_boot = var.onboot

  boot_order = ["scsi0", "net0"]

  agent {
    enabled = true
  }

  tags = var.vm_tags

  cpu {
    type    = "x86-64-v2-AES"
    cores   = var.cores
    sockets = var.sockets
    flags   = []
  }

  memory {
    dedicated = var.memory
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Ignore changes to the network
  ## MAC address is generated on every apply, causing
  ## TF to think this needs to be rebuilt on every apply
  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }

  scsi_hardware = "virtio-scsi-pci"

  disk {
    interface    = "scsi0"
    iothread     = true
    datastore_id = var.disk.storage
    size         = var.disk.size
    file_format  = "raw"
    discard      = "on"
  }

  # dynamic "disk" {
  #   for_each = var.additionnal_disks
  #   content {
  #     interface    = "scsi${1 + disk.key}"
  #     iothread     = true
  #     datastore_id = disk.value.storage
  #     size         = disk.value.size
  #     discard      = "ignore"
  #     file_format  = "raw"
  #   }
  # }

  clone {
    vm_id = local.template_vm.vm_id
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    datastore_id      = "local-lvm"
    interface         = "ide2"
    user_data_file_id = proxmox_virtual_environment_file.cloud_user_config.id
    meta_data_file_id = proxmox_virtual_environment_file.cloud_meta_config.id
  }

}