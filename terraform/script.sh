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

# Affichage de la sortie (adapte à ton output réel)
echo "📡 IP publique (si définie dans outputs) :"
terraform output -raw instance_public_ip 2>/dev/null || echo "Pas de sortie 'instance_public_ip' définie."

# Nettoyage de l'agent SSH
echo "🧹 Nettoyage de l'agent SSH..."
ssh-add -D
echo "Agent SSH nettoyé."

# Affichage de la commande SSH
echo "🔗 Pour vous connecter, utilisez la commande suivante :"
echo "ssh -i $SSH_KEY_PATH $SSH_USER@$(terraform output -raw instance_public_ip)"
echp "OU" 
echo "ssh -i $HOME/.ssh/vm-access_id_rsa ubuntu@192.168.10.x" # Remplacez par l'IP ou le nom d'hôte correct