#!/bin/bash

# Fonction pour afficher le menu de création
menu_creation() {
    clear
    echo "=============================================="
    echo "Création de Conteneurs et Machines Virtuelles - Menu Principal"
    echo "=============================================="
    echo "1. Créer un ou plusieurs conteneurs"
    echo "2. Créer un ou plusieurs machines virtuelles (VM)"
    echo "3. Liste des templates disponibles"
    echo "4. Liste des ISO disponibles"
    echo "5. Quitter"
    echo "=============================================="
    read -p "Sélectionnez une option : " option
    case $option in
        1) creer_conteneur ;;
        2) creer_vm ;;
        3) lister_templates ;;
        4) lister_iso ;;
        5) exit 0 ;;
        *) echo "Option invalide. Essayez à nouveau." && sleep 2 && menu_creation ;;
    esac
}

# Fonction pour lister les templates disponibles avec recherche par mot-clé
lister_templates() {
    read -p "Entrez un mot-clé pour rechercher des templates (ex : debian) : " keyword
    echo "Recherche de templates contenant '$keyword' :"
    # On filtre pour ne garder que les archives (tar.gz, tar.zst etc)
    found_templates=$(ls /var/lib/vz/template/cache/ | grep -i "$keyword")
    
    if [ -z "$found_templates" ]; then
        echo "Aucun template trouvé pour '$keyword'."
        read -p "Voulez-vous télécharger une template ? (y/n) : " reponse
        if [ "$reponse" == "y" ]; then
            read -p "Entrez l'URL de la template : " url
            wget -P /var/lib/vz/template/cache/ $url
            # On tente de récupérer le nom du fichier depuis l'URL pour mettre à jour la variable
            template=$(basename "$url")
            echo "Template téléchargée avec succès."
        fi
    else
        echo "Templates trouvées :"
        select template_choice in $found_templates "Télécharger une nouvelle template via une url"; do
            case $template_choice in
                "Télécharger une nouvelle template via une url")
                    read -p "Entrez l'URL de la template : " url
                    wget -P /var/lib/vz/template/cache/ $url
                    template=$(basename "$url")
                    echo "Template téléchargée avec succès."
                    break
                    ;;
                *)
                    # Vérification
                    template_path="/var/lib/vz/template/cache/$template_choice"
                    if [ -n "$template_choice" ] && [ -f "$template_path" ]; then
                        echo "Vous avez sélectionné le template : $template_choice"
                        # IMPORTANT : Mise à jour de la variable globale template
                        template="$template_choice"
                        break
                    else
                        echo "Choix invalide ou fichier introuvable."
                    fi
                    ;;
            esac
        done
    fi
}

# Fonction pour lister les ISO disponibles
lister_iso() {
    echo "Liste des ISO disponibles :"
    ls /var/lib/vz/iso/
    echo "=============================================="
    echo "Si l'ISO que vous voulez n'est pas présent, entrez l'URL pour le télécharger."
    read -p "Voulez-vous télécharger un ISO ? (y/n) : " reponse
    if [ "$reponse" == "y" ]; then
        read -p "Entrez l'URL de l'ISO : " url
        wget -P /var/lib/vz/iso/ $url
        echo "ISO téléchargé avec succès."
    fi
    sleep 2
    menu_creation
}

# Fonction pour générer un ID unique pour le conteneur ou la VM
generate_vmid() {
    # Méthode plus fiable pour Proxmox : utilise pvesh pour obtenir le prochain ID libre
    # Si pvesh échoue (pas sur proxmox), on garde ta logique de fallback, 
    # mais attention 'pveam' ne liste pas les VMIDs utilisés.
    
    # On cherche le prochain ID libre à partir de 100
    vmid=100
    while pct status $vmid &>/dev/null || qm status $vmid &>/dev/null; do
        vmid=$((vmid+1))
    done

    echo $vmid
}

