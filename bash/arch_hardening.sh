#!/bin/bash

set -euo pipefail

echo "[*] Démarrage du hardening SSH + GRUB..."

### Fonctions Utilitaires ###
is_root() {
  [ "$(id -u)" -eq 0 ]
}

run() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

### Vérification des droits ###
if ! is_root; then
  echo "❌ Ce script doit être exécuté en tant que root (ou via sudo)."
  exit 1
fi

##############################
### --- HARDENING SSH ---  ###
##############################

echo "[*] Hardening de SSH"

run systemctl stop sshd

# Backup de la config actuelle
echo "[*] Backup config SSH"
run cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Création du fichier custom de configuration avancée
echo "[*] Écriture de la config avancée dans /etc/ssh/sshd_config"
run bash -c 'cat <<EOF > /etc/ssh/sshd_config
Port 22222
AddressFamily inet
ListenAddress 0.0.0.0

PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication yes
UsePAM yes
KbdInteractiveAuthentication yes

AuthenticationMethods publickey,keyboard-interactive
DenyUsers rescue

MaxAuthTries 1
LoginGraceTime 30

AllowTcpForwarding no
X11Forwarding no
HostbasedAuthentication no
IgnoreRhosts yes
PermitUserEnvironment no

ClientAliveInterval 90
ClientAliveCountMax 0
TCPKeepAlive no

Protocol 2
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

Subsystem sftp /usr/lib/ssh/sftp-server
EOF'

### Modification / ajout explicite ###
SSHD_CUSTOM_CONF="/etc/ssh/sshd_config.d/99-archlinux.conf"

echo "[*] Vérification de KbdInteractiveAuthentication et UsePAM dans $SSHD_CUSTOM_CONF"
grep -q "^KbdInteractiveAuthentication" "$SSHD_CUSTOM_CONF" || echo "KbdInteractiveAuthentication yes" >> "$SSHD_CUSTOM_CONF"
grep -q "^UsePAM" "$SSHD_CUSTOM_CONF" || echo "UsePAM yes" >> "$SSHD_CUSTOM_CONF"

# Vérification de la configuration SSH
echo "[*] Vérification syntaxe SSH"
run sshd -t

if [ $? -eq 0 ]; then
  echo "[*] ✅ SSH config valide, redémarrage"
  run systemctl enable sshd
  run systemctl restart sshd
else
  echo "❌ Erreur dans la config SSH. Abandon."
  exit 1
fi

##########################################
### --- MFA Google Authenticator --- ###
##########################################

echo "[*] Installation de Google Authenticator pour localadm"
run pacman -Sy --noconfirm libpam-google-authenticator qrencode

# Configuration MFA pour l'utilisateur localadm
echo "[*] Configuration MFA Google Authenticator pour localadm"
run su - localadm -c "google-authenticator -t -d -f -r 3 -R 30 -W"

# Configuration MFA pour l'utilisateur rescue
echo "[*] Configuration MFA Google Authenticator pour rescue"
run su - rescue -c "google-authenticator -t -d -f -r 3 -R 30 -W"

# Configuration PAM pour SSH et sudo
echo "[*] Mise à jour des règles PAM pour SSH et SUDO"
PAM_SSHD_FILE="/etc/pam.d/sshd"
PAM_SUDO_FILE="/etc/pam.d/sudo"

# Ajout MFA dans PAM si ce n'est pas déjà fait
grep -q "pam_google_authenticator.so" "$PAM_SSHD_FILE" || echo "auth required pam_google_authenticator.so" >> "$PAM_SSHD_FILE"
grep -q "pam_google_authenticator.so" "$PAM_SUDO_FILE" || echo "auth required pam_google_authenticator.so" >> "$PAM_SUDO_FILE"

# Config SUDO avancée
echo "[*] Mise à jour de /etc/sudoers"
run bash -c 'cat <<EOF >> /etc/sudoers

