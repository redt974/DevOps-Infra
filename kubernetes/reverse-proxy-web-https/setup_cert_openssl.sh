#!/usr/bin/env bash

set -e

# Variables personnalisables
DOMAIN="minikube.local"  # ou "site1.local", "minikube.local", etc.
IP="192.168.49.2"   # IP de minikube
CERT_DIR="./setup_cert_openssl"

CA_KEY="$CERT_DIR/ca.key"
CA_CERT="$CERT_DIR/ca.crt"
SERVER_KEY="$CERT_DIR/server.key"
SERVER_CSR="$CERT_DIR/server.csr"
SERVER_CERT="$CERT_DIR/server.crt"
CERT_SERIAL="$CERT_DIR/ca.srl"

echo "📁 Création du dossier de certificats : $CERT_DIR"
mkdir -p "$CERT_DIR"

echo "🔐 Génération de la clé de la CA..."
openssl genrsa -out "$CA_KEY" 2048

echo "📜 Génération du certificat de la CA..."
openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 365 \
  -subj "/C=FR/ST=France/L=Paris/O=Kube/CN=MyCA" \
  -out "$CA_CERT"

echo "🔑 Génération de la clé privée pour le serveur..."
openssl genrsa -out "$SERVER_KEY" 2048

echo "📄 Génération de la CSR..."
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" \
  -subj "/C=FR/ST=France/L=Paris/O=Kube/CN=$DOMAIN"

echo "📜 Création du certificat serveur signé avec la CA..."
openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$SERVER_CERT" -days 365 -sha256 \
  -extfile <(echo "subjectAltName=DNS:$DOMAIN,IP:$IP")

echo "✅ Certificats générés :"
ls -l "$CERT_DIR"
