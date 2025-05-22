#!/bin/bash

DISK="/dev/sda"
HOSTNAME="arch-hardened"
ADMIN="localadm"
RESCUE="rescue"
LOCALE="fr_FR.UTF-8"
TIMEZONE="Europe/Paris"

echo "[*] Saisie du mot de passe pour l'utilisateur $ADMIN"
read -s -p "Mot de passe pour $ADMIN : " PASSWORD
echo
read -s -p "Confirmation du mot de passe pour $ADMIN : " PASSWORD_CONFIRM
echo
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
  echo "❌ Les mots de passe pour $ADMIN ne correspondent pas."
  exit 1
fi

echo "[*] Saisie du mot de passe pour l'utilisateur $RESCUE"
read -s -p "Mot de passe pour $RESCUE : " RESCUE_PASSWORD
echo
read -s -p "Confirmation du mot de passe pour $RESCUE : " RESCUE_PASSWORD_CONFIRM
echo
if [ "$RESCUE_PASSWORD" != "$RESCUE_PASSWORD_CONFIRM" ]; then
  echo "❌ Les mots de passe pour $RESCUE ne correspondent pas."
  exit 1
fi

echo "[*] Nettoyage disque $DISK"
wipefs -a $DISK
parted -s $DISK mklabel gpt

echo "[*] Création des partitions"

# BIOS boot
parted -s $DISK mkpart primary 1MiB 2MiB
parted -s $DISK set 1 bios_grub on

# /boot (512M)
parted -s $DISK mkpart primary fat32 2MiB 514MiB
parted -s $DISK set 2 boot on

# swap (2G)
parted -s $DISK mkpart primary linux-swap 514MiB 2562MiB

# / (5G)
parted -s $DISK mkpart primary ext4 2562MiB 7682MiB

# /var (4G)
parted -s $DISK mkpart primary ext4 7682MiB 11778MiB

# /usr (4G)
parted -s $DISK mkpart primary ext4 11778MiB 15874MiB

# /home (reste)
parted -s $DISK mkpart primary ext4 15874MiB 100%

echo "[*] Formatage des partitions"
mkfs.fat -F32 ${DISK}2
mkswap ${DISK}3
mkfs.ext4 ${DISK}4
mkfs.ext4 ${DISK}5
mkfs.ext4 ${DISK}6
mkfs.ext4 ${DISK}7

echo "[*] Montage des partitions"
mount ${DISK}4 /mnt || { echo "❌ Erreur montage /"; exit 1; }
mkdir -p /mnt/{boot,var,usr,home}

mount ${DISK}2 /mnt/boot || { echo "❌ Erreur montage /boot"; exit 1; }
mount ${DISK}5 /mnt/var || { echo "❌ Erreur montage /var"; exit 1; }
mount ${DISK}6 /mnt/usr || { echo "❌ Erreur montage /usr"; exit 1; }
mount ${DISK}7 /mnt/home || { echo "❌ Erreur montage /home"; exit 1; }
swapon ${DISK}3

echo "[*] Partitions (lsblk):"
lsblk

echo "[*] Synchronisation de l'heure"
timedatectl set-ntp true

echo "[*] Installation de base + dhcpcd"
pacstrap /mnt base base-devel linux linux-firmware vim sudo openssh grub dhcpcd --noconfirm

ls -l /mnt/usr/bin/init
if [ ! -f /mnt/usr/bin/init ]; then
  echo "❌ Problème : init n'est pas présent dans /usr/bin !" >&2
  exit 1
fi

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

echo "[*] Création de l'utilisateur $ADMIN (sudo SANS mot de passe)"
useradd -m -G wheel -s /bin/bash $ADMIN
echo "$ADMIN:$PASSWORD" | chpasswd

echo "[*] Création de l'utilisateur $RESCUE (sudo AVEC mot de passe)"
useradd -m -G wheel -s /bin/bash $RESCUE
echo "$RESCUE:$RESCUE_PASSWORD" | chpasswd

echo "[*] Configuration sudoers"
echo "$ADMIN ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/$ADMIN
echo "$RESCUE ALL=(ALL) ALL" >> /etc/sudoers.d/$RESCUE

chmod 440 /etc/sudoers.d/$ADMIN /etc/sudoers.d/$RESCUE

echo "[*] Journalisation des commandes sudo"
echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers

echo "[*] Regénère l'initramfs"
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck usr)/' /etc/mkinitcpio.conf
mkinitcpio -P

echo "[*] Installation de GRUB en mode BIOS"
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

echo "[*] Sécurisation des points de montage (fstab)"
cat <<FSTAB > /etc/fstab
/dev/sda2   /boot   vfat    defaults,nosuid,nodev,noexec     0  2
/dev/sda3   none    swap    sw                               0  0
/dev/sda4   /       ext4    defaults                        0  1
/dev/sda5   /var    ext4    defaults,nosuid,nodev,noexec    0  2
/dev/sda6   /usr    ext4    defaults,nodev                  0  2
/dev/sda7   /home   ext4    defaults,nosuid,nodev,noexec    0  2
tmpfs       /tmp    tmpfs   defaults,nosuid,nodev,noexec,size=512M  0  0
proc        /proc   proc    defaults,hidepid=2              0  0
FSTAB

mkdir -p /tmp
chmod 1777 /tmp

echo "[*] Activation des services essentiels"
systemctl enable sshd
systemctl enable systemd-timesyncd
systemctl enable dhcpcd

echo "[*] Hardening SSH"
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
EOF

echo "[*] Démontage propre de /mnt"
swapoff ${DISK}3
umount -R /mnt

if [ $? -eq 0 ]; then
  echo "[*] ✅ Installation terminée ! Redémarre la VM et enlève l'ISO."
  systemctl poweroff
else
  echo "[!] ⚠️ Problème lors du démontage de /mnt. Vérifie manuellement." >&2
  exit 1
fi
