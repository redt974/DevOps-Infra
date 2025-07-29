#!/bin/bash

read -p "VM (ID): " VMID
if ! [[ $VMID =~ ^[0-9]+$ ]]; then
  echo "[*] L'ID de la VM doit être un nombre !"
  exit 1
fi

# Demande des variables avec validation
read -p "Adresse IP : " ip
if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[*] Adresse IP invalide !"
    exit 1
fi

read -p "Gateway : " gateway
if [[ ! $gateway =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[*] Gateway invalide !"
    exit 1
fi

# Fichier ISO
TEMPLATE_FILE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_STORAGE="local" # Stockage ISO dans Proxmox

# Mise à jour de Proxmox
echo "[*] Mise à jour de Proxmox..."
pveam update

# Vérifier si le template existe avant de le télécharger
if ! pveam list $TEMPLATE_STORAGE | grep -q "$TEMPLATE_FILE"; then
    echo "[*] Téléchargement du template Debian..."
    pveam download $TEMPLATE_STORAGE $TEMPLATE_FILE
fi

# Vérifier si la VM existe déjà
if pct list | awk '{print $1}' | grep -q "^$VMID$"; then
    echo "[*] Erreur : Une VM avec l'ID $VMID existe déjà !"
    exit 1
fi

# Création du conteneur
echo "[*] Création du conteneur LXC..."
pct create "$VMID" $TEMPLATE_STORAGE:vztmpl/$TEMPLATE_FILE \
    --hostname client \
    --storage local-lvm \
    --password password \
    --rootfs 2 \
    --cpuunits 1024 \
    --memory 512 \
    --net0 name=eth0,bridge=vmbr1,ip="$ip/24",gw="$gateway"

if [ $? -ne 0 ]; then
    echo "[*] Erreur lors de la création du conteneur."
    exit 1
fi

# Configuration du réseau sur Proxmox
echo "[*] Configuration du réseau sur Proxmox..."
if ! grep -q "iface vmbr1 inet static" /etc/network/interfaces; then
    echo -e "\nauto vmbr1\niface vmbr1 inet static\n\taddress $gateway/24\n\tbridge-ports none\n\tbridge-stp off\n\tbridge-fd 0" >> /etc/network/interfaces
    systemctl restart networking || systemctl restart systemd-networkd
fi

# Activation du NAT (rendu persistant)
echo "[*] Activation du NAT..."
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1
sysctl -p

iptables -t nat -A POSTROUTING -o vmbr0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

# Démarrage du conteneur
echo "[*] Démarrage du conteneur..."
pct start "$VMID"

sleep 5
if ! pct status "$VMID" | grep -q "running"; then
    echo "[*] Erreur : le conteneur ne s'est pas démarré correctement !"
    exit 1
fi

# Configuration de la VM
echo "[*] Mise à jour du système..."
pct exec "$VMID" -- apt update -y && apt upgrade -y

pct exec "$VMID" -- bash -c "echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen"
pct exec "$VMID" -- update-locale LANG=en_US.UTF-8

echo "[*] Installation des outils de sécurité..."
pct exec "$VMID" -- apt install -y ufw fail2ban apparmor apparmor-utils auditd unattended-upgrades apt-listchanges

echo "[*] Configuration des mises à jour automatiques..."
pct exec "$VMID" -- dpkg-reconfigure -plow unattended-upgrades

echo "[*] Sécurisation des utilisateurs..."
pct exec "$VMID" -- passwd -l root
echo "[*] Root désactivé."

echo "[*] Configuration des mots de passe expirables..."
pct exec "$VMID" -- sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
pct exec "$VMID" -- sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 10/' /etc/login.defs

echo "[*] Sécurisation de SSH..."
pct exec "$VMID" -- sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config
pct exec "$VMID" -- sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
pct exec "$VMID" -- sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
pct exec "$VMID" -- sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
pct exec "$VMID" -- systemctl restart ssh

echo "[*] Configuration du pare-feu UFW..."
pct exec "$VMID" -- ufw default deny incoming
pct exec "$VMID" -- ufw default allow outgoing
pct exec "$VMID" -- ufw allow 2222/tcp  # Port SSH
pct exec "$VMID" -- ufw enable

echo "[*] Activation de Fail2Ban..."
pct exec "$VMID" -- systemctl enable --now fail2ban

echo "[*] Désactivation des services inutiles..."
pct exec "$VMID" -- bash -c 'for service in avahi-daemon cups bluetooth; do systemctl disable --now $service 2>/dev/null; done'

echo "[*] Sécurisation du disque temporaire..."
pct exec "$VMID" -- bash -c 'echo "tmpfs /tmp tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab'
pct exec "$VMID" -- systemctl daemon-reload
pct exec "$VMID" -- mount -o remount /tmp || echo "Impossible de remonter /tmp"

echo "[*] Nettoyage du système..."
pct exec "$VMID" -- apt autoremove -y && apt autoclean -y

echo "[*] Sécurisation terminée ! Redémarrage recommandé."
pct exec "$VMID" -- systemctl reboot
