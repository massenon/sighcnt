# PLAN : écran « Synchronisation » du panneau du relais

PRD : `docs/prd/PRD-RELAIS-synchronisation-fileuls-mere-mobiles.md`. Lot RLS-SYNC, 13/11/2026. Règle de rédaction : pas de tiret cadratin comme ponctuation.

Ordre retenu (le protocole d'abord, comme le veut `sigh-sync`) : chaque étape est commitée verte.

| Étape | Contenu | Fichiers | Preuve |
|---|---|---|---|
| 1. Protocole et mère | liste blanche partagée, vecteurs, domaine Dart, mère Dart, mère et relais de référence du banc | `packages/domaine/lib/src/mere/synchro_fileuls.dart`, `packages/domaine/test/vecteurs/synchro_fileuls.json`, `packages/sync_dart/lib/src/pont.dart`, `packages/sync/banc/synchro.js`, `mere.js`, `relais.js` | `dart test` (domaine, sync_dart), `node --test banc/synchro.test.js`, mutations |
| 2. Relais | validation avant enregistrement, historique à part, purge, réglages, relève des mobiles, trois alertes, export | `apps/web/app/Relais/Synchro/*`, `RelaisController`, `Surveillance`, migration `2026_11_13_000000_relais_synchronisation.php` | `php artisan test`, scénarios `SYN1` et `SYN2` du banc |
| 3. Écran | composant Livewire, accès superadmin, réglages aux paramètres, opacité étendue | `Synchronisation.php`, `ExigerSuperadmin.php`, `Parametres.php`, `Opacite.php` | `php artisan test` (dont `ParitePanneauTest`, inchangée) |
| 4. Documents | écarts, décisions, PRD, plan, parité, spécification, `CLAUDE.md` | `docs/` | relecture |

## Schéma

Pas d'incrément de `VERSION` (la maquette n'est pas touchée). Une migration Laravel : table `relais_synchro_historique`, colonnes `relais_appareils.dernier_releve` et `releve_n`, colonne `users.superadmin` (vrai par défaut), réglages semés dans `relais_meta`. Aucune migration du poste ni de la mère (la mère calcule sur sa base existante).

## Retour arrière

Défaire la migration (`down` fournie). La mère qui publie `fileuls` à un relais ANTÉRIEUR au lot n'est pas refusée (l'ancien relais enregistre le champ libre) ; un relais récent qui reçoit une mère ANTÉRIEURE n'en reçoit pas de tableau et affiche « non publié ».
