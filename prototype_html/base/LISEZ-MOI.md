# Base du prototype — export et import

`sigh_prototype.sql` est un export **PostgreSQL** complet de la base du prototype,
engendré par `pg_dump --clean --if-exists --no-owner --no-privileges`.

Vérifié le 08/10/2026 : réimporté dans une base neuve **sans une seule erreur**,
et rend **101 collections / 10 568 fiches / 17 comptes**, tous à mot de passe haché.

## Importer

Dans Laragon (PostgreSQL 16 doit être démarré) :

```bash
# 1. la base d'accueil
psql -U postgres -c "CREATE DATABASE sigh_prototype;"

# 2. le contenu
psql -U postgres -d sigh_prototype -f base/sigh_prototype.sql
```

Le fichier porte `DROP ... IF EXISTS` : on peut le rejouer sur une base déjà
remplie, il la remet à l'état de l'export.

## Les quatre tables

| Table | Ce qu'elle porte |
|---|---|
| `collections` | **Le magasin** — une ligne par collection (`patients`, `factures`, `ecritures`…), la donnée en `jsonb`. C'est là que vit tout le métier. |
| `meta` | Les clés hors collection : `_version` du schéma, drapeaux d'amorçage. |
| `utilisateurs` | **Les comptes**, mot de passe **haché** (`password_hash`). Jamais de secret en clair dans un export que l'on s'échange. |
| `sessions_poste` | Les sessions ouvertes. Le jeton est engendré par le serveur ; il peut se vider sans dommage. |

## Se connecter après import

Identifiants : ceux de la table `utilisateurs` (`c.bassongui`, `e.orouyo`,
`a.dieyabidi`…). **Mot de passe d'origine : `demonstration`**, et chaque compte
porte `doit_changer = true` — c'est un jeu de démonstration, pas un
paramétrage de production.

## Ce qu'il faut savoir avant d'importer

- **Les identifiants de connexion à PostgreSQL ne sont pas dans le dépôt.**
  Ils vivent dans `api/config.local.php`, ignoré par git ; `api/config.local.exemple.php`
  dit quoi y mettre.
- **La variable d'environnement `SIGH_BASE` surcharge le nom de la base.**
  C'est ce qui permet aux bancs d'essai de tourner sur une base jetable sans
  jamais toucher celle de travail.
- **Le schéma se crée tout seul** si les tables manquent (`sigh_installer`), et
  les 17 comptes se sèment au premier appel de `api/auth.php` sur une table
  vide. Un import n'est donc pas obligatoire pour démarrer — il sert à
  retrouver **ce jeu de données précis**.
- **Ce fichier n'est pas suivi par git** : c'est une donnée, pas du code, et
  5,4 Mo de SQL n'ont rien à faire dans l'historique. Il se régénère par
  `pg_dump` à tout moment.
