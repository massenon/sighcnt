# PLAN — Implémentation SIGH : Flutter (poste) + Laravel (API de synchronisation et panneau) + PWA

| | |
|---|---|
| **Statut** | brouillon 27/10/2026 — **conditionné à l'acceptation d'ADR-0005** |
| **Entrées** | demande de la Direction du 27/10/2026 ; `PRD-FLUTTER-poste-fidelite-maquette` ; `ADR-0001/0003/0005` ; maquette `prototype_html/` (exécutable de référence) |
| **Compagnon** | [`guides/BIBLIOTHEQUE-DOCUMENTAIRE.md`](../guides/BIBLIOTHEQUE-DOCUMENTAIRE.md) — les 40 documents demandés, un par un |

## 1. Principe directeur

La demande décrit une **bibliothèque documentaire** (instructions maîtres, système de conception, spécifications module par module, standards, tests) à produire **avant** d'écrire le code, et que Claude Code consommera ensuite. Ce dépôt a déjà la matière première — la maquette et 70 vagues de décisions dans `CLAUDE.md`. Le plan **n'invente rien** : chaque document est *extrait* de la maquette ou *dérivé* d'une décision existante, et ce qui n'a aucune source est une **proposition marquée à valider**.

Ordre : **extraire → décider → spécifier → bâtir → recetter.** Jamais l'inverse.

## 2. Exigences non fonctionnelles — calibrées sur la clinique

