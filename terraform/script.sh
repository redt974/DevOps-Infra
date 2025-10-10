#!/bin/bash
set -euo pipefail

# 🔧 Config
NUM_VMS=3
OS_LIST=("ubuntu" "debian" "arch")
SSH_DIR="$HOME/.ssh"
OUTPUT_DIR="./cloud-init"

# Préparer dossiers
mkdir -p "$SSH_DIR"
mkdir -p "$OUTPUT_DIR"

# Load .env variables if it exists
if [ -f .env ]; then
  echo "Chargement des variables d'environnement depuis .env..."
  set -a
  source .env
  set +a
else
  echo "❌ Fichier .env manquant."
  exit 1
fi

declare -A os_counts
declare -A all_pub_keys_per_os

echo "🔁 Génération des clés SSH et fichiers cloud-init..."

for (( i=1; i<=NUM_VMS; i++ )); do
  OS_ID="${OS_LIST[$((i-1))]}"   # Identifiant utilisé pour les chemins
  USER_NAME="$OS_ID"             # Nom de l'utilisateur Linux
  os_counts[$OS_ID]=$(( ${os_counts[$OS_ID]:-0} + 1 ))
  VM_INDEX=${os_counts[$OS_ID]}

  HOSTNAME="serveur-${OS_ID}"
  DOMAIN="local"
  INSTANCE_ID="${OS_ID}-${VM_INDEX}"

  VM_NAME="${HOSTNAME}.${DOMAIN}"
  VM_KEY="$SSH_DIR/${VM_NAME}_id_rsa"

  echo "🔐 [$VM_NAME] Suppression des anciennes clés SSH si existantes..."
  rm -f "$VM_KEY" "$VM_KEY.pub"

  echo "🔐 [$VM_NAME] Génération de la clé SSH dans $VM_KEY..."
  ssh-keygen -t rsa -b 4096 -N '' -f "$VM_KEY" -C "$VM_NAME" -q

  pub_key=$(cat "$VM_KEY.pub")

  # Cumuler toutes les clés publiques pour cet OS (toutes les VMs de même OS partagent l'accès)
  if [[ -z "${all_pub_keys_per_os[$OS_ID]:-}" ]]; then
    all_pub_keys_per_os[$OS_ID]="$pub_key"
  else
    all_pub_keys_per_os[$OS_ID]="${all_pub_keys_per_os[$OS_ID]}"$'\n'"$pub_key"
  fi

  VM_DIR="$OUTPUT_DIR/$VM_NAME"
  mkdir -p "$VM_DIR"

  echo "📝 [$VM_NAME] Création des fichiers cloud-init..."

  ssh_keys_yaml=""
  while IFS= read -r line || [[ -n $line ]]; do
    ssh_keys_yaml+="      - $line"$'\n'
  done <<< "${all_pub_keys_per_os[$OS_ID]}"

  cat > "$VM_DIR/user_data.yml" <<EOF
#cloud-config
hostname: $HOSTNAME
local-hostname: $HOSTNAME
fqdn: $HOSTNAME.${DOMAIN}
manage_etc_hosts: true

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - sudo
  - openssh-server

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

users:
  - name: $USER_NAME
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
$ssh_keys_yaml

ssh_pwauth: false
EOF

  cat > "$VM_DIR/meta_data.yml" <<EOF
instance-id: ${INSTANCE_ID}
local-hostname: $HOSTNAME
EOF

  cat > "$VM_DIR/${USER_NAME}.info" <<EOF
vm_name=${VM_NAME}
ssh_key_path=${VM_KEY}
ssh_user=${USER_NAME}
EOF

done

echo "🎉 Toutes les clés SSH et fichiers cloud-init générés."

SSH_KEY_PATH="$HOME/.ssh/id_rsa_terraform"
SSH_USER=root
SSH_PORT=22

# Vérifie l'existence de la clé
if [ ! -f "$SSH_KEY_PATH" ] || [ ! -f "$SSH_KEY_PATH.pub" ]; then
  echo "Erreur : Clé SSH manquante ($SSH_KEY_PATH ou $SSH_KEY_PATH.pub)"
  exit 1
fi

# Add SSH key to the agent
echo "🔑 Ajout de la clé SSH à l'agent..."
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/proxmox_root_id_rsa"
ssh-add "$SSH_KEY_PATH"

# Affichage des clés SSH ajoutées
echo "Clés SSH actuellement ajoutées :"
ssh-add -L

# Lancer Terraform apply avec la clé Terraform
echo "🚀 Exécution de Terraform apply..."
terraform apply -auto-approve \
  -var="ssh_public_key=$SSH_KEY_PATH.pub" \
  -var="ssh_private_key=$SSH_KEY_PATH" \
  -var="ssh_user=$SSH_USER" \
  -var=ssh_port=$SSH_PORT

echo "✅ Terraform terminé. Tentative de détection des VMs..."

# Détection automatique des VMs selon outputs Terraform
VM_MODULES=$(terraform output -json | jq -r 'keys[] | select(test(".*_vm_name$"))' | sed 's/_vm_name$//' | sort)

if [[ -z "$VM_MODULES" ]]; then
  echo "❌ Aucune VM détectée via Terraform outputs."
  exit 1
fi

echo "🔍 Détection de VMs : $VM_MODULES"

for MODULE in $VM_MODULES; do
  VM_NAME=$(terraform output -raw ${MODULE}_vm_name)
  VM_ID=$(terraform output -raw ${MODULE}_vm_id)
  VM_IPS=$(terraform output -json ${MODULE}_vm_ip)

  VM_IP=$(echo "$VM_IPS" | jq -r '.[] | select(test("^192\\.168\\."))' | head -n1)

  INFO_PATH="$OUTPUT_DIR/$VM_NAME/${MODULE}.info"
  if [[ ! -f "$INFO_PATH" ]]; then
    echo "⚠️  Fichier info manquant : $INFO_PATH"
    continue
  fi

  source "$INFO_PATH"

  echo "🔗 Connexion possible à $VM_NAME ($MODULE) :"
  echo "ssh -i $ssh_key_path $ssh_user@$VM_IP"
  echo ""
done

echo "🎉 Script terminé avec succès !"