# Fonction pour créer un ou plusieurs conteneurs
creer_conteneur() {
    read -p "Combien de conteneurs voulez-vous créer ? " nb_conteneurs
    for (( i=1; i<=$nb_conteneurs; i++ ))
    do
        echo "----------------------------------------------"
        echo "Création du conteneur $i sur $nb_conteneurs"

        # Demande des paramètres
        read -p "Nom du conteneur (hostname) : " nom
        read -p "RAM (en Mo) : " ram
        read -p "Disque (en Go) : " disque
        read -p "Adresse IP (ex: 192.168.1.50) : " ip
        
        # Gestion du Template
        read -p "Nom du template (laisser vide pour rechercher) : " template_input
        
        if [ -z "$template_input" ]; then
            lister_templates
        else
            template=$template_input
            # Vérification si le template entré manuellement existe
            if [ ! -f "/var/lib/vz/template/cache/$template" ]; then
                echo "Le template '$template' n'existe pas."
                lister_templates
            fi
        fi

        # Si après la recherche, la variable template est toujours vide ou invalide
        if [ ! -f "/var/lib/vz/template/cache/$template" ]; then
            echo "Erreur : Aucun template valide sélectionné. Annulation de ce conteneur."
            continue
        fi

        read -sp "Entrez le mot de passe root pour le conteneur : " password
        echo ""
        read -p "Entrez l'adresse DNS (exemple : 8.8.8.8) : " dns

        vmid=$(generate_vmid)
        echo "ID attribué au conteneur : $vmid"

        read -p "Sélectionnez le stockage (local/local-lvm) [défaut: local-lvm] : " stockage
        stockage=${stockage:-local-lvm} # Valeur par défaut si vide

        case $stockage in
            "local") disque_option="-storage local -rootfs $disque" ;;
            "local-lvm") disque_option="-storage local-lvm -rootfs $disque" ;;
            *) echo "Stockage invalide, 'local-lvm' utilisé." && disque_option="-storage local-lvm -rootfs $disque" ;;
        esac

        echo "Création en cours..."
        # Commande de création
        pct create $vmid "/var/lib/vz/template/cache/$template" \
            -hostname "$nom" \
            -memory "$ram" \
            $disque_option \
            -net0 name=eth0,bridge=vmbr0,ip=$ip/24,gw=192.168.20.254 \
            -password "$password" \
            -features nesting=1

        # Configuration DNS
        if [ $? -eq 0 ]; then
            pct exec $vmid -- bash -c "echo 'nameserver $dns' > /etc/resolv.conf"
            echo "Conteneur $nom ($vmid) créé avec succès !"
        else
            echo "Erreur lors de la création du conteneur."
        fi
    done
    read -p "Appuyez sur Entrée pour revenir au menu..."
    menu_creation
}

# Fonction pour créer un ou plusieurs machines virtuelles (VM)
creer_vm() {
    # (Je n'ai pas modifié cette fonction, mais pense à appliquer la même logique pour l'ISO si besoin)
    read -p "Combien de machines virtuelles voulez-vous créer ? " nb_vms
    for (( i=1; i<=$nb_vms; i++ ))
    do
        echo "Création de la VM $i"
        read -p "Nom de la VM : " nom
        read -p "RAM (en Mo) : " ram
        read -p "Disque (en Go) : " disque
        read -p "Adresse IP : " ip
        read -p "Nom de l'ISO (exemple : debian-12.iso) : " iso
        read -sp "Entrez le mot de passe pour la VM : " password
        echo ""
        read -p "Entrez l'adresse DNS : " dns

        if [ ! -f "/var/lib/vz/iso/$iso" ]; then
            echo "L'ISO spécifié n'existe pas."
            lister_iso
            # Note : ici aussi, tu devras t'assurer que la variable 'iso' est mise à jour par lister_iso
        fi

        vmid=$(generate_vmid)
        echo "ID de la VM : $vmid"

        read -p "Sélectionnez le stockage (local/local-lvm) : " stockage
        
        # Sécurisation du choix stockage
        if [[ "$stockage" != "local" && "$stockage" != "local-lvm" ]]; then
            stockage="local"
        fi

        echo "Création de la VM $nom..."
        qm create $vmid --name $nom --memory $ram --net0 model=virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --scsi0 ${stockage}:${disque} --cdrom /var/lib/vz/iso/$iso --boot order=scsi0;ide2 --ipconfig0 ip=$ip/24,gw=192.168.20.254

        # Cloud-init settings (nécessite un disque cloudinit ajouté si tu veux utiliser ciuser/cipassword)
        # Attention: qm create par défaut n'ajoute pas de lecteur cloud-init automatiquement sauf si spécifié
        # Ajout du lecteur cloudinit pour que les commandes suivantes fonctionnent :
        qm set $vmid --ide2 ${stockage}:cloudinit
        qm set $vmid --ciuser root --cipassword "$password"
        qm set $vmid --nameserver "$dns"
        
        echo "VM $nom créée !"
    done
    sleep 2
    menu_creation
}

# Lancer le menu principal
menu_creation