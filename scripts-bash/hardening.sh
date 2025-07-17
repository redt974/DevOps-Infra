#!/usr/bin/env bash

set -euo pipefail

# Vérification de l'utilisateur root
if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

# Détection de la distribution
detect_os() {
  if [[ -e /etc/os-release ]]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unsupported"
  fi
}

OS_ID=$(detect_os)

# Fonctions de hardening communes
common_hardening() {
  echo "➡ Appliquer les sécurités communes..."

  # Récupération du port SSH configuré (sinon défaut 22)
  SSH_PORT=$(grep -i "^Port " /etc/ssh/sshd_config | awk '{print $2}' || true)
  SSH_PORT=${SSH_PORT:-22}

  # Désactiver le compte root (sauf si sudo n’est pas encore configuré)
  passwd -l root || true

  # Sécuriser SSH
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?AddressFamily.*/AddressFamily inet/' /etc/ssh/sshd_config

  # Activer le banner SSH
  echo "Unauthorized access is prohibited. Your IP will be logged and banned." > /etc/issue.net
  sed -i 's|^#\?Banner.*|Banner /etc/issue.net|' /etc/ssh/sshd_config

  # Redémarrer SSH
  systemctl restart sshd || systemctl restart ssh || true

  # Activer le pare-feu UFW si disponible
  if command -v ufw >/dev/null 2>&1; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"
    ufw --force enable
  fi

  # Désactiver services inutiles
  systemctl disable systemd-timesyncd.service || true

  # Installer fail2ban selon la distro
  if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y fail2ban
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm fail2ban
  fi

  # Créer la config fail2ban
  mkdir -p /etc/fail2ban

  cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
backend = systemd
logpath = %(__journald_log)s
maxretry = 5
bantime = 1h
findtime = 10m
EOF

  # Activer fail2ban
  systemctl enable fail2ban --now

  # Vérification rapide
  echo "📦 fail2ban : allumage"
  sudo systemctl start fail2ban

  # Attendre que fail2ban démarre proprement
  sleep 2

  # Vérification SSH et fail2ban
  sudo fail2ban-client status
  sudo fail2ban-client status sshd
}

# Spécifique Debian/Ubuntu
debian_hardening() {
  echo "➡ Hardening Debian/Ubuntu..."
  apt update && apt upgrade -y
  apt autoremove --purge -y
  systemctl enable apparmor --now || true
}

# Spécifique Arch
arch_hardening() {
  echo "➡ Hardening Arch Linux..."
  pacman -Syu --noconfirm
  pacman -Rns --noconfirm cups xorg lxdm || true
  pacman -S --noconfirm audit
  systemctl enable auditd --now
  if pacman -Qs apparmor >/dev/null; then
    systemctl enable apparmor --now || true
  fi
}

# Application selon la distribution
case "$OS_ID" in
  debian|ubuntu)
    debian_hardening
    common_hardening
    ;;
  arch)
    arch_hardening
    common_hardening
    ;;
  *)
    echo "❌ Distribution non supportée : $OS_ID" >&2
    exit 1
    ;;
esac

echo "✅ Hardening de base appliqué avec succès pour $OS_ID."