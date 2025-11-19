#!/bin/bash

# ============================================================
# SCRIPT D'AUTOMATISATION PROXMOX (Corrigé : Chemins ISO standards)
# ============================================================

# --- CONFIGURATION DES LIMITES ---
# Chemins standards Proxmox
PATH_ISO="/var/lib/vz/template/iso"
PATH_TMPL="/var/lib/vz/template/cache"

# --- Fonction : Récupérer les infos Réseau réelles ---
detecter_reseau() {
    INTERFACE="vmbr0"
    REAL_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)
    REAL_BROADCAST=$(ip -4 addr show $INTERFACE | grep -oP '(?<=brd )[\d.]+')
}

# --- Fonction : Calculer la RAM Max disponible ---
get_max_ram() {
    TOTAL_FREE=$(free -m | awk '/^Mem:/{print $7}')
    MAX_RAM_CALC=$((TOTAL_FREE - 512)) # Marge de sécurité
    if [ $MAX_RAM_CALC -lt 512 ]; then MAX_RAM_CALC=512; fi
    echo $MAX_RAM_CALC
}

# --- Fonction : Calculer l'Espace Disque Max disponible ---
get_max_disk() {
    local storage=$1
    if [ "$storage" == "local" ]; then
        df -BG /var/lib/vz | awk 'NR==2 {print $4}' | sed 's/G//'
    else
        vgs pve --noheadings -o vg_free --units g | awk '{print int($1)}'
    fi
}

# --- Fonction : Validation et demande d'IP ---
demander_ip() {
    detecter_reseau
    local ip_valide=false
    local input_ip=""
    
    echo "   -> Infos détectées : Passerelle=$REAL_GATEWAY | Broadcast=$REAL_BROADCAST"

    while [ "$ip_valide" = false ]; do
        read -p "Adresse IP (ex: 192.168.20.50) : " input_ip
        
        if [[ $input_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            IFS='.' read -r -a octets <<< "$input_ip"
            o1=$((10#${octets[0]})); o2=$((10#${octets[1]})); o3=$((10#${octets[2]})); o4=$((10#${octets[3]}))

            if (( o1 > 255 || o2 > 255 || o3 > 255 || o4 > 255 )); then
                echo "Erreur : Max 255."
            elif [ "$input_ip" == "$REAL_GATEWAY" ]; then
                echo "Erreur : IP Gateway interdite."
            elif [ "$input_ip" == "$REAL_BROADCAST" ]; then
                echo "Erreur : IP Broadcast interdite."
            elif (( o4 == 0 )); then
                echo "Erreur : .0 interdit."
            else
                ip_valide=true
            fi
        else
            echo "Erreur : Format invalide."
        fi
    done
    VAL_IP_FINALE="$input_ip"
}

# --- Fonction : Générer un VMID unique ---
generate_vmid() {
    vmid=100
    while pct status $vmid &>/dev/null || qm status $vmid &>/dev/null; do
        vmid=$((vmid+1))
    done
    echo $vmid
}

# --- Fonction : Lister Templates ---
lister_templates() {
    echo "--- Recherche de templates ---"
    read -p "Mot-clé (laisser vide pour tout voir) : " keyword
    template=""

    if [ -z "$keyword" ]; then
        found_templates=$(ls $PATH_TMPL)
    else
        found_templates=$(ls $PATH_TMPL | grep -i "$keyword")
    fi

    if [ -z "$found_templates" ]; then
        echo "Aucun template trouvé."
        read -p "Télécharger via URL ? (y/n) : " reponse
        if [ "$reponse" == "y" ]; then
            read -p "URL : " url
            wget -P $PATH_TMPL "$url"
            if [ $? -ne 0 ]; then
                echo "ERREUR Téléchargement."
                rm -f "$PATH_TMPL/$(basename "$url")"
                template=""
            else
                template=$(basename "$url")
            fi
        fi
    else
        PS3="Choix : "
        select template_choice in $found_templates "Télécharger via URL" "Annuler"; do
            case $template_choice in
                "Télécharger via URL")
                    read -p "URL : " url
                    wget -P $PATH_TMPL "$url"
                    if [ $? -ne 0 ]; then
                        echo "ERREUR Téléchargement."
                        rm -f "$PATH_TMPL/$(basename "$url")"
                        template=""
                    else
                        template=$(basename "$url")
                    fi
                    break ;;
                "Annuler") template=""; break ;;
                *) [ -n "$template_choice" ] && template="$template_choice" && break ;;
            esac
        done
    fi
}

# --- Fonction : Lister ISOs (CORRIGÉE) ---
lister_iso() {
    echo "--- Liste des ISOs ---"
    # On s'assure que le dossier existe
    mkdir -p $PATH_ISO
    
    found_isos=$(ls $PATH_ISO)
    iso=""

    if [ -z "$found_isos" ]; then
        echo "Aucun ISO trouvé dans $PATH_ISO."
        read -p "Télécharger via URL ? (y/n) : " reponse
        if [ "$reponse" == "y" ]; then
            read -p "URL : " url
            wget -P $PATH_ISO "$url"
            if [ $? -ne 0 ]; then
                echo "ERREUR Téléchargement."
                rm -f "$PATH_ISO/$(basename "$url")"
                iso=""
            else
                iso=$(basename "$url")
            fi
        fi
    else
        PS3="Choix : "
        select iso_choice in $found_isos "Télécharger via URL" "Annuler"; do
            case $iso_choice in
                "Télécharger via URL")
                    read -p "URL : " url
                    wget -P $PATH_ISO "$url"
                    if [ $? -ne 0 ]; then
                        echo "ERREUR Téléchargement."
                        rm -f "$PATH_ISO/$(basename "$url")"
                        iso=""
                    else
                        iso=$(basename "$url")
                    fi
                    break ;;
                "Annuler") iso=""; break ;;
                *) [ -n "$iso_choice" ] && iso="$iso_choice" && break ;;
            esac
        done
    fi
}

