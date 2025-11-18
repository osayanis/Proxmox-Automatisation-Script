# Script d'Automatisation Proxmox

Ce script Bash a été conçu pour simplifier et automatiser la création de conteneurs (CT) et de machines virtuelles (VM) sur Proxmox VE. Il fournit un menu interactif pour guider l'utilisateur à travers les différentes étapes de création et de configuration.

## ✨ Fonctionnalités

-   **Menu Interactif :** Une interface en ligne de commande simple pour une utilisation facile.
-   **Création en Masse :** Créez plusieurs conteneurs ou machines virtuelles en une seule fois.
-   **Gestion des Templates et ISOs :**
    -   Listez les templates de conteneurs et les images ISO disponibles.
    -   Recherchez des templates par mot-clé.
    -   Téléchargez de nouveaux templates ou ISOs directement via une URL.
-   **Configuration Automatisée :**
    -   Génération automatique d'un ID unique pour chaque CT/VM.
    -   Configuration du réseau (IP, passerelle).
    -   Définition du mot de passe root/administrateur.
    -   Configuration du serveur DNS.
-   **Sélection du Stockage :** Choisissez entre `local` et `local-lvm` pour le disque root.

## 📋 Prérequis

-   Un serveur Proxmox VE fonctionnel.
-   Le script doit être exécuté avec des privilèges root (ou via `sudo`).
-   L'outil `wget` doit être installé pour le téléchargement des templates et ISOs.

## 🚀 Utilisation

1.  **Rendre le script exécutable :**
    Ouvrez un terminal sur votre nœud Proxmox et exécutez la commande suivante :
    ```bash
    chmod +x proxmox-batch.sh
    ```

2.  **Lancer le script :**
    Exécutez le script avec des droits administrateur :
    ```bash
    ./proxmox-batch.sh
    ```
    ou
    ```bash
    sudo ./proxmox-batch.sh
    ```

3.  **Naviguer dans le menu :**
    Une fois le script lancé, un menu s'affiche :

    ```
    ==============================================
    Création de Conteneurs et Machines Virtuelles - Menu Principal
    ==============================================
    1. Créer un ou plusieurs conteneurs
    2. Créer un ou plusieurs machines virtuelles (VM)
    3. Liste des templates disponibles
    4. Liste des ISO disponibles
    5. Quitter
    ==============================================
    ```
    Sélectionnez une option en entrant le numéro correspondant et suivez les instructions.

## ✍️ Auteur

-   **Yanis B.** - *Développeur du script* - [osayanis](https://github.com/osayanis)

## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier `LICENSE.md` pour plus de détails.

