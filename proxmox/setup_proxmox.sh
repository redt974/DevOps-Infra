#!/usr/bin/env bash

set -e  # Arrêter si une commande échoue
set -u  # Erreur si variable non définie

# Variables
IP_PROXMOX="192.168.10.180"
CN_PROXMOX="proxmox.local"

passwd

# ================================================
# ⚙️ 1. Configuration système et réseau
# ================================================
export DEBIAN_FRONTEND=noninteractive

# 🖥️ /etc/hosts - Personnaliser si nécessaire
cat > /etc/hosts << EOF
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
$IP_PROXMOX  $CN_PROXMOX pve
EOF

# 🔧 Configuration réseau et forwarding
cat > /etc/sysctl.d/proxmox.conf << EOF
net.ipv4.conf.all.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.ip_forward=1
EOF

sysctl -p /etc/sysctl.d/proxmox.conf

# 🔌 Configuration bridge (à adapter si besoin)
cat > /etc/network/interfaces << EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto ens33
iface ens33 inet dhcp
        dns-nameserver 1.1.1.1
        dns-nameserver 8.8.8.8
        pre-up sleep 2

iface ens33 inet manual

auto vmbr0
iface vmbr0 inet static
        address $IP_PROXMOX/24
        gateway 192.168.10.2
        bridge-ports ens33
        bridge-stp off
        bridge-fd 0
EOF

# ================================================
# 📦 2. Installation des paquets Proxmox & outils
# ================================================

# 💡 Décommenter les lignes si existantes (manuel)
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list 2>/dev/null || true

# 🧱 Dépôts PVE (no-subscription)
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

apt update -y && apt full-upgrade -y
apt install -y proxmox-ve ksm-control-daemon locales-all chrony libguestfs-tools sudo vim lsb-release tree

# ================================================
# 🔐 3. Préparation accès API sécurisé pour Terraform
# ================================================

# 🧑‍💼 Création utilisateur & token

echo "ℹ️ Création de l'utilisateur terraform@pve et du token terraform-token pour l'accès API."
pveum role add TerraformProv -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-user@pve --comment "Terraform user" --password password
pveum aclmod / -user terraform-user@pve -role TerraformProv
pveum user token add terraform-user@pve terraform-token --expire 0 --privsep 0 --comment "Token for Terraform"

echo "✅ Utilisateur terraform@pve et token créés pour l'accès API Terraform"

# 🔧 Nettoyage de noyaux inutiles
apt remove -y linux-image-amd64 'linux-image-6.1*' os-prober

echo "🛠️ Activation du type 'snippets' pour le datastore 'local'..."

# Ajoute 'snippets' comme type de contenu autorisé sur 'local'
pvesm set local --content iso,vztmpl,backup,images,rootdir,snippets

# Crée le dossier des snippets s’il n’existe pas
mkdir -p /var/lib/vz/snippets

echo "✅ Le type 'snippets' est maintenant activé pour 'local'."

# ================================================
# 👤 4. Création d'un utilisateur admin non-root
# ================================================

read -p "Nom d'utilisateur : " USER
echo "[*] Saisie du mot de passe pour $USER"
read -s -p "Mot de passe : " PASSWORD; echo
read -s -p "Confirme le mot de passe : " PASSWORD_CONFIRM; echo
[[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]] && { echo "❌ Les mots de passe ne correspondent pas."; exit 1; }

echo "👤 Création de l'utilisateur '$USER'..."
useradd -m -s /bin/bash "$USER"
echo "$USER:$PASSWORD" | chpasswd
usermod -aG sudo "$USER"

# 🔒 Désactiver le mot de passe de root via shadow
echo "🚫 Désactivation stricte de l'accès root..."
sed -i 's/^root:[^:]*:/root:!*:/' /etc/shadow

# 🔐 Autoriser login SSH avec clé (ou mot de passe temporairement)
mkdir -p /home/$USER/.ssh
cp /root/.ssh/authorized_keys /home/$USER/.ssh/authorized_keys 2>/dev/null || true
chown -R $USER:$USER /home/$USER/.ssh
chmod 700 /home/$USER/.ssh
chmod 600 /home/$USER/.ssh/authorized_keys

# 🔒 Désactivation du login SSH root
echo "🚫 Désactivation du login SSH root..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

echo "✅ Utilisateur '$USER' créé et root désactivé pour SSH."

# ================================================
# 🧱 5. (Optionnel) Création d’un template Cloud-Init
# ================================================

echo "ℹ️ Tu peux maintenant créer un template cloud-init avec Debian ou Ubuntu."

# Exemple Debian :
# 1. Créer une VM minimaliste avec un ISO Debian 12.
# 2. Installer : sudo apt install cloud-init qemu-guest-agent sudo
# 3. Configurer cloud-init et clean : cloud-init clean && poweroff
# 4. Puis depuis Proxmox :
# qm set <VMID> --ide2 local-lvm:cloudinit
# qm set <VMID> --boot order=scsi0
# qm set <VMID> --serial0 socket --vga serial0
# qm set <VMID> --agent enabled=1
# qm template <VMID>

# Ou via image cloud :
# 1. Télécharger l’image Ubuntu Cloud
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O ubuntu-22.04-cloudimg.img

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

reboot