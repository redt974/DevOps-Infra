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
scp "$SERVER_CERT" root@"$PVE_IP":/etc/pve/local/pve-ssl.pem
scp "$SERVER_KEY" root@"$PVE_IP":/etc/pve/local/pve-ssl.key

echo "🔄 Redémarrage du service pveproxy sur Proxmox..."
ssh root@"$PVE_IP" systemctl restart pveproxy

# Installer la CA dans Firefox (Debian)
FIREFOX_PROFILE_PATH=$(find ~/.mozilla/firefox -maxdepth 1 -type d -name "*.default*" | head -n 1)

sudo apt-get install -y libnss3-tools

if [ -n "$FIREFOX_PROFILE_PATH" ]; then
    echo "🦊 Importation de la CA dans Firefox : $FIREFOX_PROFILE_PATH"

    certutil -A -n "Proxmox Local CA" \
        -t "CT,C,C" \
        -i "$CA_CERT" \
        -d sql:"$FIREFOX_PROFILE_PATH"

    echo "✅ CA ajoutée à Firefox avec succès. Redémarre Firefox."
else
    echo "⚠️ Impossible de détecter le profil Firefox. Fichier CA généré : $CA_CERT"
fi

echo "✅ Configuration terminée avec succès !"
echo "📁 Les certificats sont disponibles dans le dossier : $(pwd)"
echo "📜 Le certificat CA est : $CA_CERT est à mettre manuellement dans Firefox :"
echo " -> about:preferences > Tapez 'certificats' dans la barre de recherche > Gérer les certificats > Autorités > Importer"
echo " -> Sélectionnez le fichier CA : $CA_CERT et cochez 'Faire confiance à cette autorité pour identifier les sites web'."
echo "🔗 Pour accéder à Proxmox, utilisez l'URL : https://$PVE_HOSTNAME:8006"