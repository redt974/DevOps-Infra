#!/bin/bash

DISK="/dev/sda"
HOSTNAME="arch-linux"
LOCALE="fr_FR.UTF-8"
TIMEZONE="Europe/Paris"

read -p "Nom d'utilisateur : " USER 

echo "[*] Saisie du mot de passe pour l'utilisateur $USER"
read -s -p "Mot de passe pour $USER : " PASSWORD
echo
read -s -p "Confirmation du mot de passe pour $USER : " PASSWORD_CONFIRM
echo
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
  echo "❌ Les mots de passe pour $USER ne correspondent pas."
  exit 1
fi

echo "[*] Suppression des partitions existantes"
for PART in $(lsblk -nr -o NAME $DISK | grep -E "^$(basename $DISK)p?[0-9]+$"); do
  echo " - Suppression de /dev/$PART"
  wipefs --all --force "/dev/$PART"
done

# Optionnel : Effacer complètement le disque (si pris en charge)
if command -v blkdiscard &>/dev/null; then
  blkdiscard -f $DISK
fi

# Synchroniser et recharger la table de partitions
sync
partprobe $DISK
sleep 3  # Laisser le temps au kernel de prendre en compte les changements

echo "[*] Nettoyage disque $DISK"
wipefs --all --force $DISK
parted -s $DISK mklabel gpt
sleep 3

echo "[*] Création des partitions"
parted -s $DISK mkpart primary 2MiB 3MiB
parted -s $DISK set 1 bios_grub on

parted -s $DISK mkpart primary fat32 3MiB 553MiB
parted -s $DISK set 2 boot on

parted -s $DISK mkpart primary linux-swap 553MiB 4553MiB
parted -s $DISK mkpart primary ext4 4553MiB 100%

# Attendre que le kernel détecte les partitions
echo "[*] Relecture de la table des partitions"
sync
partprobe $DISK
sleep 5  # Pause plus longue pour éviter les problèmes

# Vérifier si les partitions sont bien créées avant de continuer
lsblk $DISK

echo "[*] Formatage des partitions"
mkfs.fat -F32 ${DISK}2 || { echo "❌ Erreur formatage /boot"; exit 1; }
mkswap ${DISK}3 || { echo "❌ Erreur formatage swap"; exit 1; }
swapon ${DISK}3
mkfs.ext4 ${DISK}4 || { echo "❌ Erreur formatage /"; exit 1; }

echo "[*] Montage des partitions"
mount ${DISK}4 /mnt || { echo "❌ Erreur montage /"; exit 1; }
mkdir -p /mnt/boot
mount ${DISK}2 /mnt/boot || { echo "❌ Erreur montage /boot"; exit 1; }

echo "[*] Partitions (lsblk):"
lsblk

echo "[*] Synchronisation de l'heure"
timedatectl set-ntp true

echo "[*] Installation de base + dhcpcd"
pacstrap /mnt base base-devel linux linux-firmware vim sudo openssh grub dhcpcd --noconfirm

echo "[*] Génération de fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "[*] Chroot configuration"
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "KEYMAP=fr-latin1" > /etc/vconsole.conf

echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo "[*] Création de l'utilisateur $USER"
useradd -m -G wheel -s /bin/bash $USER
echo "$USER:$PASSWORD" | chpasswd

echo "[*] Configuration sudoers"
echo "$USER ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/$USER
chmod 440 /etc/sudoers.d/$USER 

echo "[*] Journalisation des commandes sudo"
echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers

echo "[*] Installation de GRUB en mode BIOS"
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

echo "[*] Activation des services essentiels"
systemctl enable sshd
systemctl enable systemd-timesyncd
systemctl enable dhcpcd

echo "[*] Hardening SSH"
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
EOF

echo "[*] Démontage propre de /mnt"
swapoff ${DISK}p3
umount -R /mnt

if [ $? -eq 0 ]; then
  echo "[*] ✅ Installation terminée ! Redémarre la VM et enlève l'ISO."
  systemctl poweroff
else
  echo "[!] ⚠️ Problème lors du démontage de /mnt. Vérifie manuellement." >&2
  exit 1
fi
