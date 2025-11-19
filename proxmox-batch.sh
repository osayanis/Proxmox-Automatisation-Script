#!/bin/bash

# ============================================================
# SCRIPT D'AUTOMATISATION PROXMOX (CORRIGÉ)
# ============================================================

# --- Fonction : Générer un VMID unique ---
generate_vmid() {
    vmid=100
    while pct status $vmid &>/dev/null || qm status $vmid &>/dev/null; do
        vmid=$((vmid+1))
    done
    echo $vmid
}

# --- Fonction : Lister et Sélectionner des Templates ---
lister_templates() {
    echo "--- Recherche de templates ---"
    read -p "Entrez un mot-clé (ex: debian, ubuntu) ou laissez vide pour tout voir : " keyword
    
    if [ -z "$keyword" ]; then
        found_templates=$(ls /var/lib/vz/template/cache/)
    else
        found_templates=$(ls /var/lib/vz/template/cache/ | grep -i "$keyword")
    fi

    if [ -z "$found_templates" ]; then
        echo "Aucun template trouvé pour '$keyword'."
        read -p "Voulez-vous télécharger un template via URL ? (y/n) : " reponse
        if [ "$reponse" == "y" ]; then
            read -p "Entrez l'URL du template : " url
            wget -P /var/lib/vz/template/cache/ "$url"
            template=$(basename "$url")
            echo "Template téléchargé : $template"
        fi
    else
        echo "Templates disponibles :"
        PS3="Sélectionnez un numéro : "
        select template_choice in $found_templates "Télécharger via URL" "Annuler"; do
            case $template_choice in
                "Télécharger via URL")
                    read -p "Entrez l'URL du template : " url
                    wget -P /var/lib/vz/template/cache/ "$url"
                    template=$(basename "$url")
                    echo "Template téléchargé : $template"
                    break
                    ;;
                "Annuler")
                    template=""
                    break
                    ;;
                *)
                    if [ -n "$template_choice" ]; then
                        template="$template_choice"
                        echo "Template sélectionné : $template"
                        break
                    else
                        echo "Choix invalide."
                    fi
                    ;;
            esac
        done
    fi
}

# --- Fonction : Lister et Sélectionner des ISOs ---
lister_iso() {
    echo "--- Liste des ISOs ---"
    found_isos=$(ls /var/lib/vz/iso/)

    if [ -z "$found_isos" ]; then
        echo "Aucun ISO trouvé dans /var/lib/vz/iso/."
        read -p "Télécharger un ISO ? (y/n) : " reponse
        if [ "$reponse" == "y" ]; then
            read -p "Entrez l'URL de l'ISO : " url
            wget -P /var/lib/vz/iso/ "$url"
            iso=$(basename "$url")
            echo "ISO téléchargé : $iso"
        fi
    else
        PS3="Sélectionnez un numéro : "
        select iso_choice in $found_isos "Télécharger via URL" "Annuler"; do
            case $iso_choice in
                "Télécharger via URL")
                    read -p "Entrez l'URL de l'ISO : " url
                    wget -P /var/lib/vz/iso/ "$url"
                    iso=$(basename "$url")
                    echo "ISO téléchargé : $iso"
                    break
                    ;;
                "Annuler")
                    iso=""
                    break
                    ;;
                *)
                    if [ -n "$iso_choice" ]; then
                        iso="$iso_choice"
                        echo "ISO sélectionné : $iso"
                        break
                    else
                        echo "Choix invalide."
                    fi
                    ;;
            esac
        done
    fi
}

# --- Fonction : Créer Conteneur(s) ---
creer_conteneur() {
    read -p "Combien de conteneurs voulez-vous créer ? " nb_conteneurs
    for (( i=1; i<=$nb_conteneurs; i++ ))
    do
        echo "=============================================="
        echo "Création du CONTENEUR $i / $nb_conteneurs"
        echo "=============================================="

        read -p "Nom du conteneur (hostname) : " nom
        read -p "RAM (Mo) : " ram
        read -p "Disque (Go) : " disque
        read -p "Adresse IP (ex: 192.168.20.50) : " ip
        
        read -p "Nom du template (laisser vide pour rechercher) : " template_input
        if [ -z "$template_input" ]; then
            lister_templates
        else
            template="$template_input"
        fi

        if [ ! -f "/var/lib/vz/template/cache/$template" ] || [ -z "$template" ]; then
            echo "ERREUR : Template introuvable ou non sélectionné. Annulation."
            continue 
        fi

        read -sp "Mot de passe root : " password
        echo ""
        read -p "Serveur DNS (ex: 8.8.8.8) : " dns
        read -p "Stockage (local/local-lvm) [défaut: local-lvm] : " stockage
        stockage=${stockage:-local-lvm}

        vmid=$(generate_vmid)
        echo "-> ID généré : $vmid"
        echo "-> Création en cours..."

        pct create $vmid "/var/lib/vz/template/cache/$template" \
            -hostname "$nom" \
            -memory "$ram" \
            -storage "$stockage" -rootfs "$disque" \
            -net0 name=eth0,bridge=vmbr0,ip=$ip/24,gw=192.168.20.254 \
            -password "$password" \
            -features nesting=1

        if [ $? -eq 0 ]; then
            pct exec $vmid -- bash -c "echo 'nameserver $dns' > /etc/resolv.conf"
            echo "SUCCESS : Conteneur $nom ($vmid) créé !"
        else
            echo "ECHEC : Erreur lors de la création."
        fi
    done
    read -p "Appuyez sur Entrée pour revenir au menu..."
    menu_creation
}