# --- Fonction : Créer Conteneur ---
creer_conteneur() {
    read -p "Nombre de conteneurs à créer : " nb_conteneurs
    for (( i=1; i<=$nb_conteneurs; i++ ))
    do
        echo "=============================================="
        echo "Création du CONTENEUR $i / $nb_conteneurs"
        echo "=============================================="

        while true; do
            read -p "Nom (lettres/chiffres/-) : " nom
            if [[ "$nom" =~ ^[a-zA-Z0-9-]+$ ]]; then break; else echo "Nom invalide."; fi
        done
        
        read -p "Stockage (local/local-lvm) [défaut: local-lvm] : " stockage
        stockage=${stockage:-local-lvm}
        if [[ "$stockage" != "local" && "$stockage" != "local-lvm" ]]; then stockage="local-lvm"; fi
        
        LIMIT_RAM=$(get_max_ram)
        LIMIT_DISK=$(get_max_disk "$stockage")
        echo "   -> Max Disp: RAM=${LIMIT_RAM}Mo | Disque=${LIMIT_DISK}Go"

        while true; do
            read -p "RAM (Mo) [Min: 512 - Max: $LIMIT_RAM] : " ram
            if [[ ! "$ram" =~ ^[0-9]+$ ]]; then continue; fi
            if (( ram < 512 || ram > LIMIT_RAM )); then echo "Erreur RAM."; else break; fi
        done

        while true; do
            read -p "Disque (Go) [Min: 2 - Max: $LIMIT_DISK] : " disque
            if [[ ! "$disque" =~ ^[0-9]+$ ]]; then continue; fi
            if (( disque < 2 || disque > LIMIT_DISK )); then echo "Erreur Disque."; else break; fi
        done

        demander_ip
        ip=$VAL_IP_FINALE 
        
        read -p "Template (vide pour chercher) : " template_input
        if [ -z "$template_input" ]; then lister_templates; else template="$template_input"; fi

        if [ -z "$template" ] || [ ! -f "$PATH_TMPL/$template" ]; then
            echo "ERREUR FATALE : Pas de template. Retour menu."
            read -p "Entrée..."
            menu_creation
            return
        fi

        while true; do
            read -sp "Mot de passe root (Min 5 char) : " password
            echo ""
            if [ ${#password} -ge 5 ]; then break; else echo "Erreur : Min 5 caractères."; fi
        done

        read -p "DNS : " dns
        vmid=$(generate_vmid)
        echo "-> Création CT $vmid ($nom)..."

        pct create $vmid "$PATH_TMPL/$template" \
            -hostname "$nom" \
            -memory "$ram" \
            -storage "$stockage" -rootfs "$disque" \
            -net0 name=eth0,bridge=vmbr0,ip=$ip/24,gw=$REAL_GATEWAY \
            -password "$password" \
            -features nesting=1

        if [ $? -eq 0 ]; then
            pct exec $vmid -- bash -c "echo 'nameserver $dns' > /etc/resolv.conf"
            echo "SUCCESS : Conteneur $nom créé !"
        else
            echo "ECHEC création."
        fi
    done
    read -p "Appuyez sur Entrée..."
    menu_creation
}

# --- Fonction : Créer VM ---
creer_vm() {
    read -p "Nombre de VMs à créer : " nb_vms
    for (( i=1; i<=$nb_vms; i++ ))
    do
        echo "=============================================="
        echo "Création de la VM $i / $nb_vms"
        echo "=============================================="

        while true; do
            read -p "Nom (lettres/chiffres/-) : " nom
            if [[ "$nom" =~ ^[a-zA-Z0-9-]+$ ]]; then break; else echo "Nom invalide."; fi
        done
        
        read -p "Stockage (local/local-lvm) [défaut: local-lvm] : " stockage
        stockage=${stockage:-local-lvm}
        if [[ "$stockage" != "local" && "$stockage" != "local-lvm" ]]; then stockage="local-lvm"; fi
        
        LIMIT_RAM=$(get_max_ram)
        LIMIT_DISK=$(get_max_disk "$stockage")
        echo "   -> Max Disp: RAM=${LIMIT_RAM}Mo | Disque=${LIMIT_DISK}Go"

        while true; do
            read -p "RAM (Mo) [Min: 512 - Max: $LIMIT_RAM] : " ram
            if [[ ! "$ram" =~ ^[0-9]+$ ]]; then continue; fi
            if (( ram < 512 || ram > LIMIT_RAM )); then echo "Erreur RAM."; else break; fi
        done

        while true; do
            read -p "Disque (Go) [Min: 2 - Max: $LIMIT_DISK] : " disque
            if [[ ! "$disque" =~ ^[0-9]+$ ]]; then continue; fi
            if (( disque < 2 || disque > LIMIT_DISK )); then echo "Erreur Disque."; else break; fi
        done

        demander_ip
        ip=$VAL_IP_FINALE

        read -p "ISO (vide pour chercher) : " iso_input
        if [ -z "$iso_input" ]; then lister_iso; else iso="$iso_input"; fi

        # Vérification corrigée avec le bon chemin
        if [ -z "$iso" ] || [ ! -f "$PATH_ISO/$iso" ]; then
            echo "ERREUR FATALE : Pas d'ISO valide. Retour menu."
            read -p "Entrée..."
            menu_creation
            return
        fi

        while true; do
            read -sp "Mot de passe Cloud-init (Min 5 char) : " password
            echo ""
            if [ ${#password} -ge 5 ]; then break; else echo "Erreur : Min 5 caractères."; fi
        done

        read -p "DNS : " dns
        vmid=$(generate_vmid)
        echo "-> Création VM $vmid ($nom)..."
        
        # Utilisation de local:iso/ qui pointe maintenant vers le bon fichier physique
        qm create $vmid --name "$nom" \
            --memory "$ram" \
            --net0 model=virtio,bridge=vmbr0 \
            --scsihw virtio-scsi-pci \
            --scsi0 "$stockage:$disque" \
            --cdrom "local:iso/$iso" \
            --boot "order=scsi0;ide2;net0" \
            --ipconfig0 ip=$ip/24,gw=$REAL_GATEWAY

        if [ $? -eq 0 ]; then
            qm set $vmid --ide2 "$stockage:cloudinit"
            qm set $vmid --ciuser root --cipassword "$password"
            qm set $vmid --nameserver "$dns"
            echo "SUCCESS : VM $nom créée !"
        else
            echo "ERREUR CRITIQUE."
        fi
    done
    read -p "Appuyez sur Entrée..."
    menu_creation
}

# --- MENU PRINCIPAL ---
menu_creation() {
    clear
    echo "=============================================="
    echo "   PROXMOX AUTO-INSTALLER - ULTIMATE EDITION  "
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

# Lancement
menu_creation