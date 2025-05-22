#!/bin/bash

# Vérification si root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Ce script doit être exécuté en tant que root."
   exit 1
fi

echo "💾 --- Initialisation du chiffrement sur /dev/sdb1 ---"

# Variables
DISK="/dev/sdb"
PARTITION="${DISK}1"
MAPPER_NAME="web"
MOUNT_POINT="/data/http"
DECRYPT_SCRIPT="/usr/local/bin/decrypt_web.sh"
BASH_PROFILE="/home/localadm/.bash_profile"

# 1. Création de la partition sur /dev/sdb
echo "➡️ Création de la partition sur $DISK"
fdisk $DISK <<EOF
n
p
1


w
EOF

# 2. Vérification de la partition
echo "📂 Vérification de la partition..."
lsblk $DISK

# 3. Création du répertoire de publication si non existant
echo "📂 Création du répertoire $MOUNT_POINT"
mkdir -p $MOUNT_POINT

# 4. Chiffrement avec cryptsetup
echo "🔐 Chiffrement LUKS sur $PARTITION"
cryptsetup luksFormat $PARTITION

# 5. Ouverture du volume chiffré
echo "🔓 Ouverture de $PARTITION avec le nom '$MAPPER_NAME'"
cryptsetup open $PARTITION $MAPPER_NAME

# 6. Formatage du volume en ext4
echo "📝 Formatage en ext4 de /dev/mapper/$MAPPER_NAME"
mkfs.ext4 /dev/mapper/$MAPPER_NAME

# 7. Montage du volume
echo "💾 Montage sur $MOUNT_POINT"
mount /dev/mapper/$MAPPER_NAME $MOUNT_POINT

# 8. Vérification
df -h | grep $MOUNT_POINT

echo "✅ Volume chiffré monté sur $MOUNT_POINT"

# 9. Création du script de déchiffrement complet
echo "🛠️ Création du script de déchiffrement : $DECRYPT_SCRIPT"
cat <<'EOF' > $DECRYPT_SCRIPT
#!/bin/bash

DEVICE="/dev/sdb1"
MAPPER_NAME="web"
MOUNT_POINT="/data/http"

# Vérifiez si le volume est déjà déchiffré
if ! lsblk | grep -q "$MAPPER_NAME"; then
    # Déchiffrez le volume
    sudo cryptsetup luksOpen $DEVICE $MAPPER_NAME
    # Vérifiez si le déchiffrement a réussi
    if [ $? -eq 0 ]; then
        # Vérifiez si le point de montage est déjà utilisé
        if ! mountpoint -q $MOUNT_POINT; then
            # Montez le volume
            sudo mount /dev/mapper/$MAPPER_NAME $MOUNT_POINT
            if [ $? -eq 0 ]; then
                echo "Le volume a été déchiffré et monté avec succès."
            else
                echo "Échec du montage du volume."
            fi
        else
            echo "Le point de montage est déjà utilisé."
        fi
    else
        echo "Échec du déchiffrement du volume."
    fi
else
    echo "Le volume est déjà déchiffré."
    # Vérifiez si le volume est monté
    if ! mountpoint -q $MOUNT_POINT; then
        # Montez le volume
        sudo mount /dev/mapper/$MAPPER_NAME $MOUNT_POINT
        if [ $? -eq 0 ]; then
            echo "Le volume a été monté avec succès."
        else
            echo "Échec du montage du volume."
        fi
    else
        echo "Le volume est déjà monté."
    fi
fi
EOF

# 10. Permission d'exécution
chmod +x $DECRYPT_SCRIPT
echo "✅ Script $DECRYPT_SCRIPT prêt."

# 11. Ajout dans le bash_profile de localadm (si pas déjà présent)
if grep -Fxq "$DECRYPT_SCRIPT" $BASH_PROFILE
then
    echo "ℹ️ Le script est déjà présent dans $BASH_PROFILE"
else
    echo "➡️ Ajout du script dans $BASH_PROFILE"
    echo "$DECRYPT_SCRIPT" >> $BASH_PROFILE
fi

# 12. Propriétés utilisateurs (utile si le home de localadm a été manipulé)
chown localadm:localadm $BASH_PROFILE

echo "🎉 Script complet exécuté avec succès !"
