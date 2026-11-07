# ADR-0002 — Un monorepo npm : apps (poste, hub, vitrine) et packages partagés
Statut : **accepté** le 17/10/2026 (initialisation du dépôt)
Date : 2026-10-17
Concerne : organisation du dépôt

## Contexte

Le poste et le hub doivent exécuter **le même** code de droits (`rbac`), de règles (`domaine`),
de schéma (`VERSION`) et de synchronisation (`sync`). Deux dépôts = deux copies = divergence au
premier correctif (leçon payée quatre fois sur le prototype). Le prototype (305 écrans, bancs
d'essai) reste la référence des écrans à porter ; le site vitrine est un livrable distinct qui ne
se supprime jamais.

## Options

1. Dépôts séparés (poste, hub, packages publiés) — versionnage croisé, divergence probable, pas
   d'informaticien pour le tenir.
2. **Monorepo npm workspaces** — un `npm install`, un lint, un test ; le poste et le hub importent
   les mêmes paquets par chemin ; pas d'outil supplémentaire (pas de pnpm/turbo tant que la taille
   ne l'exige pas).
3. Monorepo pnpm + Turborepo — plus rapide à grande échelle ; outillage de plus pour une équipe
   réduite.

## Décision

Option 2. Arborescence :

```
apps/poste  apps/hub  apps/vitrine
packages/domaine  packages/schema  packages/rbac  packages/sync  packages/referentiels  packages/impression
prototype_html/   (maquette gelée, outillage propre, hors workspaces : bancs reproductibles)
infra/hub  infra/poste
docs/architecture(adr)  docs/prd  docs/plans  docs/specs  docs/cadrage
.claude/skills (prd, adr, spec, plan, test-plan, review, release)
```

`node_modules`, `*.local.php`, `.env` et les exports `*.sql` ne sont **jamais** versionnés.

## Conséquences

- Un seul `VERSION`, un seul manifeste, un seul moteur de règles, consommés par deux
  applications.
- Le prototype n'est pas un workspace : ses commandes restent `npm run prototype:*` depuis la
  racine ou `npm run …` depuis son dossier, à l'identique de `CLAUDE.md`.
- Passage à pnpm/Turborepo possible plus tard sans changer l'arborescence.