Les chiffres de la demande (100 000 utilisateurs, 99,99 %) sont des chiffres de gabarit. **Proposition** à valider (Q4 d'ADR-0005) :

| Catégorie | Cible proposée | Source / mesure |
|---|---|---|
| **Performance** | liste 20 000 lignes < 1 s ; recherche patient < 300 ms ; API p95 < 500 ms ; ouverture d'écran < 2 s | banc ADR-0003 critère 5 |
| **Charge** | 15 postes + 5 téléphones + 5 sessions PWA en écriture continue ; sync p95 < 5 s | idem |
| **Sécurité** | SQLCipher au poste ; TLS ; hachage des mots de passe ; RBAC serveur **et** poste ; journal d'audit RG-12 ; révocation d'appareil ; **aucune donnée de santé en cache navigateur clair** ; secrets hors dépôt | RG-12/13, CLAUDE.md |
| **Disponibilité** | **le poste ne s'arrête jamais** (autonome) ; serveur : 99,5 % mensuel, reprise < 1 h, sauvegarde quotidienne + réplica hors site, restauration à blanc trimestrielle | ADR-0001 |
| **Maintenabilité** | un schéma source, une matrice RBAC source, des vecteurs de tests partagés ; couverture des vecteurs = 100 % des moteurs exposés | ADR-0005 |
| **Portabilité** | Windows 10/11, Linux ; Android (iOS si le parc le demande) ; PWA : Chrome/Edge/Safari récents | — |
| **Utilisabilité** | français ; typographie ≥ 11 pt ; états vide/chargement/erreur partout ; accessibilité clavier ; formats français (U+202F, U+00A0) | CLAUDE.md, vague 33 |

## 3. Phases

| Phase | Objet | Livrables (voir bibliothèque) | Porte de sortie |
|---|---|---|---|
| **P0 — Cadrage de la pile** | Trancher ADR-0005 ; répondre Q1–Q5 | ADR-0005 acceptée ou rejetée ; audit de `sigh_web/` | décision écrite de la Direction |
| **P1 — Extraction** | Sortir de la maquette tout ce qui se *lit* : manifeste, RBAC, dictionnaire, jetons de conception, vecteurs de tests, captures | `PARITE-MAQUETTE`, `ROLES_ET_PERMISSIONS`, `DICTIONNAIRE_DONNEES`, jetons de design, vecteurs JSON, captures de référence | vecteurs rejoués verts sur la maquette |
| **P2 — Spécification** | Rédiger les documents de la bibliothèque, groupe par groupe (§4) | groupes A → F | revue Direction par groupe |
| **P3 — Socle technique** | Laravel (auth, RBAC, audit, journal d'opérations, endpoint de sync), schéma unique, thème Flutter, thème Livewire/Vue | dépôts initialisés, CI, banc ADR-0005 | banc passé |
| **P4 — Tranche 1 : caisse + MECeF + impression** | Première tranche verticale **de bout en bout** : Flutter ↔ API ↔ panneau | PRD §P0-9 | recette caisse, revue d'ADR |
| **P5 → Pn — Tranches** | pharmacie → laboratoire → hospitalisation/maternité → comptabilité → RH/paie → administration | une recette par tranche | parité x / 306 |
| **P6 — PWA** | Profils distants : consultation, saisie ciblée, notifications | module PWA | audit sécurité cache |
| **P7 — Mise en service** | Clinique pilote, formation par rôle, bascule | guide d'exploitation, rollback | recette globale |

Pas de dates : elles dépendent de l'effectif Flutter/Dart/Laravel (non documenté) et du résultat du banc.

## 4. Groupes documentaires (l'ordre est la dépendance)

| Groupe | Contenu | Dépend de |
|---|---|---|
| **A. Fondations** | Instructions maîtres, glossaire, dictionnaire médical, structure de pages, ordre des sections | CLAUDE.md |
| **B. Produit** | BRS, PRD (exist.), SRS, FRS, NFRS (§2), règles de gestion, cartographie des modules, processus métier par page | A |
| **C. Architecture & données** | Architecture (ADR-0005), RBAC, dictionnaire de données, ERD, migrations, synchronisation bidirectionnelle | B |
| **D. Conception UI/UX** | Système de conception, mise en page, tableaux/filtres, modales et CRUD, responsive, notifications/toasts, impression PDF | B, extraction P1 |
| **E. Spécifications de modules** | M1…M14, MECeF, GED, RAP, PIL : écran par écran, onglet par onglet | B, C, D |
| **F. Standards, tests, revue** | Conventions Laravel/Livewire/Vue/Flutter, sécurité, tests, UAT, revue senior, sprints | C, D, E |

## 5. Bibliothèque de compétences (skills) — qui produit quoi

Compétences **du dépôt** (`.claude/skills/`) : `/prd`, `/adr`, `/spec`, `/plan`, `/test-plan`, `/review`, `/release`. Compétences de l'environnement utiles : `product-management:write-spec`, `engineering:architecture`, `engineering:system-design`, `engineering:testing-strategy`, `engineering:code-review`, `engineering:documentation`, `engineering:deploy-checklist`, `design:design-system`, `design:design-handoff`, `design:accessibility-review`, `design:ux-copy`, `sdlc-kit:*`.

| Besoin | Compétence | Écrit dans |
|---|---|---|
| Décision de pile | `/adr`, `engineering:architecture` | `docs/architecture/adr/` |
| Exigences d'un module | `/prd`, `product-management:write-spec` | `docs/prd/` |
| Spécification écran par écran | `/spec` | `docs/specs/` |
| Découpage en tranches et sprints | `/plan` | `docs/plans/` |
| Stratégie de test, UAT, jeux de données | `/test-plan`, `engineering:testing-strategy` | `docs/test-plans/` |
| Système de conception, jetons | `design:design-system`, `design:design-handoff` | `docs/design/` |
| Accessibilité | `design:accessibility-review` | `docs/design/` |
| Libellés médicaux, messages | `design:ux-copy` | `docs/design/` |
| Revue de code senior / QA architecte | `/review`, `engineering:code-review` | `docs/reviews/` |
| Livraison et retour arrière | `/release`, `engineering:deploy-checklist` | `docs/releases/` |

Les trois documents « instructions pour Claude Code » (Laravel/Livewire/Vue, Flutter, conversion Tailwind→Dart) sont des **skills du projet** à ajouter dans `.claude/skills/` une fois P2 validée : ils portent la méthode, pas l'état du projet.

## 6. Conversion Tailwind → Flutter

La maquette est en Tailwind compilé. Plutôt qu'un document de conversion à la main :

1. extraire les **jetons** (`tailwind.config.js`, `src/input.css` : couleurs navy/sémantique, rayons, ombres, espacements, Inter) vers **un seul fichier JSON de jetons** ;
2. en engendrer le `ThemeData` Flutter, les variables CSS Livewire/Vue, et la page de référence ;
3. interdire toute valeur en dur hors jetons (revue + lint).

C'est le seul moyen de tenir **trois interfaces** (Flutter, Livewire, Vue) à parité sans trois dérives.

## 7. Risques

| Risque | Mitigation |
|---|---|
| Règles métier en double PHP/Dart | option A d'ADR-0005 + vecteurs partagés en CI |
| Trois interfaces à tenir | jetons uniques ; Livewire limité au panneau ; PWA limitée aux profils distants |
| Documentation sans source (inventée) | chaque document cite sa source ; sinon « proposition à valider » |
| Dérive de fidélité | PRD Flutter, règle « pas de redesign » |
| Cache PWA et données de santé | audit de sécurité en P6, file d'envoi seule |
| `sigh_web/` hors contrôle de version | audit en P0 avant toute reprise |