Defaults env_reset
Defaults timestamp_timeout=0
Defaults logfile="/var/log/sudo.log"
EOF'

##########################################
### --- SERVICES ESSENTIELS --- ###
##########################################

echo "[*] Activation des services essentiels"
run systemctl enable sshd
run systemctl enable systemd-timesyncd

#####################################################
### --- CRÉATION CLÉ SSH POUR localadm --- ###
#####################################################

echo "[*] Création de la clé SSH pour localadm"

run su - localadm -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

# Génération de la clé (pas de passphrase)
run su - localadm -c "ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa"

# Ajout de la clé publique dans authorized_keys
run su - localadm -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

echo "[*] ✅ Clé SSH générée pour localadm"
echo
echo "➡️  Voici la **clé privée** que tu dois importer sur ton PC hôte :"
echo
run su - localadm -c 'cat ~/.ssh/id_rsa'
run su - localadm -c 'rm ~/.ssh/id_rsa'
echo
echo "💡 Sauvegarde-la dans un fichier (ex: ~/.ssh/id_rsa), avec chmod 600"
echo "Exemple de connexion :"
echo "ssh -i ~/.ssh/id_rsa -p 22222 localadm@<IP_DE_TA_VM>"
echo

###############################################
### --- SÉCURISATION GRUB --- ###
###############################################

echo "[*] Configuration du mot de passe pour GRUB"

read -p "Nom d'utilisateur GRUB : " GRUB_USER

while true; do
  read -s -p "Mot de passe GRUB : " GRUB_PASS
  echo
  read -s -p "Confirme le mot de passe GRUB : " GRUB_PASS_CONFIRM
  echo
  [ "$GRUB_PASS" == "$GRUB_PASS_CONFIRM" ] && break || echo "❌ Les mots de passe ne correspondent pas. Réessaie."
done

# Génération du hash PBKDF2 (langue FR prise en compte)
HASHED_PASS=$(echo -e "$GRUB_PASS\n$GRUB_PASS" | grub-mkpasswd-pbkdf2 | grep 'Le hachage PBKDF2' | awk '{print $9}')

# Vérification du hash
if [ -z "$HASHED_PASS" ]; then
  echo "❌ Impossible de générer le hash PBKDF2 pour GRUB."
  exit 1
fi

echo "[*] Backup de /etc/grub.d/40_custom"
cp /etc/grub.d/40_custom /etc/grub.d/40_custom.bak

# Génération du fichier /etc/grub.d/40_custom
cat <<EOF > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0

set superusers="$GRUB_USER"
password_pbkdf2 $GRUB_USER $HASHED_PASS
export superusers
EOF

chmod 755 /etc/grub.d/40_custom

### Ajout de --unrestricted aux entrées GRUB ###
echo "[*] Ajout de --unrestricted aux entrées GRUB"
cp /etc/grub.d/10_linux /etc/grub.d/10_linux.bak

rm /etc/grub.d/10_linux.bak

sed -i "s/\(menuentry 'Arch Linux'.*\)/\1 --unrestricted/" /etc/grub.d/10_linux

### Remontage de /boot et génération de grub.cfg ###
echo "[*] Remontage de /boot en lecture-écriture"
mount -o remount,rw /boot

echo "[*] Génération de grub.cfg"
if grub-mkconfig -o /boot/grub/grub.cfg; then
  echo "[*] ✅ grub.cfg généré avec succès"
else
  echo "❌ Échec de la génération de grub.cfg"
  exit 1
fi

chmod -R 700 /etc/grub.d

### Sécurisation de /boot ###
echo "[*] Mise à jour de fstab pour /boot FAT32"
sed -i '/\/boot/s/defaults.*/defaults,nosuid,nodev,noexec,fmask=0177,dmask=0077/' /etc/fstab

echo "[*] Remontage de /boot en lecture seule"
mount -o remount,ro /boot

systemctl daemon-reload

echo "[*] ✅ Hardening terminé avec succès !"
