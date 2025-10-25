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

# Liste des OS et du nombre de VMs à créer pour chacun
declare -A VM_COUNTS=(
  ["ubuntu"]=3
  ["debian"]=2
  ["arch"]=1
)

echo "🔁 Génération des clés SSH et fichiers cloud-init..."

for OS_ID in "${!VM_COUNTS[@]}"; do
  COUNT=${VM_COUNTS[$OS_ID]}
  for ((i=1; i<=COUNT; i++)); do
    USER_NAME="$OS_ID"
    HOSTNAME="serveur-${OS_ID}${i}"
    DOMAIN="local"
    INSTANCE_ID="${OS_ID}-${i}"
    VM_NAME="${HOSTNAME}.${DOMAIN}"
    VM_DIR="$OUTPUT_DIR/$VM_NAME"

    mkdir -p "$VM_DIR"

    VM_KEY="$SSH_DIR/${VM_NAME}_id_rsa"

    echo "🔐 [$VM_NAME] Génération de la clé SSH..."
    rm -f "$VM_KEY" "$VM_KEY.pub"
    ssh-keygen -t rsa -b 4096 -N '' -f "$VM_KEY" -C "$VM_NAME" -q
    PUB_KEY=$(cat "$VM_KEY.pub")

    echo "📝 [$VM_NAME] Création des fichiers cloud-init..."

    cat > "$VM_DIR/user_data.yml" <<EOF
#cloud-config
hostname: $HOSTNAME
fqdn: $VM_NAME
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
      - $PUB_KEY

ssh_pwauth: false
EOF

    cat > "$VM_DIR/meta_data.yml" <<EOF
instance-id: ${INSTANCE_ID}
local-hostname: $HOSTNAME
EOF

    cat > "$VM_DIR/${VM_NAME}.info" <<EOF
vm_name=${VM_NAME}
ssh_key_path=${VM_KEY}
ssh_user=${USER_NAME}
EOF

  done
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

# Récupération des VMs depuis l'output 'vms'
VM_JSON=$(terraform output -json vms)

# Boucle sur chaque VM
echo "$VM_JSON" | jq -r 'to_entries[] | "\(.key) \(.value.ip[] | select(test("^192\\.168\\.")))"' | while read -r VM_NAME VM_IP; do
    INFO_PATH="$OUTPUT_DIR/$VM_NAME.$DOMAIN/$VM_NAME.$DOMAIN.info"
    if [[ ! -f "$INFO_PATH" ]]; then
        echo "⚠️  Fichier info manquant : $INFO_PATH"
        continue
    fi
    source "$INFO_PATH"
    echo "🔗 Connexion possible à $VM_NAME :"
    echo "ssh -i $ssh_key_path $ssh_user@$VM_IP"
    echo ""
done

# ==============================================================
# 🧩 MISE À JOUR AUTOMATIQUE DU FICHIER hosts.yml ANSIBLE (yq v4)
# ==============================================================

ANSIBLE_HOSTS_FILE="/home/thibaut/DevOps-Infra/ansible/inventories/proxmox/hosts.yml"
VM_JSON=$(terraform output -json vms)

echo "🔄 Mise à jour du fichier Ansible hosts.yml avec les IPs détectées..."

# Parcourir chaque VM
echo "$VM_JSON" | jq -r 'to_entries[] | "\(.key) \(.value.ip[] | select(test("^192\\.168\\."))) \(.value.tags[])"' | while read -r VM_NAME VM_IP VM_OS; do
  # Exemples :
  # VM_NAME = serveur-ubuntu1
  # VM_IP = 192.168.10.207
  # VM_OS = ubuntu

  ANSIBLE_USER="$VM_OS"
  SSH_KEY_PATH="$HOME/.ssh/${VM_NAME}.local_id_rsa"
  HOST_KEY="vm-${VM_NAME#serveur-}.local"

  # Vérifie si le host existe déjà
  if yq eval ".all.children.allhosts.hosts.\"${HOST_KEY}\"" "$ANSIBLE_HOSTS_FILE" >/dev/null; then
    echo "➡️  Mise à jour de $HOST_KEY avec IP: $VM_IP"
  else
    echo "➕ Ajout de $HOST_KEY (nouvel hôte)"
    # Crée la structure s'il n'existe pas
    yq eval -i ".all.children.allhosts.hosts.\"${HOST_KEY}\" = {}" "$ANSIBLE_HOSTS_FILE"
  fi

  # Met à jour les valeurs ansible
  yq eval -i ".all.children.allhosts.hosts.\"${HOST_KEY}\".ansible_host = \"$VM_IP\"" "$ANSIBLE_HOSTS_FILE"
  yq eval -i ".all.children.allhosts.hosts.\"${HOST_KEY}\".ansible_user = \"$ANSIBLE_USER\"" "$ANSIBLE_HOSTS_FILE"
  yq eval -i ".all.children.allhosts.hosts.\"${HOST_KEY}\".ansible_ssh_private_key_file = \"$SSH_KEY_PATH\"" "$ANSIBLE_HOSTS_FILE"

  # (optionnel) ajoute automatiquement dans des groupes selon l’OS
  if ! yq eval ".all.children.${VM_OS}.hosts.\"${HOST_KEY}\"" "$ANSIBLE_HOSTS_FILE" >/dev/null; then
    yq eval -i ".all.children.${VM_OS}.hosts.\"${HOST_KEY}\" = {}" "$ANSIBLE_HOSTS_FILE"
  fi

  if ! grep -q "$VM_IP $HOST_KEY" /etc/hosts; then
  echo "$VM_IP $HOST_KEY" | sudo tee -a /etc/hosts >/dev/null
  fi

done

echo "✅ Fichier hosts.yml mis à jour avec succès."
echo "🎉 Script terminé avec succès !"