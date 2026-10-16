#!/bin/bash
# Sources :
# - Documentation Bash : https://www.gnu.org/software/bash/manual/bash.html
# - Documentation Docker : https://docs.docker.com/reference/cli/docker/
# - Documentation MariaDB : https://mariadb.com/kb/en/mariadb-dump/
# - Documentation GNU Coreutils (sha256sum) :
#   https://www.gnu.org/software/coreutils/manual/coreutils.html
# - Documentation GNU tar : https://www.gnu.org/software/tar/manual/
# - Assistance IA : ChatGPT, pour la rédaction des commentaires
#   et l'explication du fonctionnement du script.

# Arrête le script si une commande échoue dans les situations couvertes par set -e.
set -e

# Récupère le chemin absolu de la racine du projet.
# dirname "$0" désigne le dossier du script ; /.. remonte à la racine.
# cd change de dossier et pwd récupère son chemin absolu.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Définit le dossier principal où seront stockées les sauvegardes.
BACKUP_ROOT="$HOME/SAE51-backups"

# Génère une date et une heure pour identifier la sauvegarde.
# Le format évite les caractères problématiques dans les noms de dossiers.
DATE="$(date '+%Y-%m-%d_%H-%M-%S')"

# Construit le chemin du dossier de sauvegarde correspondant à cette date.
BACKUP_DIR="$BACKUP_ROOT/$DATE"

# Définit le nom du conteneur qui héberge MariaDB.
DB_CONTAINER="dolibarr-db"

# Définit le nom de la base de données à sauvegarder.
DB_NAME="dolibarr"

# Définit l'utilisateur MariaDB utilisé pour la sauvegarde.
DB_USER="dolibarr"

# Définit le mot de passe de cet utilisateur.
DB_PASSWORD="dolibarrpass"

# Affiche le titre du script dans le terminal.
echo "======================================"
echo " SAE Dolibarr - Sauvegarde"
echo "======================================"

# Crée le dossier de sauvegarde.
# -p crée également les dossiers parents manquants et ne signale pas
# d'erreur si le dossier existe déjà.
mkdir -p "$BACKUP_DIR"

# Annonce la première étape : la sauvegarde de la base de données.
echo
echo "[1/3] Sauvegarde de la base MariaDB..."

# Exécute mariadb-dump dans le conteneur MariaDB.
# MYSQL_PWD transmet le mot de passe via une variable d'environnement.
# -u sélectionne l'utilisateur MariaDB.
# --single-transaction réalise une sauvegarde cohérente des tables
# transactionnelles, notamment celles utilisant InnoDB.
# --routines inclut les procédures et fonctions stockées.
# --triggers inclut les déclencheurs.
# Le résultat SQL est redirigé vers un fichier dans le dossier de sauvegarde.
docker exec -e MYSQL_PWD="$DB_PASSWORD" \
    "$DB_CONTAINER" \
    mariadb-dump \
    -u "$DB_USER" \
    --single-transaction \
    --routines \
    --triggers \
    "$DB_NAME" \
    > "$BACKUP_DIR/dolibarr.sql"

# Confirme que la commande précédente s'est terminée sans erreur détectée.
echo "Base sauvegardée."

# Annonce la deuxième étape : la sauvegarde des documents Dolibarr.
echo
echo "[2/3] Sauvegarde des documents Dolibarr..."

# Exécute tar dans le conteneur de l'application Dolibarr.
# -c crée une archive.
# -z compresse l'archive avec gzip.
# -f - envoie l'archive vers la sortie standard.
# -C change le dossier de départ vers /var/www/documents.
# . inclut le contenu de ce dossier.
# La redirection > enregistre l'archive compressée sur l'hôte.
docker exec dolibarr-app \
    tar czf - \
    -C /var/www/documents . \
    > "$BACKUP_DIR/dolibarr_documents.tar.gz"

# Confirme que la commande précédente s'est terminée sans erreur détectée.
echo "Documents sauvegardés."

# Annonce la troisième étape : le calcul des sommes de contrôle.
echo
echo "[3/3] Calcul des sommes de contrôle..."

# Se place dans le dossier qui contient les fichiers de sauvegarde.
cd "$BACKUP_DIR"

# Calcule l'empreinte SHA-256 de chaque archive et enregistre les résultats.
# Ces empreintes permettront de détecter une modification ou une corruption
# des fichiers avant leur restauration.
sha256sum dolibarr.sql dolibarr_documents.tar.gz > sha256sums.txt

# Affiche le titre de fin de sauvegarde.
echo
echo "======================================"
echo " Sauvegarde terminée"
echo "======================================"
echo

# Affiche le chemin du dossier de sauvegarde créé.
echo "Dossier : $BACKUP_DIR"
echo

# Affiche la liste des fichiers sauvegardés, leur taille et leurs permissions.
ls -lh "$BACKUP_DIR"
