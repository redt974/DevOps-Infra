#!/bin/bash

# Valeurs par défaut
ARCH_IP="172.16.70.141"
USERNAME="thib"
ARCH_USER="localadm"
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

# Vérifier si la clé SSH existe
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[*] Génération de la clé SSH..."
  ssh-keygen -b 4096 -t rsa -N '' -f "$SSH_KEY_PATH" < /dev/null
  chmod 600 "$SSH_KEY_PATH"
fi

# Copier la clé publique sur la VM Arch
echo "[*] Copier la clé publique sur la VM Arch..."
ssh-copy-id -i "$SSH_KEY_PATH.pub" "$ARCH_USER@$ARCH_IP"

# Vérifier la connexion SSH
echo "[*] Test de la connexion SSH à la VM Arch..."
ssh-add -D
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes "$ARCH_USER@$ARCH_IP" "echo Connexion réussie !"

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
ansible-playbook -i $INVENTORY_FILE arch-hardened/main.yml -u "$ARCH_USER" --private-key "$SSH_KEY_PATH"

# echo "[*] QR Codes MFA détectés :"
# echo "─────────────────────────────────────────────────────────────"
# for qrfile in "$HOME"/qrcodes/*_mfa_qr.png; do
#     if [[ -f "$qrfile" ]]; then
#         user=$(basename "$qrfile" | sed 's/_mfa_qr\.png$//')
#         echo "QR Code pour : $user"
#         xdg-open "$qrfile"
#         echo ">>> xdg-open \"$qrfile\""
#         echo "─────────────────────────────────────────────────────────────"
#     fi
# done

# echo "[*] Clés SSH privées détectées :"
# echo "─────────────────────────────────────────────────────────────"
# for keyfile in "$HOME"/.ssh/*_id_rsa; do
#     if [[ -f "$keyfile" && ! "$keyfile" =~ \.pub$ ]]; then
#         user=$(basename "$keyfile" | sed 's/_id_rsa$//')
#         echo "Clé SSH pour : $user"
#         ls -la "$keyfile"
#         echo
#         cat "$keyfile"
#         echo
#         echo ">>> cat \"$keyfile\""
#         echo
#         echo "Commande SSH suggérée :"
#         echo ">>> ssh -i \"$keyfile\" -p 22222 $user@$ARCH_IP"
#         echo "─────────────────────────────────────────────────────────────"
#     fi
# done