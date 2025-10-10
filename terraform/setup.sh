#!/bin/bash
set -euo pipefail

# ───────────────────────────────
# 🧩 Configuration
# ───────────────────────────────
TF_SSH_KEY="$HOME/.ssh/id_rsa_terraform"         # clé pour Terraform ↔ Proxmox
PROXMOX_USER="root"
PROXMOX_HOST="192.168.10.180"
PROXMOX_PORT="22"
PROXMOX_SSH_PATH="$HOME/.ssh/proxmox_root_id_rsa"  # clé déjà valide pour root@Proxmox

# ───────────────────────────────
# 🔐 1. Génération de la clé SSH Terraform ↔ Proxmox
# ───────────────────────────────
echo "🔐 Vérification / génération de la clé SSH Terraform..."
if [ ! -f "$TF_SSH_KEY" ]; then
  ssh-keygen -t rsa -b 4096 -N '' -f "$TF_SSH_KEY" -C "terraform@$(hostname)"
  echo "✅ Clé SSH générée : $TF_SSH_KEY"
else
  echo "ℹ️ Clé SSH déjà existante : $TF_SSH_KEY"
fi

# ───────────────────────────────
# 📤 2. Copie automatique de la clé publique sur Proxmox (via clé racine)
# ───────────────────────────────
echo "📤 Copie de la clé publique Terraform sur Proxmox..."

# Vérifie si la clé d’accès root à Proxmox fonctionne
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -i "$PROXMOX_SSH_PATH" \
  "$PROXMOX_USER@$PROXMOX_HOST" "exit" 2>/dev/null; then

  echo "✅ Connexion root@Proxmox réussie avec $PROXMOX_SSH_PATH"
  echo "➡️ Installation de la clé publique Terraform..."
  ssh -i "$PROXMOX_SSH_PATH" "$PROXMOX_USER@$PROXMOX_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
  scp -i "$PROXMOX_SSH_PATH" "$TF_SSH_KEY.pub" "$PROXMOX_USER@$PROXMOX_HOST:/tmp/terraform.pub"
  ssh -i "$PROXMOX_SSH_PATH" "$PROXMOX_USER@$PROXMOX_HOST" "cat /tmp/terraform.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm /tmp/terraform.pub"
  echo "✅ Clé publique Terraform installée dans ~/.ssh/authorized_keys sur Proxmox"

else
  echo "❌ Impossible de se connecter à Proxmox avec $PROXMOX_SSH_PATH"
  echo "➡️ Copie manuelle nécessaire. Collez le contenu suivant dans /root/.ssh/authorized_keys sur Proxmox :"
  echo
  cat "$TF_SSH_KEY.pub"
  echo
  exit 1
fi

# ───────────────────────────────
# 💼 3. Chargement de la clé privée Terraform dans ssh-agent
# ───────────────────────────────
echo "💼 Chargement de la clé privée Terraform dans ssh-agent..."
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$TF_SSH_KEY" >/dev/null
echo "✅ Clé Terraform ajoutée à ssh-agent."

# ───────────────────────────────
# 🧪 4. Test de la connexion SSH Terraform → Proxmox
# ───────────────────────────────
echo "🧪 Test de la connexion SSH Terraform → Proxmox..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$TF_SSH_KEY" \
  "$PROXMOX_USER@$PROXMOX_HOST" "echo ✅ Connexion réussie à Proxmox"; then
  echo "✅ SSH opérationnel entre Terraform et Proxmox"
else
  echo "❌ Connexion SSH échouée avec la clé Terraform."
  exit 1
fi

# ───────────────────────────────
# 🌍 5. Chargement du fichier .env (si présent)
# ───────────────────────────────
if [ -f .env ]; then
  echo "📦 Chargement des variables depuis .env..."
  set -a
  source .env
  set +a
else
  echo "⚠️ Fichier .env introuvable (non bloquant)."
fi

# ───────────────────────────────
# 🚀 6. Initialisation Terraform
# ───────────────────────────────
echo "🚀 Initialisation Terraform..."
terraform init -input=false
terraform validate

echo "✅ Setup SSH et Terraform terminé. Vous pouvez exécuter : terraform apply"