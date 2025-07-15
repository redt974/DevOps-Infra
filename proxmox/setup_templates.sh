#!/usr/bin/env bash

# ========================================
# 🧱 Script générique pour créer un template Cloud-Init (Arch, Debian, Ubuntu)
# ========================================

set -euo pipefail

# === Configuration par OS ===
OS=${1:-""}
STORAGE="local-lvm"
BRIDGE="vmbr0"

case "$OS" in
  arch)
    TEMPLATE_ID=1002
    TEMPLATE_NAME="arch-cloud-template"
    IMAGE_URL="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
    IMAGE_FILE="archlinux-cloudimg.qcow2"
    TAGS="template,arch"
    ;;
  debian)
    TEMPLATE_ID=1001
    TEMPLATE_NAME="debian-cloud-template"
    IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    IMAGE_FILE="debian-12-genericcloud-amd64.qcow2"
    TAGS="template,debian"
    ;;
  ubuntu)
    TEMPLATE_ID=1000
    TEMPLATE_NAME="ubuntu-cloud-template"
    IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    IMAGE_FILE="ubuntu-22.04-cloudimg.img"
    TAGS="template,ubuntu"
    ;;
  *)
    echo "❌ Usage: $0 [arch|debian|ubuntu]"
    exit 1
    ;;
esac

echo "🚀 Création du template pour $OS..."

# === 1. Télécharger l'image si absente ===
cd /var/lib/vz/template/iso
if [[ ! -f "$IMAGE_FILE" ]]; then
  echo "⬇️ Téléchargement de l’image $OS..."
  wget "$IMAGE_URL" -O "$IMAGE_FILE"
else
  echo "✅ Image $IMAGE_FILE déjà présente"
fi

# === 2. Créer la VM vide ===
qm create $TEMPLATE_ID \
  --name "$TEMPLATE_NAME" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=$BRIDGE \
  --ostype l26

# === 3. Importer le disque ===
qm importdisk $TEMPLATE_ID "$IMAGE_FILE" $STORAGE

# === 4. Attacher le disque importé ===
qm set $TEMPLATE_ID --scsihw virtio-scsi-pci --scsi0 "$STORAGE:vm-${TEMPLATE_ID}-disk-0"

# === 5. Configurer le démarrage ===
qm set $TEMPLATE_ID --boot order=scsi0 --bootdisk scsi0

# === 6. Ajouter le disque Cloud-Init ===
qm set $TEMPLATE_ID --ide2 "$STORAGE:cloudinit,media=cdrom"

# === 7. Activer la console série ===
qm set $TEMPLATE_ID --serial0 socket --vga serial0

# === 8. Activer le guest agent ===
qm set $TEMPLATE_ID --agent enabled=1

# === 9. IP DHCP via Cloud-Init ===
qm set $TEMPLATE_ID --ipconfig0 ip=dhcp

# === 10. Ajouter les tags ===
qm set $TEMPLATE_ID --tags "$TAGS"

# === 11. Convertir en template ===
qm template $TEMPLATE_ID

echo "✅ Template $OS créé avec succès sous l'ID $TEMPLATE_ID"