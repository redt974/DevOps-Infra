#!/usr/bin/env bash

set -e

# Variables
PVE_HOSTNAME="proxmox.local"
PVE_IP="192.168.10.180"
CA_KEY="certificat_ca.key"
CA_CERT="certificat_ca.crt"
SERVER_KEY="serveur_ca.key"
SERVER_CSR="serveur_ca.csr"
SERVER_CERT="serveur_ca.crt"
CERT_SERIAL="certificat_ca.srl"

echo "👤 Utilisateur admin non-root de la Proxmox"
read -p "Nom d'utilisateur : " USER_PROXMOX

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

echo "📂 Copie des certificats vers Proxmox ($PVE_IP)..."
ssh "$USER_PROXMOX"@"$PVE_IP" "sudo cp /tmp/"$SERVER_CERT" /etc/pve/local/pve-ssl.pem && sudo chown root:root /etc/pve/local/pve-ssl.pem && sudo chmod 644 /etc/pve/local/pve-ssl.pem"
ssh "$USER_PROXMOX"@"$PVE_IP" "sudo cp /tmp/"$SERVER_KEY" /etc/pve/local/pve-ssl.key && sudo chown root:root /etc/pve/local/pve-ssl.key && sudo chmod 644 /etc/pve/local/pve-ssl.key"
# scp "$SERVER_CERT" "$USER_PROXMOX"@"$PVE_IP":/etc/pve/local/pve-ssl.pem
# scp "$SERVER_KEY" "$USER_PROXMOX"@"$PVE_IP":/etc/pve/local/pve-ssl.key

echo "🔄 Redémarrage du service pveproxy sur Proxmox..."
ssh "$USER_PROXMOX"@"$PVE_IP" systemctl restart pveproxy

echo "✅ Configuration terminée avec succès !"
echo "📁 Les certificats sont disponibles dans le dossier : $(pwd)"
echo "📜 Le certificat CA est : $CA_CERT est à mettre manuellement dans Firefox :"
echo " -> about:preferences > Tapez 'certificats' dans la barre de recherche > Gérer les certificats > Autorités > Importer"
echo " -> Sélectionnez le fichier CA : $CA_CERT et cochez 'Faire confiance à cette autorité pour identifier les sites web'."
echo "🔗 Pour accéder à Proxmox, utilisez l'URL : https://$PVE_HOSTNAME:8006"