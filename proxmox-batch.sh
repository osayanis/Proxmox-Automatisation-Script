#!/bin/bash

# ============================================================
# SCRIPT D'AUTOMATISATION PROXMOX (Ultra-Sécurisé & Dynamique)
# ============================================================

# --- Fonction : Récupérer les infos Réseau réelles ---
detecter_reseau() {
    # On détecte l'interface principale (souvent vmbr0)
    INTERFACE="vmbr0"
    
    # Récupération de la Gateway réelle
    REAL_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)
    
    # Récupération du Broadcast réel
    REAL_BROADCAST=$(ip -4 addr show $INTERFACE | grep -oP '(?<=brd )[\d.]+')
}

# --- Fonction : Calculer la RAM Max disponible ---
get_max_ram() {
    # On récupère la RAM disponible (free + cache) en Mo
    # On laisse une marge de sécurité de 512Mo pour l'hyperviseur lui-même
    TOTAL_FREE=$(free -m | awk '/^Mem:/{print $7}')
    MAX_RAM_CALC=$((TOTAL_FREE - 512))
    
    if [ $MAX_RAM_CALC -lt 512 ]; then
        MAX_RAM_CALC=512 # Minimum syndical si le serveur est saturé
    fi
    echo $MAX_RAM_CALC
}

# --- Fonction : Calculer l'Espace Disque Max disponible ---
get_max_disk() {
    local storage=$1
    # pvesm status donne la taille en octets ou blocs, on simplifie
    # On récupère l'espace 'Avail' de la commande pvesm status
    # Sortie typique: Name Type Status Total Used Available %
    
    # On force l'unité en Go pour simplifier le parsing
    # Attention : pvesm ne permet pas toujours de formater facilement, on utilise une approximation via df pour 'local' et lvs pour 'local-lvm'
    
    if [ "$storage" == "local" ]; then
        # Espace libre sur /var/lib/vz en Go
        df -BG /var/lib/vz | awk 'NR==2 {print $4}' | sed 's/G//'
    else
        # Espace libre dans le Volume Group pve (pour local-lvm)
        vgs pve --noheadings -o vg_free --units g | awk '{print int($1)}'
    fi
}

