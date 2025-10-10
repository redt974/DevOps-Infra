#!/bin/bash

read -p "VM (ID): " VMID
if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
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
TEMPLATE_FILE="archlinux-base_20240911-1_amd64.tar.zst"
TEMPLATE_STORAGE="local" # Stockage ISO dans Proxmox
USER_NAME=arch
CONTENEUR_SSH_KEY="$HOME/.ssh/conteneur-$USER_NAME.local_id_rsa"

# Mise à jour de Proxmox
echo "[*] Mise à jour de Proxmox..."
pveam update

# Vérifier si le template existe avant de le télécharger
if ! pveam list $TEMPLATE_STORAGE | grep -q "$TEMPLATE_FILE"; then
    echo "[*] Téléchargement du template Arch..."
    pveam download $TEMPLATE_STORAGE $TEMPLATE_FILE
fi

# Vérifier si la VM existe déjà
if pct list | awk '{print $1}' | grep -q "^$VMID$"; then
    echo "[*] Erreur : Une VM avec l'ID "$VMID" existe déjà !"
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
    --net0 name=eth0,bridge=vmbr0,ip="$ip/24",gw="$gateway"

if [ $? -ne 0 ]; then
    echo "[*] Erreur lors de la création du conteneur."
    exit 1
fi

# Démarrage du conteneur
echo "[*] Démarrage du conteneur..."
pct start "$VMID"

sleep 5
if ! pct status "$VMID" | grep -q "running"; then
    echo "[*] Erreur : le conteneur ne s'est pas démarré correctement !"
    exit 1
fi

# Génération de la clé SSH ↔ Proxmox
echo "[*] Vérification / génération de la clé SSH..."
if [ ! -f "$CONTENEUR_SSH_KEY" ]; then
  ssh-keygen -t rsa -b 4096 -N '' -f "$CONTENEUR_SSH_KEY" -C "$USER_NAME@$(hostname)"
  echo "[*] Clé SSH générée : $CONTENEUR_SSH_KEY"
else
  echo "[*] Clé SSH déjà existante : $CONTENEUR_SSH_KEY"
fi

# Configuration de la VM
pct exec "$VMID" -- ip link set eth0 up
pct exec "$VMID" -- ip addr add $ip/24 dev eth0
pct exec "$VMID" -- ip route add default via $gateway

echo "[*] Mise à jour du système..."
pct exec "$VMID" -- pacman-key --init
pct exec "$VMID" -- pacman-key --populate archlinux
pct exec "$VMID" -- pacman -Syu --noconfirm

echo "[*] Installation des paquets essentiels..."
pct exec "$VMID" -- pacman -Sy --noconfirm sudo openssh

echo "[*] Configuration de la locale..."
pct exec "$VMID" -- bash -c "echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen"
pct exec "$VMID" -- bash -c "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"

echo "[*] Configuration du groupe sudo..."
pct exec "$VMID" -- grep -q '^%wheel' /etc/sudoers || echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers

echo "[*] Création de l'utilisateur $USER_NAME non-root avec sudo sans mot de passe..."
if ! pct exec "$VMID" -- id "$USER_NAME" &>/dev/null; then
    pct exec "$VMID" -- useradd -m -s /bin/bash -G wheel $USER_NAME
    pct exec "$VMID" -- bash -c "mkdir -p /etc/sudoers.d && echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER_NAME && chmod 440 /etc/sudoers.d/$USER_NAME"
fi

echo "[*] Copie de la clé publique SSH de Proxmox dans le conteneur..."
pct exec "$VMID" -- mkdir -p /home/$USER_NAME/.ssh
pct push "$VMID" "$CONTENEUR_SSH_KEY.pub" /home/$USER_NAME/.ssh/authorized_keys

pct exec "$VMID" -- chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
pct exec "$VMID" -- chmod 700 /home/$USER_NAME/.ssh
pct exec "$VMID" -- chmod 600 /home/$USER_NAME/.ssh/authorized_keys

echo "[*] Sécurisation des utilisateurs..."
pct exec "$VMID" -- passwd -l root
echo "[*] Root désactivé."

echo "[*] Sécurisation de SSH..."
pct exec "$VMID" -- sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config
pct exec "$VMID" -- sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
pct exec "$VMID" -- sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
pct exec "$VMID" -- sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
pct exec "$VMID" -- systemctl enable --now sshd
pct exec "$VMID" -- systemctl start sshd
sleep 2

echo "[*] Installation et configuration de UFW..."
pct exec "$VMID" -- pacman -Sy --noconfirm ufw
pct exec "$VMID" -- ufw default deny incoming
pct exec "$VMID" -- ufw default allow outgoing
pct exec "$VMID" -- ufw allow 2222/tcp
pct exec "$VMID" -- systemctl enable --now ufw

echo "[*] Activation de Fail2Ban..."
pct exec "$VMID" -- pacman -Sy --noconfirm fail2ban
pct exec "$VMID" -- systemctl enable --now fail2ban

echo "[*] Désactivation des services inutiles..."
pct exec "$VMID" -- systemctl disable --now avahi-daemon.service || true
pct exec "$VMID" -- systemctl disable --now cups.service || true
pct exec "$VMID" -- systemctl disable --now bluetooth.service || true

echo "[*] Nettoyage du système..."
pct exec "$VMID" -- bash -c "pacman -Rns --noconfirm \$(pacman -Qdtq || true)"
pct exec "$VMID" -- pacman -Scc --noconfirm

echo "[*] Sécurisation terminée ! Redémarrage recommandé via Proxmox."
pct reboot "$VMID"

# Configuration réseau si eth0 est down
pct exec "$VMID" -- ip link set eth0 up
pct exec "$VMID" -- ip addr add $ip/24 dev eth0
pct exec "$VMID" -- ip route add default via $gateway

pct exec "$VMID" -- systemctl restart sshd
echo "Connexion SSH : ssh -p 2222 -i "$CONTENEUR_SSH_KEY" $USER_NAME@$ip"