# Architecture

- **`DICTIONNAIRE-DONNEES.md`** — les 139 tables PostgreSQL de tous les modules (engendré depuis le prototype ; schéma : `packages/schema/postgres/0001_modules.sql`).
- **`ARCHITECTURE-CIBLE.md`** — la cible : postes autonomes hors ligne, hub de clinique en étoile,
  synchronisation par journal d'opérations, sécurité, MECeF, sauvegarde, trajectoire, arbitrages.

## Décisions (ADR)

| N° | Titre | Statut |
|---|---|---|
| [ADR-0001](adr/ADR-0001-local-first-hub-etoile.md) | Postes autonomes hors ligne, hub en étoile, journal d'opérations | proposé |
| [ADR-0002](adr/ADR-0002-monorepo.md) | Monorepo npm : apps et packages partagés | accepté |
| [ADR-0003](adr/ADR-0003-stack-poste-hub-mobile.md) | Un seul langage, Dart : poste Windows/Linux et smartphone en Flutter, hub en Dart, règles partagées ; boîtier MECeF physique | proposé |
| ADR-0004 | Moteur de synchronisation (PowerSync / ElectricSQL / maison) — après le banc de validation d'ADR-0003 | à écrire |

Nouvelle décision : `/adr`.
