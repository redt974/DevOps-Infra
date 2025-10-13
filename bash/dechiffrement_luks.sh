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
