#!/usr/bin/env bash
set -e

# Variables principales
PVE_HOSTNAME="proxmox.local"
PVE_IP="192.168.10.180"
CA_KEY="certificat_ca.key"
CA_CERT="certificat_ca.crt"
SERVER_KEY="serveur_ca.key"
SERVER_CSR="serveur_ca.csr"
SERVER_CERT="serveur_ca.crt"
CERT_SERIAL="certificat_ca.srl"
SSH_KEY_PATH="$HOME/.ssh/proxmox_root_id_rsa"  # chemin de la clé privée Proxmox

# Demande utilisateur
echo "👤 Utilisateur de connexion Proxmox (root ou user sudo)"
read -p "Nom d'utilisateur : " USER_PROXMOX

# Vérification clé SSH
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "⚠️  Clé SSH Proxmox introuvable à : $SSH_KEY_PATH"
    echo "Veuillez copier votre clé privée depuis Windows, par exemple :"
    echo "scp C:\\Users\\<toi>\\.ssh\\proxmox-devops\\"$USER_PROXMOX"_id_rsa $(whoami)@$(hostname -I | awk '{print $1}'):$SSH_KEY_PATH"
    echo
    read -p "Appuie sur Entrée quand c’est fait..."
fi
chmod 600 "$SSH_KEY_PATH"

echo "🔧 Configuration du hostname et du fichier hosts..."
sudo tee /etc/hosts <<EOF
$PVE_IP $PVE_HOSTNAME
EOF

echo "📁 Création d'un dossier de travail : ./certs_openssl"
mkdir -p certs_openssl
cd certs_openssl

echo "🔐 Génération de la clé de la CA..."
openssl genrsa -out "$CA_KEY" 2048

echo "📜 Génération du certificat de la CA..."
openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 365 \
  -subj "/C=FR/ST=France/L=Paris/O=Perso/CN=$PVE_HOSTNAME CA" \
  -out "$CA_CERT"

echo "🔑 Génération de la clé privée pour le serveur..."
openssl genrsa -out "$SERVER_KEY" 2048

echo "📄 Génération de la CSR..."
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" \
  -subj "/C=FR/ST=France/L=Paris/O=Proxmox/CN=$PVE_HOSTNAME"

echo "📜 Création du certificat serveur signé avec la CA..."
openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$SERVER_CERT" -days 365 -sha256 \
  -extfile <(echo "subjectAltName=DNS:$PVE_HOSTNAME,DNS:www.$PVE_HOSTNAME,IP:$PVE_IP")

# 🧩 Copie des certificats vers Proxmox
echo "📂 Copie des certificats vers Proxmox ($PVE_IP)..."
scp -i "$SSH_KEY_PATH" "$SERVER_CERT" "$USER_PROXMOX@$PVE_IP:/tmp/"
scp -i "$SSH_KEY_PATH" "$SERVER_KEY" "$USER_PROXMOX@$PVE_IP:/tmp/"

# ⚙️ Application sur Proxmox
if [ "$USER_PROXMOX" == "root" ]; then
    ssh -i "$SSH_KEY_PATH" "$USER_PROXMOX@$PVE_IP" "cp /tmp/$SERVER_CERT /etc/pve/local/pve-ssl.pem && cp /tmp/$SERVER_KEY /etc/pve/local/pve-ssl.key && chown root:root /etc/pve/local/pve-ssl.* && chmod 644 /etc/pve/local/pve-ssl.*"
else
    ssh -i "$SSH_KEY_PATH" "$USER_PROXMOX@$PVE_IP" "sudo cp /tmp/$SERVER_CERT /etc/pve/local/pve-ssl.pem && sudo cp /tmp/$SERVER_KEY /etc/pve/local/pve-ssl.key && sudo chown root:root /etc/pve/local/pve-ssl.* && sudo chmod 644 /etc/pve/local/pve-ssl.*"
fi

# 🔄 Redémarrage du service pveproxy
if [ "$USER_PROXMOX" == "root" ]; then
    ssh -i "$SSH_KEY_PATH" "$USER_PROXMOX@$PVE_IP" "systemctl restart pveproxy"
else
    ssh -i "$SSH_KEY_PATH" "$USER_PROXMOX@$PVE_IP" "sudo systemctl restart pveproxy"
fi

echo "✅ Configuration terminée avec succès !"
echo "📁 Les certificats sont disponibles dans le dossier : $(pwd)"
echo "📜 Le certificat CA est : $CA_CERT"
echo "🔗 Accès à Proxmox : https://$PVE_HOSTNAME:8006"