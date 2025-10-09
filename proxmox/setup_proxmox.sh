#!/usr/bin/env bash

set -e  # Stop si une commande échoue
set -u  # Stop si variable non définie

# Variables
IP_PROXMOX="192.168.10.180"
IP_GATEWAY="192.168.10.2"
INTERFACE="ens33"
CN_PROXMOX="proxmox.local"

# ================================================
# ⚙️ 1. Configuration système et réseau
# ================================================
export DEBIAN_FRONTEND=noninteractive

# 🖥️ /etc/hosts - Ajouter proprement l'entrée Proxmox
if ! grep -q "$CN_PROXMOX" /etc/hosts; then
    echo "$IP_PROXMOX  $CN_PROXMOX pve" >> /etc/hosts
fi

# Vérification que le hostname est correct
CURRENT_HOSTNAME=$(hostname -f || true)
if [ "$CURRENT_HOSTNAME" != "$CN_PROXMOX" ]; then
    echo "$CN_PROXMOX" > /etc/hostname
    hostnamectl set-hostname "$CN_PROXMOX"
fi

# 🔧 Configuration sysctl (sécurisée)
cat > /etc/sysctl.d/proxmox.conf << EOF
net.ipv4.conf.all.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.ip_forward=1
EOF

sysctl --system

# 🔌 Configuration réseau (backup + écriture propre)
cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%F_%H-%M-%S)

cat > /etc/network/interfaces << EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Interface physique en mode "manual"
allow-hotplug $INTERFACE
iface $INTERFACE inet manual

# Bridge principal
auto vmbr0
iface vmbr0 inet static
        address $IP_PROXMOX/24
        gateway $IP_GATEWAY
        bridge-ports $INTERFACE
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

echo "🛠️ Activation du type 'snippets' pour le datastore 'local'..."

# Ajoute 'snippets' comme type de contenu autorisé sur 'local'
pvesm set local --content iso,vztmpl,backup,images,rootdir,snippets

# Crée le dossier des snippets s’il n’existe pas
mkdir -p /var/lib/vz/snippets

echo "✅ Le type 'snippets' est maintenant activé pour 'local'."

# ================================================
# 👤 4. Création d'un utilisateur admin non-root
# ================================================

echo "ℹ️ Création d'un utilisateur admin non-root pour l'accès SSH et l'interface web."
echo "⚠️ L'accès SSH direct au compte root sera désactivé."

read -p "Nom d'utilisateur : " USER
echo "[*] Saisie du mot de passe pour $USER"
read -s -p "Mot de passe : " PASSWORD; echo
read -s -p "Confirme le mot de passe : " PASSWORD_CONFIRM; echo
[[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]] && { echo "❌ Les mots de passe ne correspondent pas."; exit 1; }

echo "👤 Création de l'utilisateur '$USER'..."
useradd -m -s /bin/bash "$USER"
echo "$USER:$PASSWORD" | chpasswd
usermod -aG sudo "$USER"

pveum user add $USER@pam
pveum aclmod / -user $USER@pam -role PVEAdmin

# ================================================
# 🔑 5. Génération des clés SSH root et $USER
# ================================================

echo "🔑 Génération de clés SSH pour root et $USER ..."

# Génération clé root
if [ ! -f /root/.ssh/id_rsa ]; then
    mkdir -p /root/.ssh
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
else
    echo "La clé SSH root existe déjà, pas de régénération."
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

echo "⚠️ IMPORTANT : Note la clé privée root ci-dessous (à garder précieusement) !"
echo "✅ Clé SSH privée root :"
echo "----------------------------------------"
sudo cat /root/.ssh/id_rsa | sed 's/^/    /'
echo "----------------------------------------"

# Génération clé utilisateur non-admin
if [ ! -f /home/$USER/.ssh/id_rsa ]; then
    sudo -u $USER ssh-keygen -t rsa -b 4096 -f /home/$USER/.ssh/id_rsa -N ""
    cat /home/$USER/.ssh/id_rsa.pub >> /home/$USER/.ssh/authorized_keys

    echo "⚠️ IMPORTANT : Note la clé privée pour $USER ci-dessous (à garder précieusement) !"
    echo "✅ Clé SSH privée pour $USER :"
    echo "----------------------------------------"
    sudo cat /home/$USER/.ssh/id_rsa | sed 's/^/    /'
    echo "----------------------------------------"
fi

chown -R $USER:$USER /home/$USER/.ssh
chmod 700 /home/$USER/.ssh
chmod 600 /home/$USER/.ssh/authorized_keys

echo "✅ Clés SSH générées et installées."

# 🔒 Sécurisation SSH : uniquement clé publique
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?UsePAM .*/UsePAM yes/' /etc/ssh/sshd_config
systemctl restart sshd

# ⚡ Autoriser sudo sans mot de passe pour $USER
echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER
chmod 440 /etc/sudoers.d/$USER

echo "✅ Utilisateur '$USER' créé et root désactivé pour SSH."

# ================================================
# 🧱 6. (Optionnel) Création d’un template Cloud-Init
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

read -p "Appuie sur Entrée pour redémarrer..." _
reboot