# --- Fonction : Validation et demande d'IP ---
demander_ip() {
    detecter_reseau # Mise à jour des infos réseau
    local ip_valide=false
    local input_ip=""
    
    echo "   -> Infos détectées : Passerelle=$REAL_GATEWAY | Broadcast=$REAL_BROADCAST"

    while [ "$ip_valide" = false ]; do
        read -p "Adresse IP (ex: 192.168.20.50) : " input_ip
        
        if [[ $input_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            IFS='.' read -r -a octets <<< "$input_ip"
            o1=$((10#${octets[0]}))
            o2=$((10#${octets[1]}))
            o3=$((10#${octets[2]}))
            o4=$((10#${octets[3]}))

            if (( o1 > 255 || o2 > 255 || o3 > 255 || o4 > 255 )); then
                echo "Erreur : Les octets ne peuvent pas dépasser 255."
            elif [ "$input_ip" == "$REAL_GATEWAY" ]; then
                echo "Erreur : Cette IP est votre Passerelle (Gateway)."
            elif [ "$input_ip" == "$REAL_BROADCAST" ]; then
                echo "Erreur : Cette IP est votre adresse de Broadcast."
            elif (( o4 == 0 )); then
                echo "Erreur : L'adresse réseau (.0) est interdite."
            else
                ip_valide=true
            fi
        else
            echo "Erreur : Format invalide (X.X.X.X)."
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
        found_templates=$(ls /var/lib/vz/template/cache/)
    else
        found_templates=$(ls /var/lib/vz/template/cache/ | grep -i "$keyword")
    fi

    if [ -z "$found_templates" ]; then
        echo "Aucun template trouvé."
        read -p "Télécharger via URL ? (y/n) : " reponse
        if [ "$reponse" == "y" ]; then
            read -p "URL : " url
            wget -P /var/lib/vz/template/cache/ "$url"
            template=$(basename "$url")
        fi
    else
        PS3="Choix : "
        select template_choice in $found_templates "Télécharger via URL" "Annuler"; do
            case $template_choice in
                "Télécharger via URL")
                    read -p "URL : " url
                    wget -P /var/lib/vz/template/cache/ "$url"
                    template=$(basename "$url")
                    break ;;
                "Annuler") template=""; break ;;
                *) [ -n "$template_choice" ] && template="$template_choice" && break ;;
            esac
        done
    fi
}

# --- Fonction : Lister ISOs ---
lister_iso() {
    echo "--- Liste des ISOs ---"
    found_isos=$(ls /var/lib/vz/iso/)
    iso=""

    if [ -z "$found_isos" ]; then
        echo "Aucun ISO trouvé."
        read -p "Télécharger via URL ? (y/n) : " reponse
        if [ "$reponse" == "y" ]; then
            read -p "URL : " url
            wget -P /var/lib/vz/iso/ "$url"
            iso=$(basename "$url")
        fi
    else
        PS3="Choix : "
        select iso_choice in $found_isos "Télécharger via URL" "Annuler"; do
            case $iso_choice in
                "Télécharger via URL")
                    read -p "URL : " url
                    wget -P /var/lib/vz/iso/ "$url"
                    iso=$(basename "$url")
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

        # --- 1. Validation Hostname ---
        while true; do
            read -p "Nom du conteneur (pas d'espaces/spéciaux) : " nom
            if [[ "$nom" =~ ^[a-zA-Z0-9-]+$ ]]; then
                break
            else
                echo "Erreur : Caractères invalides. Utilisez uniquement lettres, chiffres et tirets."
            fi
        done
        
        # --- 2. Choix du Stockage (D'abord, pour calculer l'espace dispo) ---
        read -p "Stockage (local/local-lvm) [défaut: local-lvm] : " stockage
        stockage=${stockage:-local-lvm}
        if [[ "$stockage" != "local" && "$stockage" != "local-lvm" ]]; then stockage="local-lvm"; fi
        
        # Calcul des limites dynamiques
        LIMIT_RAM=$(get_max_ram)
        LIMIT_DISK=$(get_max_disk "$stockage")

        echo "   -> Ressources disp. : RAM Max=${LIMIT_RAM}Mo | Disque Max=${LIMIT_DISK}Go (sur $stockage)"

        # --- 3. Validation RAM ---
        while true; do
            read -p "RAM (Mo) [Min: 512 - Max: $LIMIT_RAM] : " ram
            if [[ ! "$ram" =~ ^[0-9]+$ ]]; then continue; fi
            if (( ram < 512 )); then echo "Erreur : Min 512 Mo.";
            elif (( ram > LIMIT_RAM )); then echo "Erreur : Dépasse la RAM disponible ($LIMIT_RAM Mo).";
            else break; fi
        done

        # --- 4. Validation Disque ---
        while true; do
            read -p "Disque (Go) [Min: 2 - Max: $LIMIT_DISK] : " disque
            if [[ ! "$disque" =~ ^[0-9]+$ ]]; then continue; fi
            if (( disque < 2 )); then echo "Erreur : Min 2 Go.";
            elif (( disque > LIMIT_DISK )); then echo "Erreur : Dépasse l'espace disponible ($LIMIT_DISK Go).";
            else break; fi
        done

        # --- 5. Validation IP ---
        demander_ip
        ip=$VAL_IP_FINALE 
        
        # --- 6. Template ---
        read -p "Nom du template (laisser vide pour rechercher) : " template_input
        if [ -z "$template_input" ]; then lister_templates; else template="$template_input"; fi

        if [ -z "$template" ] || [ ! -f "/var/lib/vz/template/cache/$template" ]; then
            echo "ERREUR FATALE : Pas de template valide. Retour au menu."
            read -p "Appuyez sur Entrée..."
            menu_creation
            return
        fi

        # --- 7. Mot de passe sécurisé ---
        while true; do
            read -sp "Mot de passe root (Min 5 char) : " password
            echo ""
            if [ ${#password} -ge 5 ]; then
                break
            else
                echo "Erreur : Le mot de passe doit avoir minimum 5 caractères."
            fi
        done

        read -p "Serveur DNS (ex: 8.8.8.8) : " dns
        vmid=$(generate_vmid)
        echo "-> Création du CT $vmid ($nom)..."

        pct create $vmid "/var/lib/vz/template/cache/$template" \
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

        # --- 1. Validation Hostname ---
        while true; do
            read -p "Nom de la VM (pas d'espaces/spéciaux) : " nom
            if [[ "$nom" =~ ^[a-zA-Z0-9-]+$ ]]; then break; else echo "Caractères invalides."; fi
        done
        
        # --- 2. Choix Stockage ---
        read -p "Stockage (local/local-lvm) [défaut: local-lvm] : " stockage
        stockage=${stockage:-local-lvm}
        if [[ "$stockage" != "local" && "$stockage" != "local-lvm" ]]; then stockage="local-lvm"; fi
        
        LIMIT_RAM=$(get_max_ram)
        LIMIT_DISK=$(get_max_disk "$stockage")
        echo "   -> Ressources disp. : RAM Max=${LIMIT_RAM}Mo | Disque Max=${LIMIT_DISK}Go"

        # --- 3. RAM & Disque ---
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

        # --- 4. IP ---
        demander_ip
        ip=$VAL_IP_FINALE

        # --- 5. ISO ---
        read -p "Nom de l'ISO (laisser vide pour rechercher) : " iso_input
        if [ -z "$iso_input" ]; then lister_iso; else iso="$iso_input"; fi

        if [ -z "$iso" ] || [ ! -f "/var/lib/vz/iso/$iso" ]; then
            echo "ERREUR FATALE : Pas d'ISO valide. Retour au menu."
            read -p "Appuyez sur Entrée..."
            menu_creation
            return
        fi

        # --- 6. Password ---
        while true; do
            read -sp "Mot de passe Cloud-init (Min 5 char) : " password
            echo ""
            if [ ${#password} -ge 5 ]; then break; else echo "Erreur : Minimum 5 caractères."; fi
        done

        read -p "Serveur DNS : " dns
        vmid=$(generate_vmid)
        echo "-> Création de la VM $vmid ($nom)..."
        
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