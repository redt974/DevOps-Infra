#!/usr/bin/env bash

# ========================================
# 🧱 1. Création d’un template Cloud-Init
# ========================================

# 📥 1. Télécharger l’image Debian Cloud
cd /var/lib/vz/template/iso
if [[ ! -f "debian-12-cloudimg.qcow2" ]]; then
  wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 -O debian-12-cloudimg.qcow2
fi

# ⚙️ 2. Créer une VM squelette
qm create 1001 \
  --name "debian-cloud-template" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0

# 💾 3. Importer le disque dans local-lvm
qm importdisk 1001 debian-12-cloudimg.qcow2 local-lvm

# 🔗 4. Connecter le disque à la VM
qm set 1001 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-1001-disk-0

# 🚀 5. Boot sur le disque
qm set 1001 --boot c --bootdisk scsi0

# 📀 6. Ajouter lecteur cloud-init
qm set 1001 --ide2 local-lvm:cloudinit,media=cdrom

# 🖥️ 7. Console série
qm set 1001 --serial0 socket --vga serial0

# 📡 8. QEMU Guest Agent
qm set 1001 --agent enabled=1

# 🌐 9. IP dynamique (DHCP)
qm set 1001 --ipconfig0 ip=dhcp

# 🏷️ 10. Tag comme template Debian
qm set 1001 --tags "template,debian"

# 🧬 11. Convertir en template
qm template 1001

echo "✅ Template Cloud-Init Debian créé avec succès !"