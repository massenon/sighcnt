# Documentation SIGH-CNT

Point d'entrée de tous les documents Markdown du dépôt. Langue de travail : le français.
Les règles de gestion (RG-01→14), la doctrine et les pièges sont dans [`CLAUDE.md`](../CLAUDE.md) à la racine.

## Pour démarrer

| Document | Pour quoi faire |
|---|---|
| [`guides/GUIDE-DEMARRAGE.md`](guides/GUIDE-DEMARRAGE.md) | **Cloner, tester, mettre à jour, repartir d'une base propre** (installation, bancs d'essai, sauvegarde, restauration) |
| [`guides/BIBLIOTHEQUE-DOCUMENTAIRE.md`](guides/BIBLIOTHEQUE-DOCUMENTAIRE.md) | Les ~40 documents demandés le 27/10/2026 : matière existante, compétence productrice, statut |

## Architecture et décisions

| Document | Contenu | Statut |
|---|---|---|
| [`architecture/ARCHITECTURE-CIBLE.md`](architecture/ARCHITECTURE-CIBLE.md) | La cible : postes autonomes, hub en étoile, journal d'opérations, sécurité, MECeF, sauvegarde, trajectoire | à arrêter |
| [`architecture/DICTIONNAIRE-DONNEES.md`](architecture/DICTIONNAIRE-DONNEES.md) | Les 139 tables PostgreSQL de tous les modules (engendré) | engendré |
| [`architecture/adr/ADR-0001`](architecture/adr/ADR-0001-local-first-hub-etoile.md) | Postes autonomes, hub en étoile, synchronisation par journal d'opérations | proposé |
| [`architecture/adr/ADR-0002`](architecture/adr/ADR-0002-monorepo.md) | Monorepo npm | accepté |
| [`architecture/adr/ADR-0003`](architecture/adr/ADR-0003-stack-poste-hub-mobile.md) | **Pile technique** : Flutter/Dart (poste + mobile), hub Dart, domaine partagé ; boîtier MECeF physique | proposé — attend l'acceptation de la Direction après le banc de validation |
| ADR-0004 | Moteur de synchronisation (PowerSync / ElectricSQL / maison) | à écrire, après le banc (plan S3) |
| [`architecture/adr/ADR-0005`](architecture/adr/ADR-0005-laravel-api-flutter-poste-pwa.md) | **Réévaluation d'ADR-0003** : API Laravel + panneau Livewire, poste Flutter, PWA Vue ; où vivent les règles métier | proposé (demande Direction 27/10/2026) |

Index détaillé : [`architecture/README.md`](architecture/README.md).

## Exigences (PRD)

| PRD | Objet | Statut |
|---|---|---|
| [`PRD-M12-cloture-exercice`](prd/PRD-M12-cloture-exercice.md) | Clôture d'exercice, à-nouveaux, lecture seule des exercices clos | livré (vague 69) |
| [`PRD-M6-suivi-ventes-secteurs`](prd/PRD-M6-suivi-ventes-secteurs.md) | Ventes par patient et par secteur | livré (vague 69) |
| [`PRD-SOCLE-application-sans-rechargement`](prd/PRD-SOCLE-application-sans-rechargement.md) | Document unique, notifications, planificateur | P0/P1 livrés (vagues 69-70) ; flux poussé et deltas par séquence restent |
| [`PRD-SOCLE-synchronisation-bidirectionnelle`](prd/PRD-SOCLE-synchronisation-bidirectionnelle.md) | Synchronisation dans les deux sens : poste, hub, client web, mobile | brouillon 26/10/2026 |

Index : [`prd/README.md`](prd/README.md).

## Plans, tests, livraisons

| Document | Objet |
|---|---|
| [`plans/PLAN-synchronisation-bidirectionnelle`](plans/PLAN-synchronisation-bidirectionnelle.md) | Plan en cinq phases (S0→S5), du prototype au mobile |
| [`plans/PLAN-implementation-laravel-flutter-pwa`](plans/PLAN-implementation-laravel-flutter-pwa.md) | Plan d'implémentation Flutter + Laravel (API de synchro, panneau) + PWA : NFR calibrées, phases P0→P7, compétences |
| [`plans/PLAN-implementation-v2`](plans/PLAN-implementation-v2.md) | **Plan en vigueur (30/10/2026)** : `sigh_web` abandonné, `apps/web` seul Laravel, poste fileul/mère = une application, tâches T1→T8 et leur état |
| [`plans/PLAN-conversion-305-ecrans`](plans/PLAN-conversion-305-ecrans.md) | Conversion fidèle des 305 écrans PHP/JS en Dart : mesures, niveaux de parité N1–N4, tranches, tâches T9→T20 |
| [`architecture/MODULES-COMPLEMENTAIRES-MERE`](architecture/MODULES-COMPLEMENTAIRES-MERE.md) | Les 22 modules complémentaires du poste mère (5 faits, 17 à écrire) et l'activation du mode mère |
| [`architecture/ECARTS-MAQUETTE`](architecture/ECARTS-MAQUETTE.md) | Écarts de la maquette relevés au portage (portés fidèlement, signalés, à arbitrer) |
| [`specs/SPEC-protocole-synchronisation`](specs/SPEC-protocole-synchronisation.md) | **Protocole de synchronisation** : poste mère, fileuls, mobiles, relais en ligne ; appairage, journal, curseurs, conflits, restauration, recette | brouillon 29/10/2026 |

Index : [`plans/README.md`](plans/README.md). Les spécifications d'écran vont dans [`specs/`](specs/README.md).

## Cadrage (sources de vérité)

[`cadrage/README.md`](cadrage/README.md) — CDCT, rapport de cadrage, scans, classeurs, notes d'exigences.
Aucun tarif, seuil ou numéro n'existe dans le logiciel sans une pièce ici.

## Skills du dépôt

`/prd`, `/adr`, `/spec`, `/plan`, `/test-plan`, `/review`, `/release` (dossier `.claude/skills/`) écrivent dans
`docs/` : un PRD dans `prd/`, une ADR dans `architecture/adr/`, un plan dans `plans/`, etc.

## Ajouter un document

1. Le placer dans le sous-dossier de son type (guide, PRD, plan, spec, ADR).
2. Le nommer comme ses voisins (`PRD-<module>-<sujet>.md`, `PLAN-<sujet>.md`…).
3. L'ajouter au tableau de ce fichier **et** à l'index du sous-dossier.
