#!/bin/bash

set -e

echo "👤 Votre nom d'utilisateur admin non-root :"
read -p "Nom d'utilisateur : " USER

# Génération clé utilisateur non-admin
if [ ! -f /home/$USER/.ssh/id_rsa ]; then
    sudo -u $USER ssh-keygen -t rsa -b 4096 -f /home/$USER/.ssh/id_rsa -N ""
    cat /home/$USER/.ssh/id_rsa.pub >> /home/$USER/.ssh/authorized_keys

    echo "⚠️ IMPORTANT : Note la clé privée pour $USER ci-dessous (à garder précieusement) !"
    echo "✅ Clé SSH privée pour $USER :"
    echo "----------------------------------------"
    base64 /home/$USER/.ssh/id_rsa
    echo "----------------------------------------"
fi

chown -R $USER:$USER /home/$USER/.ssh
chmod 700 /home/$USER/.ssh
chmod 600 /home/$USER/.ssh/authorized_keys

echo "✅ Clés SSH générées et installées."

# 🔒 Sécurisation SSH : uniquement clé publique
sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?UsePAM .*/UsePAM yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 1) Installation des prérequis généraux
echo "Mise à jour des dépôts..."
sudo apt update && sudo apt upgrade -y

echo "Installation des prérequis généraux..."
sudo apt install -y tree jq htop net-tools sshpass software-properties-common curl vim apt-transport-https ca-certificates gnupg lsb-release unzip openjdk-17-jdk make build-essential

# 2) Terraform (HashiCorp)
echo "Installation de Terraform..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform

# 3) Ansible
echo "Installation d'Ansible..."
sudo apt install -y ansible

# 4) Docker (install officiel)
echo "Installation de Docker..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER

# 5) Kubernetes tools (kubectl + minikube)
echo "Installation de kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

echo "Installation de minikube..."
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube
sudo install minikube /usr/local/bin/
rm minikube

# 6) Jenkins
echo "Installation de Jenkins..."
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins openjdk-17-jdk
sudo systemctl enable --now jenkins

# 7) GitLab Runner
echo "Installation de GitLab Runner..."
curl -L --output /tmp/gitlab-runner-linux-amd64 https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
sudo mv /tmp/gitlab-runner-linux-amd64 /usr/local/bin/gitlab-runner
sudo chmod +x /usr/local/bin/gitlab-runner

# Optionnel : enregistrer GitLab Runner après installation (manuel)

# 8) Jira Server (Atlassian)
echo "Installation de Jira Server..."
JIRA_VERSION="9.4.6"
wget https://product-downloads.atlassian.com/software/jira/downloads/atlassian-jira-software-${JIRA_VERSION}.tar.gz -P /tmp
sudo tar -xzf /tmp/atlassian-jira-software-${JIRA_VERSION}.tar.gz -C /opt
sudo mv /opt/atlassian-jira-software-${JIRA_VERSION}-standalone /opt/jira
# Création d'un utilisateur dédié
sudo useradd -r -m -U -d /opt/jira jira
sudo chown -R jira:jira /opt/jira
echo "Pour démarrer Jira : sudo -u jira /opt/jira/bin/start-jira.sh"

# 9) Vagrant
echo "Installation de Vagrant..."
sudo apt install -y vagrant

# 10) VS Code :
# Installer les dépendances de base
sudo apt-get update
sudo apt-get install -y wget gpg

# Télécharger la clé Microsoft et la placer correctement
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg

# Ajouter le dépôt VS Code
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
| sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

# Mettre à jour et installer VS Code
sudo apt update
sudo apt install -y code

echo "✅ Installation terminée avec succès !"
echo "Test SSH Proxmox → ssh proxmox"
echo "Terraform → terraform version"
echo "Ansible → ansible --version"
echo "Docker → docker run hello-world"
echo "Kubectl → kubectl version --client"