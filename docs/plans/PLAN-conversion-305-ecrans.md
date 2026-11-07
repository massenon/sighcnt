# Plan de conversion des 305 écrans PHP/JS → Dart (fidélité à la maquette)

> Décision du 30/10/2026 : **tous les écrans, tous les modules**, fidèlement identiques à la maquette, dans **une seule** application Flutter desktop. Les modules complémentaires de la mère sont dans [`MODULES-COMPLEMENTAIRES-MERE.md`](../architecture/MODULES-COMPLEMENTAIRES-MERE.md).

## 1. Ce qu'on convertit (mesuré, pas estimé)

| Mesure | Valeur |
|---|---|
| Pages PHP engendrées | **305** (306 entrées au manifeste, dont 20 hubs de module) |
| Code des écrans | 22 fichiers JS, **≈ 61 700 lignes** (`assets/js/modules/`) + noyau (`ui.js`, `app.js`, `parcours.js`, `store.js`, `print.js`…) |
| Écrans par tranche (hors hubs, `parite.json`) | T1 caisse/MECeF **17** · T2 pharmacie/achats **27** · T3 laboratoire/imagerie **24** · T4 parcours clinique M1–M4 **67** · T5 assurances/compta **31** · T6 RH, paie, administration, pilotage, configuration, tableaux de bord, rapports **120** |
| Impressions | ≈ 333 pièces imprimées (A4, rouleau 80 mm, badge CR80) |
| Scénarios de recette de la maquette | 74 (1 185 vérifications) + audit RBAC (846 sondages) |

## 2. Ce que « fidèlement identique » veut dire — et comment on le prouve

Une conversion JS → Dart **ne se fait pas par traduction automatique** : les écrans sont du JavaScript impératif (`U.dataTable`, `K.crud`, `render()`), pas des déclarations. Elle se fait par un **kit Dart** qui reproduit les composants de la maquette, puis **écran par écran**, avec une mesure automatique de parité. Trois niveaux, du plus strict au plus souple :

| Niveau | Mesure | Seuil de réception |
|---|---|---|
| **N1 — Contenu** | Texte visible de chaque écran (titres, libellés, en-têtes de colonnes, boutons, messages, motifs) extrait du DOM de la maquette à 1440 px **et** de l'arbre de sémantique Flutter ; comparaison exacte | **100 %** des textes présents, même ordre |
| **N2 — Structure** | Nombre et nature des blocs : KPI, onglets, colonnes, filtres, commandes (présentes / absentes selon le rôle), champs de formulaire (type, obligatoire, ordre, largeur 6 colonnes) | **100 %** |
| **N3 — Visuel** | Captures de la maquette (`build/shot.js`, 1440 et 400 px) comparées aux *golden tests* Flutter | écart toléré **≤ 2 %** de pixels, revu à l'œil sur chaque écran ; les polices et le rendu du texte diffèrent entre navigateur et Flutter : le pixel-perfect **n'est pas promis** |
| **N4 — Comportement** | Les 74 scénarios de la maquette rejoués sur l'application Dart (même séquence de gestes, mêmes vérifications) + l'audit RBAC | 74/74 et 0 promesse |

Les niveaux N1, N2 et N4 sont **automatisables** et font foi. N3 est un contrôle de proximité, pas une égalité.

## 3. Ordre de travail

### Étape 0 — Le kit (avant tout écran)
Composants Dart reproduisant `ui.js`/`_kit.js` : tableau (tri, filtres, pagination, colonnes, sélection, plage de dates, recherche), formulaire à **6 colonnes** (`U.form`), `combo`/`multiselect`, modale, tiroir, onglets avec ancre, KPI, graphiques (Chart.js → bibliothèque Flutter), toasts et annulation, ruban de navigation et méga-menu, fil d'Ariane, recherche globale, bandeau de lecture seule, gabarit de page standard, **impression** (A4, 80 mm, CR80, en-tête légal unique, pied normalisé, totaux calculés jamais fournis). Les droits viennent de `MatriceDroits`.

### Étape 1 — L'outillage de parité (avant la tranche 1)
1. Extracteur de **contenu et structure** par écran, côté maquette (extension de `build/extraire.js`) → `docs/architecture/ecrans/<id>.json` (engendré).
2. Extracteur équivalent côté Flutter (test d'intégration) → comparaison N1/N2 automatique, tableau de bord de parité (`PARITE-MAQUETTE.md` enrichi : % par écran).
3. Rejeu des scénarios de la maquette (N4) en pilotant l'application.

### Étape 2 — Tranches verticales (ordre du risque)
| Tranche | Écrans | Particularités |
|---|---|---|
| 1 | 17 | Caisse, MECeF, impression. Moteurs RG-09/RG-10 **déjà portés** (21 + 23 vecteurs). MECeF : protocole du boîtier inconnu → écrans et simulation, intégration physique **bloquée** |
| 2 | 27 | Pharmacie, stocks (FEFO, CUMP, RG-03), achats (RG-04) |
| 3 | 24 | Laboratoire (deux verrous de validation), imagerie à cinq modalités |
| 4 | 67 | Parcours clinique : patients/DMI, consultations, hospitalisation, maternité |
| 5 | 31 | Assurances (facture mère), comptabilité SYSCOHADA, états financiers |
| 6 | 120 | RH, paie, administration, pilotage, configuration, tableaux de bord par poste, rapports |

Chaque tranche se ferme quand **N1, N2 et N4 sont à 100 %** pour ses écrans et que N3 est revu.

### Étape 3 — Moteurs à état
`repartir` et `encaisser` sont portés. Restent à porter, **avec vecteurs extraits de la maquette** : avoir (`emettreAvoir`), exercice et clôture, BFR, valorisation CUMP/prix de vente, FEFO, paie (ITS, CNSS, ORTB), primes (grille datée), moteur de notifications. Aucune règle n'est portée sans vecteur.

### En parallèle — Modules complémentaires de la mère
Les 17 écrans à écrire (M-04 à M-22 hors faits), dans l'ordre : M-09 sauvegardes/restauration, M-10 clé de clinique, M-13 relais, M-15 service, M-20 assistant de mise en service, puis les autres.

## 4. Tâches

| # | Tâche | Sortie vérifiable |
|---|---|---|
| T9 | **Activation du mode mère à l'exécution** (plus de `--dart-define`) : réglage persistant, garde « une seule mère », démarrage du service dans le processus | tests ; refus nommé d'une 2ᵉ mère |
| T10 | **Kit Dart** (étape 0) | une page de démonstration par composant + tests de widgets |
| T11 | **Outillage de parité** (étape 1) | rapport N1/N2 par écran, engendré |
| T12–T17 | Tranches 1 à 6 | % de parité par écran, scénarios rejoués |
| T18 | Moteurs à état restants | vecteurs verts |
| T19 | Modules complémentaires de la mère (17) | un test de widgets + un test sur le service réel par module |
| T20 | Packaging (service Windows/Linux, SQLCipher, compilation native) | **hors de cet environnement** |

## 5. Ce que ce plan ne promet pas

- **Pixel-perfect** : non. Même contenu, même structure, même comportement, rendu proche — pas identique au pixel.
- **Délai** : la conversion est un programme de plusieurs mois pour une équipe, pas une tâche de session. Cette session peut produire le kit, l'outillage de parité et des tranches entières, **écran par écran, mesurés** ; elle ne peut pas annoncer « 305 écrans terminés ».
- **MECeF physique, builds natifs, SQLCipher, service Windows** : impossibles dans l'environnement de rédaction.
