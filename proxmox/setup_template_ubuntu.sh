#!/usr/bin/env bash

# ========================================
# 🧱 1. Création d’un template Cloud-Init
# ========================================

# 1. Télécharger l’image Ubuntu Cloud
cd /var/lib/vz/template/iso
if [[ ! -f "ubuntu-22.04-cloudimg.img" ]]; then
  wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O ubuntu-22.04-cloudimg.img
fi

# 2. Créer une VM "squelette"
qm create 1000 \
  --name "ubuntu-cloud-template" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0

# 3. Importer le disque dans le storage "local-lvm"
qm importdisk 1000 ubuntu-22.04-cloudimg.img local-lvm

# 4. Connecter le disque importé à la VM
qm set 1000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-1000-disk-0

# 5. Configurer le boot sur ce disque
qm set 1000 --boot c --bootdisk scsi0

# 6. Ajouter le lecteur cloud-init
qm set 1000 --ide2 local-lvm:cloudinit,media=cdrom

# 7. Activer la console série (utile pour le débogage cloud-init)
qm set 1000 --serial0 socket --vga serial0

# 8. Activer le qemu-guest-agent
qm set 1000 --agent enabled=1

# 9. (Optionnel mais recommandé) Config IP par DHCP via cloud-init
qm set 1000 --ipconfig0 ip=dhcp

# 10. Ajouter un tag pour retrouver facilement la template
qm set 1000 --tags "template,ubuntu"

# 11. Convertir la VM en template
qm template 1000

echo "✅ Template Cloud-Init créé avec succès !"