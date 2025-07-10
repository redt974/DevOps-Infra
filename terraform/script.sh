#!/bin/bash

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

# Variables d'environnement
SSH_KEY_PATH="$HOME/.ssh/id_rsa_terraform"
VM_SSH_KEY_PATH="$HOME/.ssh/vm-access_id_rsa"
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
ssh-add $SSH_KEY_PATH

# Affichage des clés SSH ajoutées
echo "Clés SSH actuellement ajoutées :"
ssh-add -L

# Exécution de terraform apply avec les clés injectées
echo "🚀 Exécution de Terraform apply..."
terraform apply -auto-approve \
  -var="ssh_public_key=$(cat "$SSH_KEY_PATH.pub")" \
  -var="ssh_private_key=$(cat "$SSH_KEY_PATH")" \
  -var="ssh_user=$SSH_USER" \
  -var=ssh_port=$SSH_PORT     

# Vérification du succès
if [ $? -eq 0 ]; then
  echo "✅ Terraform apply terminé avec succès."
else
  echo "❌ Terraform apply a échoué."
  exit 1
fi

VM_ID=$(terraform output -raw vm_id 2>/dev/null)
VM_NAME=$(terraform output -raw vm_name 2>/dev/null)
VM_IP=$(terraform output -json vm_ip 2>/dev/null | jq -r '.[] | select(test("^192\\.168\\."))' | head -n1)
# Récupération des tag OS de la VM
VM_TAGS_JSON=$(terraform output -json vm_tags)
VM_OS_TAG=$(echo "$VM_TAGS_JSON" | jq -r '.[1]')


if [[ -z "$VM_IP" ]]; then
  echo "🔎 IP non trouvée dans Terraform, tentative via qm + QEMU Guest Agent..."

  if command -v ssh >/dev/null && command -v jq >/dev/null; then
    IP=$(ssh -i "$SSH_KEY_PATH" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" \
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin sudo -n /usr/sbin/qm guest cmd $VM_ID network-get-interfaces" 2>/dev/null \
      | jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]?.ip-address' \
      | grep -E '^192\.168\.' | head -n1)

    if [[ -n "$IP" ]]; then
      VM_IP="$IP"
      echo "✅ IP détectée via qm: $VM_IP"
    else
      echo "❌ Impossible de récupérer l'IP via QEMU Guest Agent."
    fi
  else
    echo "❌ ssh ou jq introuvables localement."
  fi
else
  echo "✅ IP récupérée depuis Terraform : $VM_IP"
fi

if [[ -n "$VM_IP" ]]; then
  echo "🔗 Connectez-vous à la VM ($VM_NAME) :"
  echo "ssh -i $VM_SSH_KEY_PATH $VM_OS_TAG@$VM_IP"
fi

# Nettoyage ssh-agent
ssh-add -D
echo "✅ Agent SSH nettoyé."