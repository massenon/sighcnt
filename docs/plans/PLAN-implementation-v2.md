# Plan d'implémentation v2 — du 30/10/2026

Remplace les passages contraires de `PLAN-implementation-laravel-flutter-pwa.md`. **Décisions de la Direction du 30/10/2026** :

1. **`sigh_web/` est abandonné.** Aucun audit, aucune reprise : le seul Laravel est **`apps/web`**, à implémenter ici.
2. Quatre projets, un dépôt : `apps/poste`, `apps/mobile`, `apps/web`, `packages/domaine`.
3. **Le poste fileul et le poste mère sont UNE SEULE application Flutter desktop.** La mère est le même exécutable avec des modules **en plus** (service de synchronisation, console, supervision, sauvegardes, arbitrage des conflits, appareils, réinitialisation). Le mode est une donnée de configuration du poste, pas deux produits.
4. L'implémentation avance **par tâches** (liste ci-dessous), chacune vérifiable et commitée.

## Architecture de l'application poste

```
apps/poste/lib/
  core/          thème (jetons), configuration du poste (mode fileul | mère), session
  modules/       registre de modules : { id, libelle, icone, modes, droit, construire }
    commun/      modules présents sur TOUT poste (accueil, caisse, patients…) — par tranches verticales
    mere/        modules réservés à la mère (supervision, appareils, conflits, journal, maintenance)
  shell/         coque : barre de navigation FILTRÉE par mode ET par droits (matrice packages/rbac), pastille de sync
  sync/          pastille d'état ; branchement de packages/sync_dart
```

- **Le registre est la source unique** de la navigation (comme `nav.js` pour la maquette) : un module déclare les modes qui le portent ; la coque n'affiche jamais un module d'un autre mode. Un poste fileul ne contient pas le code d'arbitrage des conflits dans son menu, et la mère affiche tous les modules communs **plus** les siens.
- La mère embarque le **service** (`packages/sync_dart`, PostgreSQL local) ; le fileul n'embarque que le **client** de synchronisation. Même base de code, même thème, mêmes écrans métier.
- Les droits viennent de `packages/rbac/data/rbac.json` (engendré). Une commande refusée est **absente**, pas grisée.

## Tâches (ordre d'exécution)

| # | Tâche | Critère de fin |
|---|---|---|
| T1 | **Coque unique** : registre de modules, mode fileul/mère à l'exécution, navigation filtrée mode + droits ; console de la mère déplacée en modules `mere/` | tests : fileul ne voit aucun module mère ; mère voit tout ; analyse propre |
| T2 | **`packages/domaine`** : moteur de droits (lecture de `rbac.json`), session, `C.money`/dates déjà portés ; ajouter `peutVoir/peutEditer(role, ecran)` | tests sur la matrice extraite (parité avec `N.droitsEcran`) |
| T3 | **`apps/web`** : relais déjà conforme (23 tests) → ajouter ce qui manque pour l'exploitation : commande de purge, rotation des jetons, journal d'audit consultable, `production.env.exemple` vérifié, procédure cPanel testée sur un `php artisan` à blanc | PHPUnit vert ; checklist `DEPLOIEMENT-CPANEL.md` rejouée |
| T4 | **Branchement de la synchronisation dans le poste** : client fileul (`sigh_sync`) derrière une interface, pastille alimentée par l'état réel | test avec faux dépôt + banc `banc:cible` inchangé |
| T5 | **`apps/mobile`** : appairage, profil soignant (tournée), profil réception de secours, source de données injectable | tests de widgets ; aucun contact avec la LAN |
| T6 | **Tranche 1 — caisse + MECeF + impression** (modules communs) : moteur dans `packages/domaine` avec vecteurs extraits de la maquette | vecteurs de la maquette rejoués ; RG-03/09/10 |
| T7 | Tranches suivantes selon `docs/architecture/PARITE-MAQUETTE.md` (pharmacie/stocks/achats, laboratoire, parcours clinique, assurances/compta, RH/paie/admin) | statuts `parite-statuts.json` |
| T8 | Packaging : installation de la mère en service Windows/Linux, base locale chiffrée (SQLCipher), compilation native | hors de cet environnement de rédaction — documenté et non testé tant qu'il n'est pas exécuté sur un poste équipé |

## Hors de portée de cet environnement (dit d'avance)

Compilation Windows/Android, SQLCipher, service Windows, MECeF physique (protocole non documenté, dix questions au fournisseur dans l'ADR), tests de charge, revue de sécurité externe.
