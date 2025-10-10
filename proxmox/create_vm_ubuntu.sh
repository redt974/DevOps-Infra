#!/bin/bash

read -p "VM (ID): " VMID
if ! [[ $VMID =~ ^[0-9]+$ ]]; then
  echo "L'ID de la VM doit être un nombre !"
  exit 1
fi

# Fichier ISO
ISO_URL="https://mirror.tutosfaciles48.fr/ubuntu/24.04.3"
ISO_FILE="ubuntu-24.04.3-desktop-amd64.iso"
ISO_STORAGE="local" # Proxmox ISO storage

# Paramètres de la VM
VMNAME="client"
ISO_PATH=$ISO_STORAGE:iso/$ISO_FILE
STORAGE="local-lvm"
BRIDGE="vmbr0"

# Ressources de la VM
RAM=2048 
CORES=2
DISK_SIZE=20

# Télécharger l'iso
echo "[*] Vérification et téléchargement de l'ISO Ubuntu Linux"
if ! pvesh get /nodes/$(hostname)/storage/$ISO_STORAGE/content | grep -q $ISO_FILE; then
  echo "[*] Téléchargement de $ISO_FILE..."
  wget -O /var/lib/vz/template/iso/$ISO_FILE $ISO_URL/$ISO_FILE
else
  echo "[*] ISO déjà présent"
fi

echo "[*] Création de la VM $VMID : $VMNAME"
qm create $VMID \
  --name $VMNAME \
  --memory $RAM \
  --cores $CORES \
  --net0 virtio,bridge=$BRIDGE \
  --scsihw virtio-scsi-pci \
  --ostype l26 \
  --scsi0 $STORAGE:$DISK_SIZE \
  --ide2 $ISO_PATH,media=cdrom \
  --boot "order=ide2;scsi0" \
  --vga std 
 
if [ $? -ne 0 ]; then
  echo "Erreur lors de la création de la VM !"
  exit 1
fi

# Désactiver la Virtualization KVM
qm set $VMID --kvm 0

# Démarrage de la VM (installation manuelle de Ubuntu + cloud-init inside)
echo "[*] Démarrage de la VM pour installation de Ubuntu Linux"
qm start $VMID