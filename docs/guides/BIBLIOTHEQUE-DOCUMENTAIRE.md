# Bibliothèque documentaire SIGH — les documents demandés, leur source, leur producteur

Compagnon de [`plans/PLAN-implementation-laravel-flutter-pwa.md`](../plans/PLAN-implementation-laravel-flutter-pwa.md).
Pour chaque document demandé par la Direction le 27/10/2026 : **où se trouve déjà la matière** dans le dépôt, **quelle compétence l'écrit**, **où il sera rangé**, et son **statut**.

**Règle** : un document cite sa source (`CLAUDE.md`, `prototype_html/…`, `docs/cadrage/…`). Ce qui n'en a pas est une proposition marquée « à valider ». Rien n'est inventé pour remplir une rubrique.

Légende statut : **existe** (déjà au dépôt) · **à extraire** (la matière est dans la maquette, à sortir mécaniquement) · **à rédiger** · **à décider** (attend une réponse de la Direction).

## A. Fondations

| Document demandé | Matière existante | Compétence | Rangé dans | Statut |
|---|---|---|---|---|
| `MASTER_INSTRUCTIONS.md` (instructions maîtres) | `CLAUDE.md` (doctrine, RG-01→14, pièges) | `engineering:documentation` | `docs/guides/` + skill `.claude/skills/sigh-maitre` | à rédiger (condenser CLAUDE.md, ~3 000 lignes → 1 page de principes + renvois) |
| `GLOSSAIRE.md` | libellés de `nav.js`, `data.js`, `CLAUDE.md` | `engineering:documentation` | `docs/guides/` | à extraire |
| `DICTIONNAIRE_MEDICAL_COPYWRITING_INSTRUCTION.md` | libellés des écrans, référentiels (`data-labo.js`, `data-maternite.js`, `data-imagerie.js`, `D.PATHOLOGIES`) | `design:ux-copy` | `docs/design/` | à extraire ; **vocabulaires arbitrés par un professionnel restent marqués** (ex. « Amnios », six secteurs) |
| `STRUCTURE_PAGE_MAQUETTES.md`, `STRICT_RESPECT_PAGE_STRUCTRE_INSTRUCTION.md`, `PAGE_SECTION_ORDER_INSTRUCTION.md` | gabarit standard de CLAUDE.md (header → KPI → cartes → filtres → tableau → CRUD → tiroir), `K.dash` (hero → accès rapides → indicateurs), `K.pageFormulaire` | `design:design-system` | `docs/design/` | à extraire |
| `RESPECT_100%_OF_TEMPLATE_LAYOUT_INSTRUCTIONS.md`, `No redesign…md` | **`PRD-FLUTTER-poste-fidelite-maquette`** (définition mesurable de la fidélité, non-objectif « pas de redesign ») | `/prd` | `docs/prd/` | **existe** |

## B. Produit

