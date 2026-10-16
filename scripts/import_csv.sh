```bash
#!/bin/bash
# Sources :
# - Documentation Bash : https://www.gnu.org/software/bash/manual/bash.html
# - Documentation Python CSV : https://docs.python.org/3/library/csv.html
# - Documentation Docker Compose : https://docs.docker.com/compose/
# - Documentation MariaDB : https://mariadb.com/kb/en/mariadb-client/
# - Assistance IA : ChatGPT, pour la rédaction des commentaires
#   et l'explication du fonctionnement du script.

# Arrête le script si une commande échoue dans les situations couvertes par set -e.
set -e

# Définit le chemin du fichier CSV contenant les tiers à importer.
CSV_FILE="data/tiers.csv"

# Définit le nom du conteneur Docker qui héberge MariaDB.
DB_CONTAINER="dolibarr-db"

# Définit le nom de la base de données Dolibarr.
DB_NAME="dolibarr"

# Définit l'utilisateur MariaDB utilisé pour l'import.
DB_USER="dolibarr"

# Définit le mot de passe de cet utilisateur.
DB_PASSWORD="dolibarrpass"

# Vérifie que le fichier CSV existe.
if [ ! -f "$CSV_FILE" ]; then
    # Affiche un message si le fichier est absent.
    echo "Erreur : fichier CSV introuvable : $CSV_FILE"

    # Arrête le script avec un code indiquant une erreur.
    exit 1
fi

# Crée un fichier temporaire destiné à recevoir les requêtes SQL.
TMP_SQL=$(mktemp)

# Supprime le fichier temporaire lorsque le script se termine.
trap 'rm -f "$TMP_SQL"' EXIT

# Lance Python en lui transmettant le fichier CSV et le fichier SQL.
# Le délimiteur <<'PY' permet d'intégrer le code Python dans ce script Bash.
python3 - "$CSV_FILE" "$TMP_SQL" <<'PY'

# Importe le module permettant de lire les fichiers CSV.
import csv

# Importe le module permettant de récupérer les arguments du programme.
import sys

# Définit une fonction qui prépare une valeur pour une chaîne SQL.
def esc(value):
    # Supprime les espaces aux extrémités et double les apostrophes.
    return value.strip().replace("'", "''")

# Définit une fonction qui convertit une valeur en texte SQL.
def sql_text(value):
    # Supprime les espaces aux extrémités de la valeur.
    value = value.strip()

    # Retourne NULL si la valeur est vide, sinon une chaîne SQL entre apostrophes.
    return "NULL" if not value else f"'{esc(value)}'"

# Récupère le chemin du CSV transmis en premier argument à Python.
csv_file = sys.argv[1]

# Récupère le chemin du fichier SQL transmis en deuxième argument à Python.
sql_file = sys.argv[2]

# Ouvre le CSV en lecture.
# newline="" est recommandé pour laisser le module csv gérer les retours à la ligne.
# utf-8-sig permet aussi de gérer un éventuel BOM au début du fichier.
with open(csv_file, newline="", encoding="utf-8-sig") as f:

    # Lit le CSV en associant chaque valeur au nom de sa colonne.
    reader = csv.DictReader(f)

    # Liste les colonnes obligatoires pour effectuer l'import.
    required = [
        "Nom du tiers* (s.nom)",
        "État* (s.status)",
        "Code pays (s.fk_pays)",
        "Client* (s.client)",
        "Fournisseur* (s.fournisseur)",
    ]

    # Vérifie que chaque colonne obligatoire est présente dans le CSV.
    for column in required:

        # Interrompt le programme si une colonne obligatoire est absente.
        if column not in reader.fieldnames:
            raise SystemExit(f"Colonne absente du CSV : {column}")

    # Ouvre le fichier temporaire SQL en écriture.
    with open(sql_file, "w", encoding="utf-8") as out:

        # Parcourt les lignes du CSV une par une.
        for row in reader:

            # Récupère le nom du tiers et supprime les espaces inutiles.
            nom = row["Nom du tiers* (s.nom)"].strip()

            # Convertit l'état en entier.
            status = int(row["État* (s.status)"])

            # Prépare le code pays pour son utilisation dans les requêtes SQL.
            code_pays = esc(row["Code pays (s.fk_pays)"])

            # Convertit l'indicateur client en entier.
            client = int(row["Client* (s.client)"])

            # Convertit l'indicateur fournisseur en entier.
            fournisseur = int(row["Fournisseur* (s.fournisseur)"])

            # Récupère l'adresse si la colonne existe, sinon utilise une valeur vide.
            # sql_text convertit ensuite cette valeur en texte SQL ou en NULL.
            address = sql_text(row.get("Adresse (s.address)", ""))

            # Récupère et prépare le code postal.
            zip_code = sql_text(row.get("Code postal (s.zip)", ""))

            # Récupère et prépare la ville.
            town = sql_text(row.get("Ville (s.town)", ""))

            # Récupère et prépare le numéro de téléphone.
            phone = sql_text(row.get("Téléphone (s.phone)", ""))

            # Récupère et prépare l'adresse e-mail.
            email = sql_text(row.get("Email (s.email)", ""))

            # Récupère et prépare la clé d'import si elle existe.
            import_key = sql_text(row.get("Clé import (s.import_key)", ""))

            # Prépare le nom du tiers pour son utilisation dans SQL.
            nom_sql = sql_text(nom)

            # Génère une requête UPDATE pour modifier un tiers déjà présent.
            out.write(f"""
UPDATE llx_societe s
# Associe le tiers à la table des pays grâce au code pays.
JOIN llx_c_country c ON c.code = '{code_pays}'
SET
    # Met à jour l'état du tiers.
    s.status = {status},
    # Enregistre l'identifiant interne du pays.
    s.fk_pays = c.rowid,
    # Définit si le tiers est un client.
    s.client = {client},
    # Définit si le tiers est un fournisseur.
    s.fournisseur = {fournisseur},
    # Met à jour les coordonnées du tiers.
    s.address = {address},
    s.zip = {zip_code},
    s.town = {town},
    s.phone = {phone},
    s.email = {email},
    # Met à jour la clé d'import.
    s.import_key = {import_key}
# Cible le tiers en utilisant son nom.
WHERE s.nom = {nom_sql};

""")

            # Génère une requête INSERT pour ajouter un tiers absent.
            out.write(f"""
INSERT INTO llx_societe
(
    # Liste des colonnes qui recevront les données.
    entity,
    nom,
    status,
    fk_pays,
    client,
    fournisseur,
    address,
    zip,
    town,
    phone,
    email,
    import_key,
    datec
)
SELECT
    # Définit l'entité Dolibarr à laquelle le tiers appartient.
    1,
    # Insère les informations récupérées dans le CSV.
    {nom_sql},
    {status},
    c.rowid,
    {client},
    {fournisseur},
    {address},
    {zip_code},
    {town},
    {phone},
    {email},
    {import_key},
    # Enregistre la date et l'heure actuelles.
    NOW()
# Recherche le pays correspondant au code fourni.
FROM llx_c_country c
WHERE c.code = '{code_pays}'
  # Insère le tiers uniquement si aucun tiers du même nom n'existe.
  AND NOT EXISTS (
      SELECT 1
      FROM llx_societe s
      WHERE s.nom = {nom_sql}
  );

""")

# Fin du code Python intégré au script Bash.
PY

# Annonce le début de l'exécution des requêtes SQL.
echo "Import enrichi des Tiers..."

# Exécute le client MariaDB dans le conteneur Docker.
# -i transmet le contenu du fichier SQL à l'entrée standard.
# -e définit la variable d'environnement MYSQL_PWD pour cette commande.
# Le mot de passe n'est ainsi pas écrit directement dans les arguments de mariadb.
docker exec -i -e MYSQL_PWD="$DB_PASSWORD" \
    "$DB_CONTAINER" \
    mariadb -u "$DB_USER" "$DB_NAME" < "$TMP_SQL"

# Affiche un message lorsque l'import s'est terminé sans erreur détectée.
echo "Import terminé."
```