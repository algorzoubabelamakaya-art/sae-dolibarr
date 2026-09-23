# séance du 23/09/2026

#Travail fait:

1- Installation de git et clonage du depot sae-dolibarr sur la vm 
2- Tentative d'installation de façon manuelle (paquet dolideb: abandonné
3-Installation de docker et docker compose sur la vm
4-création d'un docker-compose.yml : les conteneurs MariaDB et Dolibarr
5-lancement réussi de Dolibarr via docker et accessible sur htt://localhost:8080
6-config de bas notament la société iut moduke tiers activé
7-creation du compte utilisateur user.user avec des permissions limitées
Test réussi avec la création d'un tiers BUT3 avec le compte user


#Difficultés rencontrées
1- errreur de syntaxe yml dans docker-compose notamment avec les indentation
2- Mauvaise connexion provoquant la lenteur suite au téléchargement docker

#A faire
1- Générer des données CSV fictive client /fournisseurs
2- importer ces données via le menu outils de dolibarr
3- explorer en détails la gestion des contacts liés aux tiers
