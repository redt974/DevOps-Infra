#!/bin/bash

# Valeurs par défaut
VM_IP="172.16.70.141"
USERNAME="thib"
VM_USER="localadm"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
INVENTORY_FILE="serveurs/inventory"

# Demander les informations à l'utilisateur (avec valeurs par défaut)
read -p "Entrez le nom d'utilisateur actuel [$USERNAME]: " user
USERNAME=${user:-$USERNAME}

read -p "Entrez le nom d'utilisateur serveur [$VM_USER]: " user_vm
VM_USER=${user_vm:-$VM_USER}

read -p "Entrez l'IP de la VM serveur [$VM_IP]: " user_ip
VM_IP=${user_ip:-$VM_IP}

read -p "Entrez le chemin de la clé SSH privée [$SSH_KEY_PATH]: " key_path
SSH_KEY_PATH=${key_path:-$SSH_KEY_PATH}

# Vérifier si la clé SSH existe
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[*] Génération de la clé SSH..."
  ssh-keygen -b 4096 -t rsa -N '' -f "$SSH_KEY_PATH" < /dev/null
  chmod 600 "$SSH_KEY_PATH"
fi

# Copier la clé publique sur la VM serveur
echo "[*] Copier la clé publique sur la VM serveur..."
ssh-copy-id -i "$SSH_KEY_PATH.pub" "$VM_USER@$VM_IP"

# Vérifier la connexion SSH
echo "[*] Test de la connexion SSH à la VM serveur..."
ssh-add -D
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes "$VM_USER@$VM_IP" "echo Connexion réussie !"

# Créer ou éditer le fichier d'inventaire dynamiquement
echo "[*] Création ou mise à jour du fichier d'inventaire..."
rm -f $INVENTORY_FILE
cat > $INVENTORY_FILE <<EOL
[serveur-vm]
$VM_IP ansible_user=$VM_USER ansible_ssh_private_key_file=$SSH_KEY_PATH ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes'

[serveur-vm:vars]
ansible_python_interpreter=/usr/bin/python3
EOL

# Exécution du playbook Ansible
echo "[*] Exécution du playbook Ansible..."
ansible-playbook -i $INVENTORY_FILE serveurs/main.yml -u "$VM_USER" --private-key "$SSH_KEY_PATH"