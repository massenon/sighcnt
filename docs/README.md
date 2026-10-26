# Documentation SIGH-CNT

Point d'entrée de tous les documents Markdown du dépôt. Langue de travail : le français.
Les règles de gestion (RG-01→14), la doctrine et les pièges sont dans [`CLAUDE.md`](../CLAUDE.md) à la racine.

## Pour démarrer

| Document | Pour quoi faire |
|---|---|
| [`guides/GUIDE-DEMARRAGE.md`](guides/GUIDE-DEMARRAGE.md) | **Cloner, tester, mettre à jour, repartir d'une base propre** (installation, bancs d'essai, sauvegarde, restauration) |

## Architecture et décisions

| Document | Contenu | Statut |
|---|---|---|
| [`architecture/ARCHITECTURE-CIBLE.md`](architecture/ARCHITECTURE-CIBLE.md) | La cible : postes autonomes, hub en étoile, journal d'opérations, sécurité, MECeF, sauvegarde, trajectoire | à arrêter |
| [`architecture/DICTIONNAIRE-DONNEES.md`](architecture/DICTIONNAIRE-DONNEES.md) | Les 139 tables PostgreSQL de tous les modules (engendré) | engendré |
| [`architecture/adr/ADR-0001`](architecture/adr/ADR-0001-local-first-hub-etoile.md) | Postes autonomes, hub en étoile, synchronisation par journal d'opérations | proposé |
| [`architecture/adr/ADR-0002`](architecture/adr/ADR-0002-monorepo.md) | Monorepo npm | accepté |
| [`architecture/adr/ADR-0003`](architecture/adr/ADR-0003-stack-poste-hub-mobile.md) | **Pile technique** : Flutter/Dart (poste + mobile), hub Dart, domaine partagé ; boîtier MECeF physique | proposé — attend l'acceptation de la Direction après le banc de validation |
| ADR-0004 | Moteur de synchronisation (PowerSync / ElectricSQL / maison) | à écrire, après le banc (plan S3) |

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
