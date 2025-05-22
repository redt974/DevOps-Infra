#!/bin/bash

# Valeurs par défaut
ARCH_IP="172.16.70.136"
USERNAME="thib"
ARCH_USER="root"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
INVENTORY_FILE="arch-install/inventory"

# Demander les informations à l'utilisateur (avec valeurs par défaut)
read -p "Entrez le nom d'utilisateur actuel [$USERNAME]: " user
USERNAME=${user:-$USERNAME}

read -p "Entrez le nom d'utilisateur Arch [$ARCH_USER]: " user_arch
ARCH_USER=${user_arch:-$ARCH_USER}

read -p "Entrez l'IP de la VM Arch [$ARCH_IP]: " user_ip
ARCH_IP=${user_ip:-$ARCH_IP}

read -p "Entrez le chemin de la clé SSH privée [$SSH_KEY_PATH]: " key_path
SSH_KEY_PATH=${key_path:-$SSH_KEY_PATH}

# Vérifier si la clé SSH existe, et la supprimer si nécessaire
if [ -f "$SSH_KEY_PATH" ]; then
  echo "[*] La clé SSH existe déjà. Suppression de l'ancienne clé..."
  rm -f "$SSH_KEY_PATH"
  rm -f "$SSH_KEY_PATH.pub"
fi

# Vérifier si la clé SSH existe
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[*] Génération de la clé SSH..."
  ssh-keygen -b 4096 -t rsa -N '' -f "$SSH_KEY_PATH" < /dev/null
  chmod 600 "$SSH_KEY_PATH"
fi

# Copier la clé publique sur la VM Arch
echo "[*] Copier la clé publique sur la VM Arch..."
ssh-copy-id -i "$SSH_KEY_PATH.pub" -o IdentitiesOnly=yes "$ARCH_USER@$ARCH_IP"

# Vérifier la connexion SSH
echo "[*] Test de la connexion SSH à la VM Arch..."
ssh-add -D
ssh -i "$SSH_KEY_PATH" "$ARCH_USER@$ARCH_IP" "echo Connexion réussie !"

# Créer ou éditer le fichier d'inventaire dynamiquement
echo "[*] Création ou mise à jour du fichier d'inventaire..."
cat > $INVENTORY_FILE <<EOL
[arch-vm]
$ARCH_IP ansible_user=$ARCH_USER ansible_ssh_private_key_file=$SSH_KEY_PATH ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes'

[arch-vm:vars]
ansible_python_interpreter=/usr/bin/python3
EOL

# Exécution du playbook Ansible
echo "[*] Exécution du playbook Ansible..."
ansible-playbook -i $INVENTORY_FILE arch-install/main.yml -u "$ARCH_USER" --private-key "$SSH_KEY_PATH
