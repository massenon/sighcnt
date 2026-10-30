# Plan d'implémentation v2 — du 30/10/2026

Remplace les passages contraires de `PLAN-implementation-laravel-flutter-pwa.md`. **Décisions de la Direction du 30/10/2026** :

1. **`sigh_web/` est abandonné.** Aucun audit, aucune reprise : le seul Laravel est **`apps/web`**, à implémenter ici.
2. Quatre projets, un dépôt : `apps/poste`, `apps/mobile`, `apps/web`, `packages/domaine`.
3. **Le poste fileul et le poste mère sont UNE SEULE application Flutter desktop** (30/10/2026, précisé : *mère = les 305 écrans du fileul + les écrans de ses modules complémentaires, activés sur le serveur local* — voir [`MODULES-COMPLEMENTAIRES-MERE.md`](../architecture/MODULES-COMPLEMENTAIRES-MERE.md) et [`PLAN-conversion-305-ecrans.md`](PLAN-conversion-305-ecrans.md)). La mère est le même exécutable avec des modules **en plus** (service de synchronisation, console, supervision, sauvegardes, arbitrage des conflits, appareils, réinitialisation). Le mode est une donnée de configuration du poste, pas deux produits.
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

## État d'avancement (30/10/2026, fin de journée)

| Tâche | État | Preuve |
|---|---|---|
| T1 Coque unique fileul/mère, registre de modules | **fait** | `apps/poste` : 27 tests, `analyze` propre ; un fileul ne voit aucun module de la mère |
| T2 Moteur de droits (`packages/domaine`) | **fait** | 21 tests, parité exhaustive avec `rbac.json`, mutation détectée ; branché sur le filtre des modules |
| T3 Relais `apps/web` : exploitation | **fait** | 28 tests PHPUnit ; `relais:statut`, `relais:purger` (jamais les enveloppes) |
| T4 Synchronisation dans le poste | **fait** | moteur fileul embarqué ; test bout en bout console ↔ mère ↔ fileul réels, coupure comprise |
| T5 `apps/mobile` | **fait (logique et écrans)** | appairage, soignant, réception de secours ; 5 tests ; le téléphone réel (coffre, biométrie, notifications) n'est pas câblé |
| T6 Tranche 1 : caisse | **partielle** | **portés avec vecteurs de la maquette** : prise en charge RG-09 (21 situations) et encaissement + écriture RG-10 (17 séquences, 23 versements). **Non portés** : émission/scission `-A`/`-B`, ticket 80 mm, impression, MECeF (protocole du boîtier absent des documents), écran de caisse |
| T7 Tranches suivantes | non commencé | |
| T8 Packaging (service Windows/Linux, SQLCipher, compilation native) | non commencé — **impossible dans cet environnement** | |

Écarts de la maquette découverts en portant : `docs/architecture/ECARTS-MAQUETTE.md` (quatre, dont deux touchent la comptabilité — **décision de la Direction attendue**).

## Mise à jour du 30/10/2026 (soir)

| Tâche | État | Preuve |
|---|---|---|
| T6 (partie 2) | **écarts E1 et E3 corrigés** dans la maquette puis portés | vecteurs régénérés ; 64 tests du domaine |
| Prototypes | **fait** : 22 pages « Poste mère », 12 pages « Relais en ligne », simulateur mobile (21 écrans, 4 profils, iPhone 14 / Pixel 8) | `npm run mobile:check` 92/92 ; `build/check.js` 0 erreur |
| T9 Activation du mode mère à l'exécution | **fait** | relais : `POST /mere/activer` (34 tests PHPUnit) ; poste : 43 tests ; le mode vit dans `poste.json`, plus dans une option de compilation |
| Plan en sprints | **fait** | `PLAN-SPRINTS.md` |

## Mise à jour du 30/10/2026 (fin de journée)

| Tâche | État | Preuve |
|---|---|---|
| T10a Coque à l'image de la maquette | **fait** | barre supérieure, ruban à méga-menus **identique à `N.tree()` pour les 22 rôles** (vecteurs), page standard, 187 icônes Lucide, police Inter, accueil du rôle, raccourcis permanents ; 44 tests |
| T10b/c Composants de données (tableau, formulaire 6 colonnes, modale, tiroir, onglets, graphiques, impression) | **non commencé** | prochain sprint (S2–S3) |
| T11 Outillage de parité | **fait** (N1) | 341 fiches de la maquette extraites (`docs/architecture/ecrans/`, 332 ouvertes ; 9 sans page de contenu : banque de sang fermée, écrans d'authentification, enquête publique) ; mesure N1 des écrans Flutter portés : **6 portés, parité de 6 % à 40 %** (`rapport-parite-flutter.json`) ; un statut « porté » est refusé tant que N1 < 100 % |
| Conversion des 321 écrans | **6 écrans ont une page Flutter, aucun n'est à parité** | les 315 autres s'affichent « à convertir » avec leur tranche |
