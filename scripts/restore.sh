#!/bin/bash
# Sources et références :
# - Documentation Bash : https://www.gnu.org/software/bash/manual/bash.html
# - Documentation Docker Compose : https://docs.docker.com/reference/cli/docker/compose/
# - Documentation MariaDB : https://mariadb.com/kb/en/mariadb-client/
# - Documentation GNU Coreutils (sha256sum) :
#   https://www.gnu.org/software/coreutils/manual/coreutils.html
# - Documentation curl : https://curl.se/docs/manpage.html
# - Documentation GNU tar : https://www.gnu.org/software/tar/manual/
# - Assistance IA : ChatGPT, pour la rédaction des commentaires.
#   Conserver les références correspondant aux ressources réellement utilisées.

# Arrête le script si une commande échoue dans les situations couvertes par set -e.
set -e

# Récupère le chemin du dossier de sauvegarde passé en premier argument.
# Exemple : ./scripts/restore.sh "$HOME/SAE51-backups/2026-10-16_04-48-43"
BACKUP_DIR="$1"

# Définit l'adresse locale utilisée pour vérifier que Dolibarr répond.
DOLIBARR_URL="http://localhost:8081"

# Vérifie qu'un chemin de sauvegarde a été fourni.
# -z teste si une chaîne est vide.
if [ -z "$BACKUP_DIR" ]; then

    # Affiche la syntaxe attendue si aucun argument n'a été fourni.
    # $0 représente le nom utilisé pour lancer le script.
    echo "Usage : $0 <dossier_de_sauvegarde>"

    # Quitte le script avec le code 1, qui indique une erreur.
    exit 1
fi

# Vérifie que le chemin fourni correspond à un dossier existant.
# -d teste l'existence d'un répertoire.
if [ ! -d "$BACKUP_DIR" ]; then

    # Affiche une erreur si le dossier n'existe pas.
    echo "ERREUR : dossier introuvable : $BACKUP_DIR"

    # Arrête le script avec un code d'erreur.
    exit 1
fi

# Vérifie la présence des trois fichiers indispensables à la restauration.
# -f vérifie qu'un chemin correspond à un fichier ordinaire.
# || représente l'opérateur logique OU.
# Les antislashs permettent de continuer la commande sur plusieurs lignes.
if [ ! -f "$BACKUP_DIR/dolibarr.sql" ] || \
   [ ! -f "$BACKUP_DIR/dolibarr_documents.tar.gz" ] || \
   [ ! -f "$BACKUP_DIR/sha256sums.txt" ]; then

    # Signale que la sauvegarde est incomplète.
    echo "ERREUR : sauvegarde incomplète."

    # Arrête la restauration pour éviter d'utiliser une sauvegarde incomplète.
    exit 1
fi

# Calcule le chemin absolu de la racine du projet.
# dirname "$0" récupère le dossier contenant le script.
# /.. remonte d'un niveau, cd se place dans ce dossier et pwd affiche son chemin.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Informe l'utilisateur que les fichiers vont être contrôlés.
echo "Vérification de l'intégrité de la sauvegarde..."

# Exécute les commandes suivantes dans un sous-shell.
# Les parenthèses isolent le changement de répertoire du shell principal.
(
    # Se place dans le dossier qui contient les fichiers de sauvegarde.
    cd "$BACKUP_DIR"

    # Compare les empreintes SHA-256 calculées aux valeurs enregistrées.
    # Le fichier sha256sums.txt doit contenir les empreintes des deux archives.
    sha256sum -c sha256sums.txt
)

# Ajoute une ligne vide pour faciliter la lecture du terminal.
echo

# Avertit l'utilisateur que la restauration est destructive.
# La commande exécutée plus bas supprimera les conteneurs et volumes du projet.
echo "ATTENTION : cette opération va supprimer les conteneurs et volumes actuels."

# Demande une confirmation à l'utilisateur.
# -r empêche read d'interpréter les antislashs comme des caractères d'échappement.
# La réponse est stockée dans la variable CONFIRMATION.
read -r -p "Confirmer la restauration ? (oui/non) : " CONFIRMATION

# Vérifie que l'utilisateur a saisi exactement "oui".
if [ "$CONFIRMATION" != "oui" ]; then

    # Indique que l'opération a été annulée.
    echo "Restauration annulée."

    # Termine normalement le script avec le code 0.
    exit 0
fi

# Se place à la racine du projet pour utiliser le fichier Docker Compose.
cd "$PROJECT_DIR"

# Annonce la première étape de la restauration.
echo
echo "[1/5] Suppression de l'environnement actuel..."

# Arrête et supprime les conteneurs du projet.
# -v supprime également les volumes déclarés et les volumes anonymes
# associés aux conteneurs concernés.
# ATTENTION : cela peut supprimer les données actuelles de MariaDB et les
# documents persistants. La restauration dépend donc des fichiers de sauvegarde.
docker compose down -v

# Annonce la deuxième étape : démarrer uniquement le service de base de données.
echo
echo "[2/5] Démarrage de MariaDB uniquement..."

