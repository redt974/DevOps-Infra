#!/bin/bash

# Configuration
TF_SSH_KEY="$HOME/.ssh/id_rsa_terraform"
PROXMOX_USER="root"
PROXMOX_HOST="192.168.10.180"

# 2. Générer la clé SSH pour Terraform (connexion Proxmox)
echo "🔐 Génération clé SSH pour Terraform <=> Proxmox..."
ssh-keygen -t rsa -b 4096 -N '' -f "$TF_SSH_KEY" -C "terraform key"

# 3. Copie automatique sur Proxmox (si accessible)
echo "📤 Copie de la clé publique sur $PROXMOX_HOST..."
if ssh -o ConnectTimeout=3 "$PROXMOX_USER@$PROXMOX_HOST" 'exit' 2>/dev/null; then
  ssh-copy-id -i "$TF_SSH_KEY.pub" "$PROXMOX_USER@$PROXMOX_HOST"
else
  echo "⚠️ Proxmox non joignable. Copie manuelle nécessaire."
  echo "➡️ Connectez-vous et collez le contenu suivant dans ~/.ssh/authorized_keys sur Proxmox :"
  cat "$TF_SSH_KEY.pub"
fi

# 4. Permissions SSH (utile en cas de copie manuelle)
echo "🛡️ Vérification des permissions (~/.ssh/authorized_keys sur Proxmox)"
echo "Connectez-vous et exécutez :"
echo "chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"

# 5. Ajout de la clé dans l'agent SSH
echo "💼 Chargement de la clé privée dans ssh-agent..."
eval "$(ssh-agent -s)"
ssh-add "$TF_SSH_KEY"

# 6. Test SSH
echo "🧪 Test de la connexion SSH à Proxmox..."
ssh -o BatchMode=yes -i "$TF_SSH_KEY" "$PROXMOX_USER@$PROXMOX_HOST" "echo ✅ Connexion réussie à Proxmox" || {
  echo "❌ Connexion SSH échouée. Vérifiez les étapes précédentes."
  exit 1
}

# 7. Chargement des variables d’environnement (.env)
if [ -f .env ]; then
  echo "📦 Chargement des variables depuis .env..."
  set -a
  source .env
  set +a
else
  echo "⚠️ Fichier .env manquant (non bloquant ici)."
fi

# 8. Terraform Initialisation
echo "🚀 Lancement de Terraform..."
terraform init
terraform validate

echo "✅ Setup terminé. Vous pouvez lancer terraform apply si tout est OK."