# --- Fonction : Créer Machine(s) Virtuelle(s) ---
creer_vm() {
    read -p "Combien de VMs voulez-vous créer ? " nb_vms
    for (( i=1; i<=$nb_vms; i++ ))
    do
        echo "=============================================="
        echo "Création de la VM $i / $nb_vms"
        echo "=============================================="

        read -p "Nom de la VM : " nom
        read -p "RAM (Mo) : " ram
        read -p "Disque (Go) : " disque
        read -p "Adresse IP (ex: 192.168.20.51) : " ip

        read -p "Nom de l'ISO (laisser vide pour rechercher) : " iso_input
        if [ -z "$iso_input" ]; then
            lister_iso
        else
            iso="$iso_input"
        fi

        if [ ! -f "/var/lib/vz/iso/$iso" ] || [ -z "$iso" ]; then
            echo "ERREUR : ISO introuvable ou non sélectionné. Annulation."
            continue
        fi

        read -sp "Mot de passe (Cloud-init, si supporté) : " password
        echo ""
        read -p "Serveur DNS : " dns
        read -p "Stockage (local/local-lvm) [défaut: local-lvm] : " stockage
        stockage=${stockage:-local-lvm}

        vmid=$(generate_vmid)
        echo "-> ID généré : $vmid"
        echo "-> Création en cours..."

        # CORRECTION MAJEURE ICI :
        # 1. Utilisation de "local:iso/$iso" au lieu du chemin absolu
        # 2. Ajout de guillemets autour de "--boot order=..." pour éviter l'erreur Bash
        
        qm create $vmid --name "$nom" \
            --memory "$ram" \
            --net0 model=virtio,bridge=vmbr0 \
            --scsihw virtio-scsi-pci \
            --scsi0 "$stockage:$disque" \
            --cdrom "local:iso/$iso" \
            --boot "order=scsi0;ide2;net0" \
            --ipconfig0 ip=$ip/24,gw=192.168.20.254

        # Vérification si la commande qm create a réussi
        if [ $? -eq 0 ]; then
            # Configuration optionnelle Cloud-init
            qm set $vmid --ide2 "$stockage:cloudinit"
            qm set $vmid --ciuser root --cipassword "$password"
            qm set $vmid --nameserver "$dns"
            echo "SUCCESS : VM $nom ($vmid) créée !"
        else
            echo "ERREUR CRITIQUE : La VM n'a pas pu être créée."
        fi
    done
    read -p "Appuyez sur Entrée pour revenir au menu..."
    menu_creation
}

# --- MENU PRINCIPAL ---
menu_creation() {
    clear
    echo "=============================================="
    echo "   PROXMOX AUTO-INSTALLER - MENU PRINCIPAL    "
    echo "=============================================="
    echo "1. Créer un ou plusieurs conteneurs (LXC)"
    echo "2. Créer un ou plusieurs machines virtuelles (VM)"
    echo "3. Voir les templates disponibles"
    echo "4. Voir les ISO disponibles"
    echo "5. Quitter"
    echo "=============================================="
    read -p "Votre choix : " option
    case $option in
        1) creer_conteneur ;;
        2) creer_vm ;;
        3) lister_templates; read -p "Appuyez sur Entrée..." ; menu_creation ;;
        4) lister_iso; read -p "Appuyez sur Entrée..." ; menu_creation ;;
        5) echo "Au revoir !"; exit 0 ;;
        *) echo "Option invalide." && sleep 1 && menu_creation ;;
    esac
}

# Lancement du script
menu_creation