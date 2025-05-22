#!/bin/bash

# Vérification des droits sudo
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté avec sudo." 
    exit 1
fi

echo "Mise à jour du système..."
apt update && apt upgrade -y

echo "Installation des outils de sécurité..."
apt install -y ufw fail2ban apparmor apparmor-utils auditd unattended-upgrades apt-listchanges

echo "Configuration des mises à jour automatiques..."
dpkg-reconfigure -plow unattended-upgrades

echo "Sécurisation des utilisateurs..."
passwd -l root
echo "root désactivé"

echo "Configuration des mots de passe expirables..."
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 10/' /etc/login.defs

echo "Sécurisation de SSH..."
sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
echo "Redémarrage du service SSH..."
systemctl restart ssh

echo "[*] Création de la clé SSH pour debian"
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Génération de la clé (pas de passphrase)
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa

# Ajout de la clé publique dans authorized_keys
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

echo "[*] Clé SSH générée pour debian"
echo
echo "[*] Voici la **clé privée** que tu dois importer sur ton PC hôte :"
echo
cat ~/.ssh/id_rsa
rm ~/.ssh/id_rsa
echo
echo "[*] Sauvegarde-la dans un fichier (ex: ~/.ssh/id_rsa), avec chmod 600"
echo "Exemple de connexion :"
echo "ssh -i ~/.ssh/id_rsa -p 2222 debian@<IP_DE_TA_VM>"
echo

echo "Configuration du pare-feu UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 2222/tcp  # Port SSH
ufw enable

echo "Désactivation des services inutiles..."
for service in avahi-daemon cups bluetooth; do
    systemctl disable --now $service 2>/dev/null
done

echo "Activation d'AppArmor..."
systemctl enable --now apparmor

echo "Activation de Fail2Ban..."
systemctl enable --now fail2ban

echo "Activation d'AuditD..."
systemctl enable --now auditd

echo "Sécurisation du disque temporaire..."
echo "tmpfs /tmp tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
mount -o remount /tmp

echo "Nettoyage du système..."
apt autoremove -y && apt autoclean -y

echo "Sécurisation terminée ! Redémarrage recommandé."
