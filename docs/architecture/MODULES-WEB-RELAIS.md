# Modules de `apps/web` — le relais en ligne et son panneau superadmin

Le relais est **opaque** (ADR-0005) : il stocke des enveloppes chiffrées et des indicateurs sans nom ; il ne détient aucune clé ; il n'appelle jamais la mère. Son panneau (Laravel 12 + Livewire, sans `npm`) sert au superadmin à vérifier que la mère est vivante, à jour et sauvegardée — **jamais** à lire un dossier.

Prototype : domaine « Relais en ligne » de la maquette, module `RLS`, 12 pages `rls-*` (admin seulement). **Quatre écrans existent déjà** côté Laravel ; les huit autres sont ceux que l'on doit attendre d'un relais exploité.

| Id | Module | Dans `apps/web` | Contenu |
|---|---|---|---|
| `rls-tableau` | Tableau de bord du relais | ✅ `Tableau` | mère vivante ? appareils, volumes, alertes |
| `rls-appareils` | Appareils | ✅ `Appareils` | état, dernier contact, révocation journalisée |
| `rls-codes` | Codes d'appairage | ✅ `Codes` | empreintes, expiration, usage unique |
| `rls-journal` | Journal d'audit | ✅ `Journal` | qui a fait quoi ; purge de l'audit seule |
| `rls-boites` | Boîtes aux lettres | ⬜ | volumes par mobile et par sens, rangs contigus |
| `rls-indicateurs` | Indicateurs reçus | ⬜ | historique des compteurs publiés par la mère |
| `rls-alertes` | Alertes et notifications | ⬜ | règles (battement, appareil bloqué, disque, cron), courriel |
| `rls-superadmin` | Comptes superadmin | ⬜ | comptes, sessions, double facteur |
| `rls-parametres` | Paramètres du relais | ⬜ | seuil de battement, rétention, secret (jamais en base) |
| `rls-hebergement` | Hébergement (cPanel) | ⬜ | PHP, base, cron, disque, certificat |
| `rls-sauvegarde` | Sauvegarde du relais | ⬜ | export avant migration |
| `rls-opacite` | Preuve d'opacité | ⬜ | ce que le relais voit et ne voit pas |

Contraintes d'hébergement qui s'imposent à tout écran : PHP ≥ 8.2, PostgreSQL, cron d'une minute, pas de SSH, pas de Redis, pas de WebSocket, pas de `npm`.
