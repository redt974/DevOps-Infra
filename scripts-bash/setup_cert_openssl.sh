#!/usr/bin/env bash
set -e

# === CONFIGURATION DE BASE ===
DOMAIN="app.local"         # Nom du domaine local
IP="127.0.0.1"             # Adresse IP locale
CERT_DIR="./certs_ssl"     # Dossier de sortie
DAYS_VALID=365             # Durée de validité (jours)

# === FICHIERS ===
CA_KEY="$CERT_DIR/ca.key"
CA_CERT="$CERT_DIR/ca.crt"
SERVER_KEY="$CERT_DIR/$DOMAIN.key"
SERVER_CSR="$CERT_DIR/$DOMAIN.csr"
SERVER_CERT="$CERT_DIR/$DOMAIN.crt"
SERIAL_FILE="$CERT_DIR/ca.srl"

# === PRÉPARATION ===
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "🔐 Génération de la clé de la CA..."
openssl genrsa -out "$CA_KEY" 2048

echo "📜 Génération du certificat racine (CA)..."
openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days $DAYS_VALID \
  -subj "/C=FR/ST=France/L=Paris/O=DevLocal/CN=DevLocal CA" \
  -out "$CA_CERT"

echo "🔑 Génération de la clé privée pour $DOMAIN..."
openssl genrsa -out "$SERVER_KEY" 2048

echo "📄 Génération du CSR..."
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" \
  -subj "/C=FR/ST=France/L=Paris/O=DevLocal/CN=$DOMAIN"

echo "🧾 Signature du certificat serveur..."
openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$SERVER_CERT" -days $DAYS_VALID -sha256 \
  -extfile <(echo "subjectAltName=DNS:$DOMAIN,IP:$IP")

echo "🧹 Nettoyage"
mv $CA_CERT $SERVER_KEY $SERVER_CERT ../
cd .. && rm -rf "$CERT_DIR"

echo "✅ Certificats générés avec succès dans : $CERT_DIR"
echo
echo "📜 Fichiers importants :"
echo " - Autorité (CA) : $CA_CERT"
echo " - Clé serveur : $SERVER_KEY"
echo " - Certificat serveur : $SERVER_CERT"
echo
echo "👉 Ajoute $DOMAIN dans ton /etc/hosts :"
echo "    $IP    $DOMAIN"
echo
echo "⚠️ Pour éviter les avertissements, importe $CA_CERT dans le magasin de certificats de ton OS."