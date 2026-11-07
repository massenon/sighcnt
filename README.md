# SIGH-CNT — monorepo

Système Intégré de Gestion Hospitalière de la **CLINIQUE NASSIERA TOO SARL** (Natitingou, Bénin).
~18 000 dossiers patients, ~30 agents, 14 modules (M1 Patients → M14 Sécurité), plus MECeF et
Rapports. Langue de travail : le **français**.

## Ce que contient le dépôt

| Dossier | Rôle | État |
|---|---|---|
| `prototype_html/` | **Maquette de référence** : 305 écrans, manifeste RBAC, moteurs métier, bancs d'essai (66 scénarios, audit RBAC). Source des écrans à porter. | gelée, fonctionnelle |
| `apps/poste/` | Application de **poste de travail** : autonome hors ligne (SQLite local), reprend les écrans du prototype, se synchronise avec le hub. | à construire |
| `apps/hub/` | **Serveur de clinique** : autorité de synchronisation, invariants (RG-01→14), RBAC côté serveur, journal d'audit, passerelle MECeF, sauvegardes. | à construire |
| `apps/vitrine/` | Site public de la clinique (`frontend_html/` de l'ancien dépôt — à rapatrier, **ne se supprime jamais**). | à rapatrier |
| `packages/domaine/` | Règles de gestion et moteurs (parcours transactionnel, prise en charge, BFR, paie), TypeScript pur sans entrée-sortie. | à extraire du prototype |
| `packages/schema/` | Schéma des données (SQLite poste / PostgreSQL hub), migrations numérotées, `VERSION` unique. | à construire |
| `packages/rbac/` | Manifeste des écrans, rôles et matrice des droits — **une source, deux consommateurs** (poste et hub). | à extraire de `nav.js` |
| `packages/sync/` | Journal d'opérations, horloge logique hybride, client et serveur de synchronisation. | à construire |
| `packages/referentiels/` | Les documents de cadrage devenus référentiels versionnés (`data-*.js`). | à extraire |
| `packages/impression/` | Gabarits A4, rouleau 80 mm, carte CR80 ; en-tête légal unique. | à extraire de `print.js` |
| `infra/` | Installation du hub (Docker Compose), installeur des postes, sauvegardes, procédure de reprise. | à construire |
| `docs/` | Architecture (ADR), PRD, plans, spécifications, documents de cadrage. | en cours |

**Commencer par lire** `CLAUDE.md` (doctrine, règles de gestion, pièges du prototype) puis
`docs/architecture/ARCHITECTURE-CIBLE.md` (la cible hors ligne d'abord et sa synchronisation).

## Commandes

```bash
npm install                 # espaces de travail apps/* et packages/*
npm run prototype:install   # outillage de la maquette (Tailwind, Puppeteer)
npm run prototype:verify    # lint + build + check + test de la maquette
npm run prototype:serveur   # la maquette avec sa base PostgreSQL (port 8080)
```

La maquette garde son outillage propre (`prototype_html/package.json`) : elle n'est pas un espace
de travail npm, pour que ses bancs d'essai restent reproductibles tels quels.

## Cycle de développement (skills Claude Code)

Les skills du dossier `.claude/skills/` encadrent le cycle : `/prd` (exigences) → `/adr`
(décision d'architecture) → `/spec` (spécification d'écran ou de module) → `/plan` (plan
d'implémentation) → `/test-plan` (stratégie de vérification) → `/review` (revue) → `/release`
(livraison). Chacun écrit dans `docs/` au gabarit fourni.

## Secrets

Aucun identifiant ne se versionne : `*.local.php`, `.env` et les exports `*.sql` sont ignorés.
Copier `prototype_html/api/config.local.exemple.php` vers `config.local.php` sur chaque poste.