# Démarre le service nommé db en arrière-plan.
# -d signifie que les conteneurs tournent en mode détaché.
docker compose up -d db

# Informe l'utilisateur que le script attend la disponibilité de MariaDB.
echo
echo "Attente de MariaDB..."

# Réessaie la requête SQL jusqu'à ce qu'elle réussisse.
# docker exec lance une commande dans le conteneur dolibarr-db.
# MYSQL_PWD transmet le mot de passe à la commande MariaDB par variable
# d'environnement.
# -u sélectionne l'utilisateur MariaDB.
# -e exécute la requête SQL SELECT 1.
# La redirection masque la sortie et les erreurs pendant les tentatives.
# ATTENTION : cette boucle n'a pas de délai maximal et peut attendre indéfiniment.
until docker exec -e MYSQL_PWD='dolibarrpass' dolibarr-db \
    mariadb -u dolibarr dolibarr -e "SELECT 1;" >/dev/null 2>&1
do
    # Attend deux secondes avant de réessayer.
    sleep 2
done

# Confirme que MariaDB répond et que le compte utilisé fonctionne.
echo "MariaDB est opérationnel et le compte dolibarr est accessible."

# Annonce la troisième étape : restaurer la base de données.
echo
echo "[3/5] Restauration de la base..."

# Envoie le contenu du fichier SQL au client MariaDB dans le conteneur.
# -i maintient l'entrée standard ouverte pour transmettre le fichier.
# MYSQL_PWD fournit le mot de passe à la commande MariaDB.
# -u sélectionne l'utilisateur et dolibarr désigne la base de données.
# < lit le contenu du fichier dolibarr.sql et l'envoie à MariaDB.
docker exec -i -e MYSQL_PWD='dolibarrpass' \
    dolibarr-db \
    mariadb -u dolibarr dolibarr < "$BACKUP_DIR/dolibarr.sql"

# Confirme que la commande de restauration SQL s'est terminée sans erreur détectée.
echo "Base restaurée."

# Annonce la quatrième étape : démarrer l'application Dolibarr.
echo
echo "[4/5] Démarrage de Dolibarr..."

# Démarre le service dolibarr en arrière-plan.
docker compose up -d dolibarr

# Informe l'utilisateur que le script attend la réponse HTTP de Dolibarr.
echo
echo "Attente de Dolibarr..."

# Définit le nombre maximal de tentatives de vérification HTTP.
MAX_ATTEMPTS=60

# Initialise le compteur de tentatives à 1.
ATTEMPT=1

# Réessaie tant que l'adresse de Dolibarr ne répond pas correctement.
# curl -f considère les réponses HTTP d'erreur comme des échecs.
# -s désactive l'affichage habituel de curl.
# -S permet toutefois d'afficher les erreurs de curl.
# --max-time 3 limite chaque requête à trois secondes.
# >/dev/null 2>&1 masque la sortie et les erreurs pendant les tentatives.
until curl -fsS --max-time 3 "$DOLIBARR_URL" >/dev/null 2>&1
do

    # Vérifie si le nombre maximal de tentatives a été atteint.
    if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then

        # Affiche une erreur si Dolibarr n'est toujours pas accessible.
        echo "ERREUR : Dolibarr ne répond pas après 120 secondes."

        # Affiche l'état des services Docker pour faciliter le diagnostic.
        docker compose ps

        # Arrête le script avec un code d'erreur.
        exit 1
    fi

    # Attend deux secondes avant de lancer une nouvelle tentative.
    sleep 2

    # Incrémente le compteur d'une unité.
    ATTEMPT=$((ATTEMPT + 1))
done

# Confirme que Dolibarr répond aux requêtes HTTP.
echo "Dolibarr est accessible."

# Annonce la cinquième étape : restaurer les documents.
echo
echo "[5/5] Restauration des documents..."

# Supprime le contenu actuel du répertoire de documents dans le conteneur.
# sh -c exécute la commande find dans un shell.
# -mindepth 1 évite de supprimer le répertoire lui-même.
# -delete supprime les fichiers et sous-répertoires trouvés.
# Cette suppression permet de remplacer l'ancien contenu par la sauvegarde.
docker exec dolibarr-app \
    sh -c 'find /var/www/documents -mindepth 1 -delete'

# Transmet l'archive compressée au conteneur Dolibarr pour la décompresser.
# -i transmet l'entrée standard au conteneur.
# tar xzf - extrait une archive gzip reçue sur l'entrée standard.
# -C définit le répertoire dans lequel extraire les fichiers.
# La redirection < transmet le fichier d'archive de la sauvegarde.
docker exec -i dolibarr-app \
    tar xzf - -C /var/www/documents \
    < "$BACKUP_DIR/dolibarr_documents.tar.gz"

# Affiche une ligne vide avant le bilan final.
echo

# Affiche le message de fin de restauration.
echo "======================================"
echo " Restauration terminée"
echo "======================================"

# Affiche l'état des services et des conteneurs Docker du projet.
docker compose ps