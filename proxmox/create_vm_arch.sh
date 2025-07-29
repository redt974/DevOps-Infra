#!/bin/bash

read -p "VM (ID): " VMID
if ! [[ $VMID =~ ^[0-9]+$ ]]; then
  echo "L'ID de la VM doit être un nombre !"
  exit 1
fi

# Fichier ISO
ISO_URL="https://geo.mirror.pkgbuild.com/iso/latest"
ISO_FILE="archlinux-2025.03.01-x86_64.iso"
ISO_STORAGE="local" # Proxmox ISO storage

# Paramètres de la VM
VMNAME="arch-linux"
ISO_PATH=$ISO_STORAGE:iso/$ISO_FILE
STORAGE="local-lvm" # Stockage principal
STORAGE_SECOND="local-lvm" # Peut être changé si nécessaire
BRIDGE="vmbr0"

# Ressources de la VM
RAM=2048
CORES=2
DISK_SIZE=20   # Disque principal en Go
DISK2_SIZE=10  # Disque secondaire en Go

# Télécharger l'iso
echo "[*] Vérification et téléchargement de l'ISO Arch Linux"
if ! pvesh get /nodes/$(hostname)/storage/$ISO_STORAGE/content | grep -q $ISO_FILE; then
  echo "[*] Téléchargement de $ISO_FILE..."
  wget -O /var/lib/vz/template/iso/$ISO_FILE $ISO_URL/$ISO_FILE
else
  echo "[*] ISO déjà présent"
fi

# Création de la VM avec le disque principal
echo "[*] Création de la VM $VMID : $VMNAME"
qm create $VMID \
  --name $VMNAME \
  --memory $RAM \
  --cores $CORES \
  --net0 virtio,bridge=$BRIDGE \
  --scsihw virtio-scsi-pci \
  --ostype l26 \
  --scsi0 $STORAGE:${DISK_SIZE} \
  --ide2 $ISO_PATH,media=cdrom \
  --boot "order=ide2;scsi0" \
  --vga std

if [ $? -ne 0 ]; then
  echo "❌ Erreur lors de la création de la VM !"
  exit 1
fi

# Ajout d'un second disque (exemple : /dev/sdb dans la VM)
echo "[*] Ajout du deuxième disque de ${DISK2_SIZE}G sur scsi1"
qm set $VMID --scsi1 $STORAGE_SECOND:${DISK2_SIZE}

if [ $? -ne 0 ]; then
  echo "❌ Erreur lors de l'ajout du deuxième disque !"
  exit 1
fi

# Désactiver la Virtualization KVM (optionnel selon ton besoin)
qm set $VMID --kvm 0

# Démarrage de la VM
echo "[*] Démarrage de la VM pour installation d'Arch Linux"
qm start $VMID

echo "✅ VM $VMID créée avec 2 disques :"
echo "   - Disque principal : ${DISK_SIZE}G"
echo "   - Deuxième disque  : ${DISK2_SIZE}G"
