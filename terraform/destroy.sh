#!/bin/bash
set -euo pipefail

# ───────────────────────────────
# ⚙️  Configuration
# ───────────────────────────────
TF_SSH_KEY="$HOME/.ssh/id_rsa_terraform"
PROXMOX_HOST="192.168.10.180"
OUTPUT_DIR="./cloud-init"

# ───────────────────────────────
# 📦 Chargement du .env (si présent)
# ───────────────────────────────
if [ -f .env ]; then
  echo "📦 Chargement des variables depuis .env..."
  set -a
  source .env
  set +a
else
  echo "⚠️ Fichier .env non trouvé — utilisation des valeurs par défaut."
fi

# ───────────────────────────────
# 🧭 Vérification de la configuration
# ───────────────────────────────
if ! command -v terraform >/dev/null 2>&1; then
  echo "❌ Terraform non trouvé dans le PATH."
  exit 1
fi

if [ ! -f "$TF_SSH_KEY" ]; then
  echo "⚠️ Clé SSH Terraform manquante ($TF_SSH_KEY)."
fi

# ───────────────────────────────
# 🔍 Liste des VMs actuelles (via Terraform outputs)
# ───────────────────────────────
echo "🔍 Vérification des VMs gérées par Terraform..."
if terraform output -json >/tmp/tf_output.json 2>/dev/null; then
  VM_MODULES=$(jq -r 'keys[] | select(test(".*_vm_name$"))' /tmp/tf_output.json | sed 's/_vm_name$//' | sort || true)
  if [[ -n "$VM_MODULES" ]]; then
    echo "🧾 VMs détectées :"
    for MODULE in $VM_MODULES; do
      VM_NAME=$(terraform output -raw ${MODULE}_vm_name 2>/dev/null || echo "N/A")
      VM_ID=$(terraform output -raw ${MODULE}_vm_id 2>/dev/null || echo "N/A")
      echo "  • $VM_NAME (ID: $VM_ID)"
    done
  else
    echo "⚠️ Aucune VM Terraform détectée."
  fi
else
  echo "⚠️ Impossible de lire les outputs Terraform (probablement pas d'état existant)."
fi

# ───────────────────────────────
# 💣 Destruction Terraform
# ───────────────────────────────

echo "💣 Exécution de terraform destroy..."
terraform destroy -auto-approve \
  -var="ssh_public_key=$HOME/.ssh/id_rsa_terraform.pub" \
  -var="ssh_private_key=$HOME/.ssh/id_rsa_terraform" \
  -var="ssh_user=root" \
  -var="ssh_port=22"


echo "✅ Destruction Terraform terminée."

# ───────────────────────────────
# 🧹 Nettoyage local
# ───────────────────────────────
echo "🧹 Nettoyage des fichiers locaux..."

if [ -d "$OUTPUT_DIR" ]; then
  echo "   → Suppression de $OUTPUT_DIR"
  rm -rf "$OUTPUT_DIR"
fi

find "$HOME/.ssh" -type f -name "*serveur-*.local_id_rsa*" -exec rm -f {} \; 2>/dev/null || true

if pgrep -x "ssh-agent" >/dev/null; then
  echo "   → Fermeture de ssh-agent"
  pkill ssh-agent || true
fi

echo "🎉 Nettoyage terminé. Toutes les ressources et fichiers locaux ont été supprimés."