| Document demandé | Matière existante | Compétence | Rangé dans | Statut |
|---|---|---|---|---|
| BRS (besoins métier) | `docs/Rapport_de_Cadrage…` (AS-IS, besoins §10.1–10.13, MoSCoW), `docs/cadrage/` | `/prd` | `docs/cadrage/` | à rédiger (synthèse) |
| PRD | `docs/prd/` (5 PRD) | `/prd`, `product-management:write-spec` | `docs/prd/` | **existe** pour clôture, ventes, sans-rechargement, sync, Flutter ; à écrire pour Laravel/PWA |
| SRS / FRS | CDCT (EF-M1→EF-M14, UC-01→08), 306 pages du manifeste | `/spec` | `docs/specs/` | à rédiger, **module par module** (groupe E) |
| NFRS | PLAN §2 (cibles calibrées) | `engineering:system-design` | `docs/specs/` | proposé, **à décider** (Q4 d'ADR-0005) |
| Règles métier | `CLAUDE.md` : RG-01→14 + règles nommées par vague | `/spec` | `docs/specs/REGLES-GESTION.md` | à extraire (une règle = un identifiant, une source, un vecteur de test) |
| `CARTOGRAPHIE DE DIFFERENTS MODULES` | `nav.js` (14 modules + MECeF/GED/RAP/PIL/CFG/DASH, domaines, rangées, alias, `secondaire`) | `engineering:architecture` | `docs/architecture/` | à extraire (engendré depuis le manifeste) |
| `ARCHITECTURE_DES_PROCESSUS_MÉTIER_DE_CHAQUE PAGES` | `parcours.js`, `K.parcours` (13 postes), scénarios 1→74 | `/spec` | `docs/specs/processus/` | à extraire des scénarios |

## C. Architecture, données, droits, synchronisation

| Document demandé | Matière existante | Compétence | Rangé dans | Statut |
|---|---|---|---|---|
| Architecture (Clean Architecture, Laravel, Vue PWA, Flutter, Livewire) | ADR-0001, 0003, **0005** ; `ARCHITECTURE-CIBLE.md` | `/adr`, `engineering:architecture` | `docs/architecture/` | ADR-0005 **proposé** ; document d'architecture à rédiger après acceptation |
| `SYSTEM_INSTRUCTIONS_CLAUDE_PROJECT_LARAVEL_WEB_LIVEWIRE_VUE_JS` | — | `engineering:documentation` | skill `.claude/skills/sigh-laravel` | à rédiger après acceptation d'ADR-0005 |
| `SYSTEM_INSTRUCTIONS_CLAUDE_PROJECT_FLUTTER`, `CONVERT_TAILWIND_IN_DART_FLUTTER` | PLAN §6 (jetons) | `design:design-handoff` | skill `.claude/skills/sigh-flutter` | à rédiger ; la conversion est **engendrée** depuis des jetons, pas décrite |
| `DICTIONNAIRE_DONNEES_COMPLET`, ERD, contraintes | `docs/architecture/DICTIONNAIRE-DONNEES.md` (139 tables, 18 schémas, 55 clés étrangères), `packages/schema/postgres/0001_modules.sql` | `engineering:system-design` | `docs/architecture/` | **existe** (engendré) ; ERD à engendrer ; migrations Laravel à dériver |
| Migrations | `0001_modules.sql` | — | `apps/api/database/migrations/` | à dériver, **jamais écrites à la main en parallèle** |
| `ROLE_ET_PERMISSIONS.md`, `RBAC_ACTIONS.md`, `ADMIN_ACTIONS.md` | `nav.js`, collection `rbac`, `npm run inventaire-rbac` → `newdocs/INVENTAIRE-RBAC.md`, `audit-rbac` | `/spec` | `docs/specs/RBAC.md` + matrice JSON | à extraire ; **la matrice JSON est la source unique** lue par Laravel, Flutter et Vue |
| `SYNCRONISATION_FLUTTER_API_BIDIRECTIONNEL…`, `SYNC__PROJECT_LARAVEL_LIVEWIRE_FLUTTER` | `PRD-SOCLE-synchronisation-bidirectionnelle`, `PLAN-synchronisation-bidirectionnelle` | `/spec`, `/plan` | `docs/specs/` | PRD + plan **existent** ; spec de l'endpoint Laravel à écrire |
| Login, session, sécurité (`LOGIN_DECONNEXION…`, `SESSION_USER_CONNECTION`, `SECURITE_LOGIN`) | `api/auth.php`, `api/session.php`, `auth-*.php`, verrouillage 15 min, jeton serveur, `tentativesConnexion` | `/spec` | `docs/specs/securite/` | à extraire ; mot de passe **saisi, jamais conservé** |

## D. Conception UI/UX

| Document demandé | Matière existante | Compétence | Rangé dans | Statut |
|---|---|---|---|---|
| `UI_UX_DESIGN_SYSTEM.md`, `FULL_DESIGN_SYSTEM_INSTRUCTION.md`, `LAYOUT_INSTRUCTION.md` | `tailwind.config.js`, `src/input.css`, `ui.js`, `_kit.js` | `design:design-system` | `docs/design/` | à extraire ; **jetons en JSON** (PLAN §6) |
| `TABLES_ERGONOMIE_DESIGN_FOLLOW.md`, `FILTRES DANS LES TABLES_FOLLOW_PROTOTYPE.md` | `U.dataTable` (tri, filtre, pagination, `plageDates`, `searchable`), `filtres en force` portés sur l'état imprimé | `design:design-system` | `docs/design/` | à extraire |
| `MODAL_FORMULAIRE_CRUD_INSTRUCTION.md`, `MODAL_DELETE_POPUP_WARMING.md` | `U.modal`, `U.form` à six colonnes, `U.combo`, `K.pageFormulaire`, **archivage RG-14** (pas de suppression), `U.confirm` | `design:design-system` | `docs/design/` | à extraire ; **« supprimer » = archiver, annulable** |
| `NOTIFICATIONS_SYSTEMS_INSTRUCTION`, `TOAST_INSTRUCTION` | `notifications.js` (événement → moteur → distribution → son), `U.toast`, `U.toastDiffere` | `design:design-system` | `docs/design/` | à extraire |
| `REALTIME_CLOCK_NOTIFICATION`, `REALTIME_MODAL_NOTIFICATION_OPEN_APP_FLUTTER_LARAVEL_WEB`, `REALTIME_Rappel de Prophylaxie du Jour` | `api/cron.php`, `notifications_serveur`, sondage 3 s, pastille de synchro | `/spec` | `docs/specs/` | à extraire ; **le rappel de prophylaxie n'existe pas à la maquette** → proposition à valider |
| `ALERTE_CRITIQUE_DE_STOCK_MODULE_IMPLEMENTATION` | `PR.alerterStock`, seuils fixés par la clinique, regroupement au-delà de 3 | `/spec` | `docs/specs/` | à extraire |
| `RESPONSIVE_BEHAVIOR_INSTRUCTION`, `PAGES_KPIS_UX_MOBILE_DESKTOP_INSTRUCTIONS`, `ERGONOMIE_EXPÉRIENCE UTILISATEUR UNIFIÉE (UX)` | règles responsive de CLAUDE.md (sous 768 px : ruban empilé, KPI en accordéons, tableaux en cartes) | `design:design-system`, `design:accessibility-review` | `docs/design/` | à extraire |
| `DIRECTIVE D'ÉDITION PDF UNIFIÉE_ACCROSS_ALL_MODULES.md` | `print.js`, 333 états, en-tête légal unique, trois gabarits (A4, ticket 80 mm, CR80), `somme` calculée | `/spec` | `docs/specs/impression/` | à extraire |

## E. Spécifications de modules (écran par écran, onglet par onglet)

Une spécification par module, par `/spec`, **dans l'ordre des tranches** du plan :

| Ordre | Module(s) | Source principale |
|---|---|---|
| 1 | M8 caisse + MECeF + impression | `m8-*.php`, `mecef-*.php`, scénarios caisse |
| 2 | M6 pharmacie & stocks, M7 achats | `m6-*`, `m7-*` |
| 3 | M5 laboratoire, M2 imagerie | `m5-*`, `m2-imagerie-*` |
| 4 | M1, M2, M3, M4 (clinique) | `m1-*`…`m4-*` |
| 5 | M9, M12 | `m9-*`, `m12-*` |
| 6 | M10, M11, M13, M14, GED, RAP, PIL, CFG, DASH | restant du manifeste |

Chaque spécification suit le canevas : écrans → onglets → champs (type, obligatoire, source) → actions et droits → états (vide/chargement/erreur) → règles de gestion citées → famille de fusion de chaque écriture → scénarios de recette liés.

## F. Standards, tests, revue

| Document demandé | Matière existante | Compétence | Rangé dans | Statut |
|---|---|---|---|---|
| Standards de développement (Laravel, Livewire, JS, Tailwind, validation, sécurité) | « pièges » de CLAUDE.md (hissage, double clé d'objet, `String.replace`, fonctions de fermeture, amorçage au socle…) | `engineering:documentation` | `docs/guides/` | à extraire (les pièges sont l'expérience payée) |
| Stratégie de test, UAT, critères d'acceptation, jeux de données | 74 scénarios (1 185 vérifications), `audit-rbac` (0 promesse), `check` (0 erreur JS, 0 lien cassé), jeu de démonstration, `sigh_prototype.dump` | `/test-plan`, `engineering:testing-strategy` | `docs/test-plans/` | à rédiger |
| `SANITY_CHECK_COMPLET`, `AUDIT_DE_CONCEPTION_ET_DE_STRUCTURE` | `npm run verify`, balayage des 296 pages | `engineering:testing-strategy` | `docs/test-plans/` | à rédiger |
| `REVUE_DE_CODE_SENIOR_QA_ARCHITECT.md` | skill `/review` | `/review`, `engineering:code-review` | `docs/reviews/` | à rédiger (grille) |
| `SPRINT_COMPLETE__PROJECT_FLUTTER`, `SPRINT_COMPLETE_PROJECT_LARAVEL_LIVEWIRE` | PLAN §3 (phases) | `/plan`, `product-management:sprint-planning` | `docs/plans/` | à rédiger **après P0** (dépend de l'effectif et du banc) |
| Bibliothèque de skills | PLAN §5 | `plugin-authoring`/`skill-creator` | `.claude/skills/` | à rédiger après P2 |

## Ordre de travail recommandé

1. **P0** : décider ADR-0005 (Q1–Q5). Tout le reste en dépend.
2. **P1** : les « à extraire » — mécaniques, sans décision, fort rendement (dictionnaire, RBAC JSON, manifeste, jetons, glossaire, règles).
3. **P2** : les « à rédiger » par groupe, revue de la Direction à chaque groupe.
4. Skills du projet **en dernier** : on n'écrit pas la méthode avant d'avoir le contenu.

## Ce que ce catalogue ne fait pas

Il ne **rédige pas** les quarante documents : il dit lesquels existent, lesquels sortent de la maquette sans décision, et lesquels attendent la Direction. Les rédiger d'un coup ferait inventer — c'est exactement l'écart que la doctrine du dépôt interdit.
