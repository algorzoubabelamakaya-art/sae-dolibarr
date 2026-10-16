#!/bin/bash
# Sources :
# - Bash : https://www.gnu.org/software/bash/manual/bash.html
# - Docker Compose : https://docs.docker.com/compose/
# - curl : https://curl.se/docs/manpage.html
# - Assistance IA : ChatGPT, pour les commentaires.
# Sources à conserver si elles correspondent à celles réellement utilisées.

# Arrête le script en cas d'échec d'une commande.
set -e

# Définit le chemin absolu de la racine du projet.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Définit l'adresse locale de Dolibarr.
DOLIBARR_URL="http://localhost:8081"

# Affiche le titre.
echo "======================================"
echo " SAE Dolibarr - Installation"
echo "======================================"

# Se place à la racine du projet.
cd "$PROJECT_DIR"

# Vérifie que Docker est disponible.
if ! command -v docker >/dev/null 2>&1; then
    echo "ERREUR : Docker n'est pas installé."
    exit 1
fi

# Vérifie que Docker Compose fonctionne.
if ! docker compose version >/dev/null 2>&1; then
    echo "ERREUR : Docker Compose n'est pas disponible."
    exit 1
fi

# Vérifie que curl est disponible.
if ! command -v curl >/dev/null 2>&1; then
    echo "ERREUR : curl n'est pas installé."
    exit 1
fi

# Vérifie que le fichier Compose existe.
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
    echo "ERREUR : docker-compose.yml introuvable."
    exit 1
fi

# Démarre les conteneurs en arrière-plan.
echo
echo "[1/4] Démarrage de MariaDB et Dolibarr..."
docker compose up -d

# Attend que MariaDB réponde.
echo
echo "[2/4] Attente du démarrage de MariaDB..."

until docker exec dolibarr-db mariadb-admin ping \
    -h localhost \
    -u dolibarr \
    -p'dolibarrpass' \
    --silent >/dev/null 2>&1
do
    # Attend deux secondes avant de réessayer.
    sleep 2
done

echo "MariaDB est opérationnel."

# Prépare la vérification HTTP de Dolibarr.
echo
echo "[3/4] Attente de la disponibilité de Dolibarr..."

MAX_ATTEMPTS=60
ATTEMPT=1

# Réessaie jusqu'à ce que Dolibarr réponde ou que la limite soit atteinte.
until curl -fsS --max-time 3 "$DOLIBARR_URL" >/dev/null 2>&1
do
    # Vérifie si le nombre maximal de tentatives est atteint.
    if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
        echo "ERREUR : Dolibarr ne répond pas après 120 secondes."
        docker compose ps
        exit 1
    fi

    # Attend deux secondes et incrémente le compteur.
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

echo "Dolibarr est accessible."

# Affiche l'état des conteneurs.
echo
echo "[4/4] Vérification des conteneurs..."
docker compose ps

# Affiche le bilan de l'installation.
echo
echo "======================================"
echo " Installation terminée"
echo "======================================"
echo "Dolibarr : $DOLIBARR_URL"
echo
echo "Pour importer les données :"
echo "    ./scripts/import_csv.sh"