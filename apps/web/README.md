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
