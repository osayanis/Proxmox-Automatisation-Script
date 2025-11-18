#!/bin/bash

# Fonction pour afficher le menu de création de conteneurs
menu_creation() {
    clear
    echo "=============================================="
    echo "Création de Conteneurs Proxmox - Menu Principal"
    echo "=============================================="
    echo "1. Créer un ou plusieurs conteneurs"
    echo "2. Liste des templates disponibles"
    echo "3. Quitter"
    echo "=============================================="
    read -p "Sélectionnez une option : " option
    case $option in
        1) creer_conteneur ;;
        2) lister_templates ;;
        3) exit 0 ;;
        *) echo "Option invalide. Essayez à nouveau." && sleep 2 && menu_creation ;;
    esac
}

# Fonction pour lister les templates disponibles
lister_templates() {
    echo "Liste des templates disponibles :"
    ls /var/lib/vz/template/cache/
    echo "=============================================="
    echo "Si la template que vous voulez n'est pas présente, entrez l'URL pour la télécharger."
    read -p "Voulez-vous télécharger une template ? (y/n) : " reponse
    if [ "$reponse" == "y" ]; then
        read -p "Entrez l'URL de la template : " url
        # Télécharger la template
        wget -P /var/lib/vz/template/cache/ $url
        echo "Template téléchargée avec succès."
    fi
    sleep 2
    menu_creation
}

# Fonction pour générer un ID unique pour le conteneur
generate_vmid() {
    # Recherche du plus grand VMID existant et incrémentation
    vmid=$(pveam available | grep -oP '\d+' | sort -n | tail -n 1)
    vmid=$((vmid+1))  # Incrémente l'ID pour garantir qu'il soit unique

    # Vérifier que l'ID n'existe pas déjà
    while pct status $vmid &>/dev/null; do
        vmid=$((vmid+1))
    done

    echo $vmid
}

# Fonction pour créer un ou plusieurs conteneurs
creer_conteneur() {
    read -p "Combien de conteneurs voulez-vous créer ? " nb_conteneurs
    for (( i=1; i<=$nb_conteneurs; i++ ))
    do
        echo "Création du conteneur $i"

        # Demande des paramètres pour chaque conteneur
        read -p "Nom du conteneur : " nom
        read -p "RAM (en Mo) : " ram
        read -p "Disque (en Go) : " disque
        read -p "Adresse IP : " ip
        read -p "Nom du template (exemple : ubuntu-20.04-standard_20.04-1_amd64.tar.zst) : " template

        # Demander le mot de passe pour la machine
        read -sp "Entrez le mot de passe pour le conteneur : " password
        echo  # Pour un retour à la ligne après avoir saisi le mot de passe

        # Demander le DNS souhaité
        read -p "Entrez l'adresse DNS souhaitée (exemple : 8.8.8.8) : " dns

        # Vérification de la présence du template
        if [ ! -f "/var/lib/vz/template/cache/$template" ]; then
            echo "Le template n'existe pas. Vous allez être redirigé pour le télécharger."
            lister_templates
        fi

        # Générer un ID unique pour le conteneur
        vmid=$(generate_vmid)
        echo "ID du conteneur : $vmid"

        # Gestion des disques (local et local-lvm) - Utilisation de "local" ou "local-lvm"
        read -p "Sélectionnez le stockage pour le disque (local/local-lvm) : " stockage
        case $stockage in
            "local")
                disque_option="-storage local -rootfs $disque"
                ;;
            "local-lvm")
                disque_option="-storage local-lvm -rootfs $disque"
                ;;
            *)
                echo "Option de stockage invalide, utilisation de 'local' par défaut."
                disque_option="-storage local -rootfs $disque"
                ;;
        esac

        # Création du conteneur avec un ID unique et les paramètres spécifiés, y compris le mot de passe
        echo "Création du conteneur $nom avec $ram Mo de RAM, $disque Go de disque, IP $ip, DNS $dns."
        pct create $vmid /var/lib/vz/template/cache/$template -hostname $nom -memory $ram $disque_option -net0 name=eth0,bridge=vmbr0,ip=$ip/24,gw=192.168.20.254 -password $password

        # Configuration du DNS
        pct exec $vmid -- bash -c "echo 'nameserver $dns' > /etc/resolv.conf"
        echo "Conteneur $nom créé avec succès et mot de passe défini !"
    done
    sleep 2
    menu_creation
}

# Lancer le menu principal
menu_creation