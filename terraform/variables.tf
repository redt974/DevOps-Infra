variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH pour cloud-init"
  type        = string
}

variable "ssh_private_key" {
  description = "Contenu de la clé privée SSH pour provisionnement ou debug (non recommandé en prod)"
  type        = string
  sensitive   = true
}

variable "ssh_user" {
  description = "Nom d'utilisateur pour SSH"
  type        = string
  default    = "root"
}

variable "ssh_port" {
  description = "Port SSH"
  type        = number
  default     = 22
}

variable "proxmox_url" { 
  description = "URL de l'API Proxmox"
  type        = string
  default     = "https://192.168.10.180:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API Token in format id=secret"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "Proxmox node"
  type        = string
  default = "pve"
}

variable "onboot" {
  description = "Auto start VM when node is start"
  type        = bool
  default     = true
}

variable "target_node_domain" {
  description = "Proxmox node domain"
  type        = string
  default = "proxmox.local"
}

variable "vm_hostname" {
  description = "VM hostname"
  type        = string
  default = "serveur"
}

variable "domain" {
  description = "VM domain"
  type        = string
  default = "local"
}

variable "vm_tags" {
  description = "VM tags"
  type        = list(string)
  default = [ "serveur" ]
}

variable "template_tag" {
  description = "Template tag"
  type        = string
  default = "template"
}

variable "sockets" {
  description = "Number of sockets"
  type        = number
  default     = 1
}

variable "cores" {
  description = "Number of cores"
  type        = number
  default     = 1
}

variable "memory" {
  description = "Number of memory in MB"
  type        = number
  default     = 2048
}

variable "disk" {
  description = "Disk (size in Gb)"
  type = object({
    storage = string
    size    = number
  })
  default = {
    storage = "local-lvm"
    size = 10
  }
}

variable "additionnal_disks" {
  description = "Additionnal disks"
  type = list(object({
    storage = string
    size    = number
  }))
  default = []
}