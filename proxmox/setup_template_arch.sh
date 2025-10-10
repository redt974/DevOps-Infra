#!/usr/bin/env bash

# ========================================
# 🧱 1. Création d’un template Cloud-Init Arch Linux
# ========================================

set -euo pipefail

# 1. Télécharger l’image Arch Linux Cloud
cd /var/lib/vz/template/iso
if [[ ! -f "arch-Linux-x86_64-cloudimg.qcow2" ]]; then
  wget "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2" -O "arch-Linux-x86_64-cloudimg.qcow2"
fi

# 2. Créer une VM vide sans disque
qm create 1002 \
  --name "arch-cloud-template" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26

# 3. Importer le disque qcow2 dans le stockage local-lvm
qm importdisk 1002 "arch-Linux-x86_64-cloudimg.qcow2" "local-lvm"

# 4. Attacher le disque importé
qm set 1002 --scsihw virtio-scsi-pci --scsi0 "local-lvm:vm-1002-disk-0"

# 5. Définir l'ordre de démarrage sur le disque
qm set 1002 --boot order=scsi0 --bootdisk scsi0

# 6. Ajouter le lecteur cloud-init
qm set 1002 --ide2 "local-lvm:cloudinit,media=cdrom"

# 7. Activer la console série
qm set 1002 --serial0 socket --vga serial0

# 8. Activer le qemu-guest-agent
qm set 1002 --agent enabled=1

# 9. Configurer DHCP via cloud-init
qm set 1002 --ipconfig0 ip=dhcp

# 10. Ajouter des tags
qm set 1002 --tags "template,arch"

# 11. Convertir la VM en template
qm template 1002

echo "✅ Template Cloud-Init créée avec succès !"