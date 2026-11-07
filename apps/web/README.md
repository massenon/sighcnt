# apps/web — relais en ligne et panneau superadmin (Laravel 12, cPanel mutualisé)

Rôle **opaque** (ADR-0005, spec §12–13) : le relais **ne lit jamais** un dossier. Il stocke des **enveloppes chiffrées de bout en bout**
(clé de clinique que seuls les appareils de la clinique détiennent), des **indicateurs sans nom de patient**, le battement de cœur de la mère,
et porte un **panneau superadmin minimal** (Blade + Livewire + Alpine) : appareils et jetons, journaux techniques, sauvegardes, restauration,
supervision. **Aucune règle de gestion, aucun écran métier.**

Contraintes d'hébergement (cPanel mutualisé) : PHP ≥ 8.2, PostgreSQL, `cron` chaque minute, **pas de SSH, pas de Redis, pas de WebSocket**.
`composer install --no-dev --optimize-autoloader` et la compilation des ressources se font **sur le poste de développement** ; on téléverse
le dossier (racine web = `public/`). Files de tâches en pilote `database`, `queue:work --stop-when-empty` par `cron`. `.env` hors dépôt.

Contrat du relais : `packages/sync/banc/relais.js` (implémentation de référence) et `docs/specs/SPEC-protocole-synchronisation.md` §12.
**État : squelette Laravel 12 sans code métier.**

## Essai local sur un poste de développement (PostgreSQL)

Le relais tourne sur PostgreSQL, comme en production : un essai local sur SQLite ne prouverait rien sur ce que l'hébergeur servira.

1. Installer PostgreSQL 15 ou plus, puis créer la base et son utilisateur (`psql -U postgres`) :
   ```sql
   CREATE USER sigh_relais WITH PASSWORD 'choisir-un-mot-de-passe';
   CREATE DATABASE sigh_relais OWNER sigh_relais;
   ```
2. Dans `apps/web` : `composer install`, puis `Copy-Item .env.example .env` (PowerShell) ou `cp .env.example .env`. Renseigner `DB_PASSWORD` et `RELAIS_SECRET_MERE` (un texte long et aléatoire), puis `php artisan key:generate`.
3. `php artisan migrate`, puis `php artisan relais:superadmin votre@courriel.bj --mot-de-passe='…'` (12 caractères au moins) pour créer le compte du panneau, et `php artisan serve`.
4. Pour la PRODUCTION, partir de `production.env.exemple` (à copier en `.env` sur le serveur, jamais dans le dépôt).

Les tests (`php artisan test`) utilisent SQLite en mémoire : ils n'ont besoin d'aucune base installée.

Dans le poste, « Activer la mère » demande trois choses : l'adresse du relais (par exemple `sighcnt.nassieratoo.com`), le secret de la mère (le même texte que `RELAIS_SECRET_MERE` du `.env` du relais) et la clé de clinique (16 caractères au moins, à ranger sur papier : sans elle, rien de ce qui quitte le serveur ne peut être restauré).
