# PRD-TARIFS : un référentiel de tarifs unique, un écran unique, et un changement de prix validé qui n'est jamais rétroactif

Statut : **proposé le 10/11/2026** ; décisions T1 à T15 de la Direction du 11/11/2026 appliquées ; **lots T0, T1 et T2 livrés en maquette le 11/11/2026, T3, T4 et T6 ensuite, T5 (les produits) en maquette le 12/11/2026 (écarts E2436 à E2447)** (plan : `docs/plans/PLAN-tarifs-referentiel-unique.md`, écarts E2361 à E2369) ; T3 à T7 restent à faire. Les sections 2 et 3 décrivent l'état D'AVANT les lots (les constats 1, 2 et 9 sont mesurés et le 9 est faux, voir 2.4) ; les sections 4 à 9 décrivent la cible, avec les écarts de mise en œuvre notés ci-dessous.
Sources : décisions de la Direction du 10/11/2026 (`docs/decisions/DECISIONS-A-VALIDER.md`, section F, lignes 88 à 93) ; `prototype_html/assets/js/data.js`, `data-tarifs.js`, `store.js`, `parcours.js`, `notifications.js`, `modules/configuration.js`, `modules/import.js`, `modules/m8-facturation.js`, `modules/m5-laboratoire.js`, `modules/m6-stock.js`, `modules/m10-rh.js`, `nav.js` ; `packages/rbac/data/rbac.json` ; `packages/domaine/lib/src/consultation/cs_moteur.dart`, `parametres/` ; `apps/poste/lib/` ; `docs/prd/PRD-IMP-bouton-importer-par-ecran.md`, `PRD-M13-validation-par-modale-et-fin-du-statut-a-valider.md` ; `docs/specs/SPEC-protocole-synchronisation.md` ; `docs/architecture/ECARTS-MAQUETTE.md`, `DICTIONNAIRE-DONNEES.md` ; `CLAUDE.md`.

Règle de lecture : chaque affirmation sur le code cite `fichier:ligne`. Ce qui n'a pas été vérifié est dit **non vérifié**. Une valeur, un seuil ou un libellé proposé sans source documentaire est une **proposition à valider**. Le code n'a été que **lu** : aucun banc, aucun serveur, aucune écriture hors de ce document. Les chiffres de la semence (69 actes, 147 lignes de grille, 48 analyses) ont été mesurés en chargeant `data.js` et `data-tarifs.js` hors navigateur ; les effectifs des collections viennent de `DICTIONNAIRE-DONNEES.md` (actes 73 fiches, catalogueTarifs 147, analyses 48, examensLabo 70, produits 184, valorisationsSage 34). Les lignes marquées (g) n'ont été trouvées que par recherche textuelle, sans ouvrir le contexte.

---

## 1. Problème et décisions de la Direction

### 1.1 Les trois décisions du 10/11/2026

1. **Une seule liste de prix.** La liste « actes », lue par la caisse, et le « Catalogue tarifaire (deux prix) » sont **fusionnées** en une liste que la caisse lit pour facturer. **Un seul écran** porte tous les prix (prestations, analyses, imagerie, et le cas des produits), pour éviter les doublons et le double travail. L'avis de l'assistant doit être dit (section 3).
2. **Un import de prix porte un champ de validation Oui/Non** (Oui : le nouveau prix s'applique ; Non : il ne s'applique pas). Et **quand le logiciel constate un changement de prix** (import ou saisie à l'écran), il crée une **alerte de validation Oui/Non** (circuit Direction et DAF).
3. **Le changement du prix d'un produit ou d'un acte n'influence jamais les anciennes facturations** : une pièce émise ne se réécrit pas ; le prix se **versionne par date d'effet**, comme la grille des primes (`D.NS132.montant(prime, fonction, date)`, `data.js:128` à `data.js:179`) et les plages par lot de réactif.

Réponses voisines déjà données : le poste du gestionnaire de stock est un **fileul** (réponse du 10/11, `DECISIONS-A-VALIDER.md` section E) ; un référentiel importé à un fileul passe par la **demande d'import vérifiée, appliquée par la mère** (`PRD-IMP`, 8.3). Question 3 des analyses : même principe, un prix unique lu par la facturation ; **le modèle de résultat (unités, bornes) reste séparé** (`DECISIONS-A-VALIDER.md:93`).

### 1.2 Pourquoi c'est un vrai défaut et pas une préférence d'écran

La règle d'or écrite dans l'écran lui-même est « une seule source de vérité tarifaire, les prix ne sont jamais dupliqués entre modules » (`modules/configuration.js:851` à `853`) et le cadrage parle d'un « TARIF MASTER » consommé par pharmacie, facturation, assurance et comptabilité (`CLAUDE.md`, correspondance document vers rôle). Le code actuel ne la tient pas : il y a **neuf emplacements qui portent un prix** (section 2.1), **deux (S4 et S6) que la caisse n'applique pas** (2.4), aucun historique de version, et une correction de prix qui s'écrit **en place** (2.4, constat 7). Les décisions du 10/11 ne demandent donc pas un ravalement : elles réparent la promesse déjà écrite.

---

## 2. État des lieux, mesuré

### 2.1 Les sources de prix

| N° | Source | Contenu | Où | Qui l'écrit | Qui la lit |
|---|---|---|---|---|---|
| S1 | `D.ACTES` (constante, 69 actes, 5 secteurs) | `[code, libellé, secteur, prix, source]` ; **sert de semence** | `data.js:1436` ; rapprochée d'une grille par `rapprocherActes()` (`data-tarifs.js:521` à `data-tarifs.js:568`) | personne (constante) | `store.seed` (S2), `genFactures` (`store.js:1046` à `1048`), import (`import.js:431` à `432`) |
| S2 | collection `actes` (73 fiches : 69 + 3 journées `HO01..03` + `GY-SAA`) | prix unique `prix`, plus `prixNonAssure`, `prixAssure`, `nonCouvert`, `assurable`, `codeTarif` pour les **28 actes rapprochés** d'une grille ; `tarifProvisoire`, `tarifArreteLe` | `store.js:1701` à `store.js:1745` | `cfg-tarifs` onglet « Actes & hospitalisation » (`configuration.js:1091` à `1300`), jeu d'import `actes` (`import.js:419` à `464`) | la facturation (S2 est **la** liste de la caisse : `parcours.js:87` à `93`, `m8-facturation.js:620`) |
| S3 | `D.CATALOGUE` (constante, **147 lignes** : 131 de grilles imprimées + 16 tarifs d'attente d'imagerie) | deux prix, trois états de la colonne assurée, `assurable` (`true`, `false`, `'sos'`), `variantesGrille`, `prixAValider` | `data-tarifs.js:381` à `388` ; familles `CONSULTATION 6`, `IMAGERIE 23`, `LABO 41`, `AMI 40`, `GYNECO 31`, `CERTIFICAT 6` (mesuré) | personne (constante) | **les lecteurs `D.tarif`, `D.tarifPrix`, `D.tarifParFamille`** (2.2) |
| S4 | collection `catalogueTarifs` (147 fiches) | copie de S3 ; mêmes champs | `store.js:1841` à `1843` | `cfg-catalogue` (`configuration.js:3956` à `4125`) | **aucun lecteur dans la maquette** hors son écran (recherche : `store.js:1841`, `3878`, `4268`, `configuration.js:3957`, `vecteurs-cfg.js`, `test-fonctionnel.js:4374`) ; **le poste Flutter la lit** (2.2) |
| S5 | `D.ANALYSES` (constante, 48 analyses) | `[code, catégorie, prix, échantillon, délai]` ; une **seule colonne de prix** | `data.js:624` | personne (constante) | `analyseParCode` (`parcours.js:83` à `86`), caisse manuelle (`m8-facturation.js:629`), consultation (`m2-consultations.js:2307`, `3155`), hospitalisation (`m3-hospitalisation.js:535`) : **22 occurrences dans 11 fichiers** (grep) |
| S6 | collection `analyses` (48 fiches) | copie de S5 (`tarifProvisoire`, `aValider`) | `store.js:1694` | `cfg-tarifs` onglet « Analyses » (`configuration.js:913` à `996`), `m5-catalogue` (`m5-laboratoire.js:1193` à `1290`) | `m5-laboratoire.js:34` à `37` (avec repli sur S5) ; **pas la facturation** (2.4, constat 2) |
| S7 | collection `examensLabo` (70 fiches) | le **modèle de résultat** (sections, variables, unités, bornes) ; **aucun prix** | `data-labo.js` ; jeu d'import `analyses` (`import.js:469` à `506`) | `m5-valeurs-reference`, import | saisie des résultats |
| S8 | `examensImagerie` (24 fiches) | **aucun prix** ; porte `tarifCode` qui renvoie à S3 | `data-imagerie.js:130` et `135` ; `parcours.js:863` à `870` | `cfg-imagerie-catalogue` | demande d'imagerie (`D.tarifPrix(ex.tarifCode)`) |
| S9 | collection `produits` (184 fiches) | `prixAchat`, `prixVente`, `cump`, `valorisationProvisoire` ; RG-02 : prix de vente = prix d'achat pour un médicament | `store.js:733` à `748` ; `m6-stock.js:415`, `435` | `m6-produits` (`m6-stock.js:415` à `475`), `cfg-tarifs` onglet « Produits » (`configuration.js:884` à `940`), import Grand Stock (`import.js:124` à `242`) | `prescrire` (`prixAchat`, `parcours.js:127`), caisse manuelle (`prixVente`, `m8-facturation.js:632`), panier de la pharmacie (`m6-stock.js:2473`), valorisation du stock (`store.js:210` à `229`) |
| S10 | `valorisationsSage` (34 fiches) | surcouche tracée des 34 références SAGE non valorisées (médiane de catégorie) | `store.js:1668` | `m6-produits` (`m6-stock.js:373`) | valorisation |
| S11 | `D.TYPES_CHAMBRE` (constante, 3 types : 5 000, 15 000, 25 000) | prix de la journée d'hospitalisation ; **recopié** dans S2 (`HO01..03`, `store.js:1714` à `1727`) | `data.js:1017` à `1021` | personne | `m3-hospitalisation.js:53`, `687`, `732`, `913`, `934`, caisse manuelle (`m8-facturation.js:634`), `dashboards.js:4488` : **12 occurrences dans 5 fichiers** |

Voisines qui **ne portent pas de prix** et que la fusion ne doit pas absorber : `naturesFacture` (14 fiches : libellé, code, secteur, source, `configuration.js:1296` à `1306`) ; `souscripteurs` et `garanties` (taux, plafonds, exclusions : `parcours.js:1972` à `1982`, `2155` à `2224`) ; `INVENTAIRE_SAGE` (source de la reprise de stock, `store.js:700` à `748`) ; `typesPiece` (14 fiches) qui ne porte que `tarifCode` (`store.js:1869` à `1893`) et renvoie à S3.

**Trois copies figées de prix**, qui sont la raison pour laquelle l'histoire d'une pièce est déjà protégée dans l'essentiel : la ligne de facture (`prixUnitaire`, `montantBrut`, `montant`, `parcours.js:1096` à `1146`), la ligne de prescription de soins (`prix`, `parcours.js:2447` à `2468`) et la demande d'analyse (`prix`, `m5-laboratoire.js:66`, `288`).

**Bilan : 9 emplacements portent un prix (S1 à S6, S9, S10, S11 ; S3 compté une fois), 2 renvoient à un prix par `tarifCode` (S8, `typesPiece`), 3 voisines n'en portent pas, 3 copies figées.**

### 2.2 Les lecteurs

#### Maquette (24 lecteurs fonctionnels)

| N° | Lecteur | Ce qu'il lit | Source |
|---|---|---|---|
| R1 | `PR.prescrire` | médicaments : `prixAchat` (S9) ; analyses : S5 via `analyseParCode` ; actes : S2 via `acteParCode`, avec la colonne **assurée** (`a.prixAssure`) quand la carte est valide (C3) | `parcours.js:117` à `156`, `83` à `93` |
| R2 | ouverture de demande externe (analyses) | S5, une colonne | `parcours.js:732` à `736` |
| R3 | `creerDemandesImagerie` | S3 par `D.tarifPrix((ex.tarifCode) \|\| code, assure)` | `parcours.js:863` à `870` |
| R4 | `prescrireSoins` | S3 par `D.tarif` et `D.tarifPrix` | `parcours.js:2437` à `2468` |
| R5 | certificats et pièces | S3 via `D.tarif(x.tarifCode \|\| x.code)` puis `PR.facturerPiece` (`parcours.js:1194`) | `m1-patients.js:2203`, `2563` ; `data-seed.js:1076`, `2463` ; `configuration.js:4220` à `4292` |
| R6 | `construireLignes` | **copie** le prix dans la ligne | `parcours.js:1096` à `1146` |
| R7 | `PR.repartir` et `categoriser` | le **montant** de la ligne (pas le prix) ; les garanties du souscripteur ; l'**appariement par libellé** avec les exclusions ; le **secteur** de l'acte par `acteParCode` | `parcours.js:2155` à `2224`, `2238` à `2243` |
| R8 | caisse manuelle | S2 (`620`), S5 (`629`), `prixVente` S9 (`632`), S11 (`634`) | `m8-facturation.js:620` à `634`, `794` |
| R9 | consultation, estimation du total | S5, S2, S3 (`D.tarifParFamille('AMI')`) | `m2-consultations.js:51`, `56`, `2307`, `2313`, `3090`, `3155`, `3159`, `3464`, `4988` |
| R10 | hospitalisation, observation, bloc | S5, S2, S3 (GYNECO), S11 | `m3-hospitalisation.js:535`, `542`, `3545`, `3553`, `3672`, `1927`, `53`, `687`, `732`, `913`, `934` |
| R11 | laboratoire | S6 avec repli sur S5 ; copie le prix dans la demande | `m5-laboratoire.js:34` à `37`, `66`, `288` |
| R12 | recherche globale | S2, S5 | `app.js:734` à `736`, `747` |
| R13 | secteur d'une ligne, groupes de prestation | `secteur` de S2 par `acteCode` | `data.js:2196` à `2223` ; `dashboards.js:2682` ; point des ventes |
| R14 | stock et pharmacie | `prixVente` du panier ; valorisation au CUMP ; édition produit | `m6-stock.js:2473`, `415` à `435` ; `m12-comptabilite.js:5956` ; `store.js:210` à `229` |
| R15 | **assurance du personnel** | le montant PORTÉ par la demande ; S5 ne sert qu'à nommer l'examen (**constat soldé par la vague 109, mesuré au lot T0**) | `m10-rh.js:4799` à `4807` |
| R16 | M9 (relevés, factures mensuelles, mère) | le **montant des lignes** de facture (pas le catalogue) ; la liste des **libellés d'actes** pour les exclusions | `m9-assurances.js:1278`, `1677`, `945` |
| R17 | MECeF | les lignes de la pièce (`prixUnitaire`), jamais le catalogue | `mecef.js:311` à `329` |
| R18 | impressions de grille | S2, S6 | `configuration.js:1260` à `1290` ; `m5-laboratoire.js:1276` à `1282` |
| R19 | amorçage du jeu de démonstration | S5, S1 | `store.js:1046` à `1048` |
| R20 | jeux d'import | écrivent S2 et S7, jamais S4 ni S6 | `import.js:414` à `506` |
| R21 | seed GY-SAA | S3 (`AMIU`) | `store.js:1731` |
| R22 | affichages de catalogue (compteurs, classements) | S5 (g) | `dashboards.js:408`, `1039`, `1105`, `1126` ; `rapports.js:297` |
| R23 | avoirs | les lignes de la facture d'origine (CLAUDE.md, vague 42 ; **non relu ici**) | `SIGH.emettreAvoir` |
| R24 | point des ventes, statistiques | les lignes émises et le secteur (R13) | `m6-stock.js` (g) |

#### Poste Flutter et domaine (8 lecteurs fonctionnels)

| N° | Lecteur | Ce qu'il lit | Source |
|---|---|---|---|
| P1 | moteur de prescription du domaine | `csTarifPrix` lit **`catalogueTarifs`** (S4) ; les actes lisent `actes` ; les analyses lisent un référentiel **statique** | `cs_moteur.dart:32` à `34`, `504` à `520`, `692` à `712` |
| P2 | demandes d'imagerie | `catalogueTarifs` puis `actes` rapprochés | `m2/img_commun.dart:50` à `66` |
| P3 | prescriptions, ordonnances, fiche | `catalogueTarifs` (AMI), `actes` | `m2/cs_prescriptions.dart:53` ; `cs_ordonnances.dart:482` ; `cs_commun.dart:127` |
| P4 | bloc, pansements, observation | `actes`, `catalogueTarifs` | `m3/bloc_pansements.dart:39` ; `bloc_cro.dart:141` ; `hos_observation.dart:383` |
| P5 | pièces certifiantes, patient externe | `catalogueTarifs` | `m1/pieces.dart:27` ; `externe.dart` |
| P6 | caisse manuelle | `actes` (analyses et produits : non relus) | `m8/facturation.dart:226` |
| P7 | points des ventes, coût d'activité, pilotage | `actes` pour le secteur | `m6/points_ventes.dart:154` ; `m12/cpc_cout_activite.dart:80` ; `pil/pil_gestion.dart:159` |
| P8 | écrans de configuration, recherche, états | les deux collections | `cfg/cfa_tarifs.dart:31` à `32` ; `cfa_catalogue.dart` ; `cfa_pieces.dart` ; `shell/recherche_globale.dart` ; `rap/rap_generateur.dart` ; `m5/cat_commun.dart` |

Aucun lecteur de prix dans `apps/mobile/lib` (recherche de `tarif`, `catalogueTarifs`, `prixAssure` : zéro résultat). Le relais `apps/web` ne porte pas non plus de tarif (recherche vide) : il est opaque. **Total recensé : 32 lecteurs fonctionnels (24 maquette, 8 poste et domaine), 22 fichiers JS de la maquette et 21 fichiers Dart.**

### 2.3 Les écrans qui éditent un prix

| Écran | Édite | Droits actuels (`rbac.json`, voir / éditer / annuler) | Remarque |
|---|---|---|---|
| `cfg-tarifs` | S9 (produits), S6 (analyses), S2 (actes, hospitalisation) en **trois onglets** | admin 111, da 111, direction 110, reception 100 | alias dans ACCUEIL (`nav.js:148`) ; rubriques de recherche `nav.js:1625` à `1629` |
| `cfg-catalogue` | S4 | admin 111, da 111, direction 110, reception 100 | alias dans ACCUEIL (`nav.js:149`) ; **n'alimente aucune facture de la maquette** |
| `m5-catalogue` | S6, **y compris le prix** | admin 111, laborantin 111, dm 110, direction 100 | le biologiste modifie un prix |
| `cfg-imagerie-catalogue` | S8 (aucun prix) | admin 111, da 111, direction 110, dm 100 | porte le `tarifCode` |
| `m6-produits` | S9, S10 | admin 111, da 111, **stock 111**, **caissier 111**, comptable 100, direction 100, medecin 100 | **le caissier et le gestionnaire de stock modifient des prix de produits** |
| `m6-import-grand-stock` | S9 (prix de revient) | stock, da, admin, direction | `import.js:124` à `242` |
| `imp-actes`, `imp-analyses` | S2 ; S7 | da, admin, direction ; laborantin, da, admin | `nav.js:702`, `703` ; la liste `roles` d'un jeu est **décorative**, seul `N.can` sur l'écran joue (`PRD-IMP` 2.2) |

Le poste Flutter porte les mêmes écrans, tous marqués « porté » à N1 = 100 % (`docs/architecture/parite-statuts.json:201`, `202`, `208`, `64`, `32`, `353`, `354`, `360`).

### 2.4 Constats (ce que le code fait réellement)

1. **`catalogueTarifs` n'est lue par aucune facture dans la maquette.** `D.tarif`, `D.tarifPrix` et `D.tarifParFamille` lisent la **constante** `D.CATALOGUE` (`D.CATALOGUE` à `data-tarifs.js:585`, `D.tarif = parEntree` à `data-tarifs.js:587`), jamais la collection. Modifier un prix à `cfg-catalogue` change S4 et **rien d'autre** pour l'imagerie, les soins (AMI), la gynécologie, les certificats. **MESURÉ le 11/11/2026** (lot T0, scénario « Vague 113 ») : un prix d'imagerie modifié AU GESTE à `cfg-catalogue` (9 000 vers 9 100) entre dans la collection, et la demande d'imagerie reste à 9 000 ; même épreuve sur le soin `SIV` (collection modifiée, `D.tarifPrix` et ligne de prescription de soins inchangés). Lecture statique des sources : seul `configuration.js` ouvre `collection('catalogueTarifs')` ; `store.js` ne fait que la semer et la nommer à la corbeille.
2. **Même défaut pour les analyses.** `cfg-tarifs` et `m5-catalogue` écrivent la collection `analyses` (S6) ; la facturation lit la constante `D.ANALYSES` (`parcours.js:83` à `86`, `m8-facturation.js:629`, `m2-consultations.js:2307`). Le commentaire de `m5-laboratoire.js:33` à `34` dit « lire la constante, c'était ignorer un tarif corrigé » : le laboratoire a été réparé, pas la caisse. **MESURÉ le 11/11/2026** (lot T0) : `L01` modifié dans la collection `analyses` (2 000 vers 2 100) reste à 2 000 sur la ligne d'ordonnance et la ligne de facture de `PR.prescrire`, et la liste « Analyse de laboratoire » de la caisse manuelle montre toujours AKOP à 2 000 (73 actes, 48 analyses, 3 journées listés) ; la liste des actes, elle, suit la collection `actes` (MG01 modifié, vu à 5 100).
3. **Deux espaces de codes pour la même prestation.** L'acte `SO02` (S2) est rapproché de la ligne de grille `SIV` (S3) par `codeTarif` (`data-tarifs.js:491` à `502`, `560` à `566`). Les lignes de facture portent tantôt le code d'acte (`prescrire`, `parcours.js:150`), tantôt le code de grille (`prescrireSoins`, `parcours.js:2458`). `secteurDeLigne` ne retrouve le secteur que par le code d'acte (`data.js:2196` à `2204`) : une ligne facturée sous un code de grille n'a pas de secteur et retombe sur la catégorie.
4. **Deux libellés pour la même prestation, et un contrat sur le libellé.** `PR.repartir` apparie les exclusions de convention **par libellé** (`parcours.js:2183`, `m9-assurances.js:945` liste les libellés d'actes). Le libellé de S2 (« Soins intraveineux (SIV) ») n'est pas celui de S3 (« Soin, injection intraveineuse »). Choisir le mauvais en fusionnant change la couverture d'un assuré sans le dire.
5. **Une correction de prix s'écrit en place, sans version.** `K.actionsLigne` met la fiche à jour (`configuration.js:1240`, `996`) ; la valeur ancienne n'existe que dans le journal d'audit, **tronquée à 100 caractères et plafonnée à 400 entrées** (`store.js:3987` à `4010`). Il n'existe **aucun historique de prix** pour les actes, analyses et produits, contrairement aux primes (`historiquePrimes`, `data.js:143`, `169`, `195`).
6. **La validation actuelle valide un marquage, pas un changement.** Les familles `actes` et `analyses` de `FAMILLES_A_VALIDER` (`parcours.js:4316` à `4319`) lèvent le marquage « tarif d'attente » ; elles ne comparent aucun ancien prix à un nouveau, ne portent aucune date d'effet, et le « Non » n'existe pas. Un `PR.validerReferentiel` refuse déjà sur un fileul (`refusFileulValidation`, `parcours.js:4395` et suivantes).
7. **Hospitalisation : une promesse non tenue.** `m3-hospitalisation.js` dit que les tarifs par catégorie « se modifient dans Référentiel tarifaire » ; `D.TYPES_CHAMBRE` n'est référencé nulle part dans `configuration.js` (recherche vide). Les fiches `HO01..03` de S2 sont une copie que la caisse lit, pendant que l'écran des lits lit la constante : deux prix de journée possibles.
8. **Produits : deux champs, un seul est contrôlé.** `prescrire` facture `prixAchat` (`parcours.js:127`), la caisse manuelle `prixVente` (`m8-facturation.js:632`). RG-02 les aligne à la **création** (`m6-stock.js:435`) mais la modification depuis `cfg-tarifs` « ne contrôle pas RG-02 » (`ECARTS-MAQUETTE.md`, E846). Le caissier et le gestionnaire de stock détiennent l'édition (`rbac.json`).
9. **~~Une relecture rétroactive existe déjà~~ : CONSTAT FAUX, CORRIGÉ le 11/11/2026 (lot T0).** Le PRD décrivait une lecture du prix courant par l'assurance du personnel. Elle a été soldée avant lui, par la vague 109 (lot L7, `ECARTS-MAQUETTE.md`) : `m10-rh.js` lit le montant PORTÉ par la demande (`a.montant`, sinon `a.prix`) et une demande ancienne sans montant est « non renseignée » ; `D.ANALYSES` n'y sert plus qu'à nommer l'examen. Mesuré : la sonde du lot T0 lit la source, et le scénario de la vague 109 le sonde au geste. **Mesuré aussi : une facture émise ne bouge pas quand le prix de l'acte change** (lignes copiées, total identique). Aucune relecture rétroactive n'est donc à corriger ; la décision 3 garde son sens (preuve, résolution à la date, mémoire) mais le point (d) de 2.5 est sans objet.
10. **Le poste ne se comporte pas comme la maquette.** Le poste lit `catalogueTarifs` (P1, P2, P3), donc une édition y serait **appliquée** aux imageries et soins, là où la maquette l'ignore. Les vecteurs sont tirés de la maquette ; la divergence est latente tant que personne n'édite. À consigner comme écart (E2337 et suivants) et à lever par la fusion.
11. **L'import de prix refuse ou écrit la mauvaise collection.** Le jeu `actes` refuse tout doublon (`import.js:782` à `789`) et écrit S2 ; le jeu `analyses` écrit `examensLabo` (S7), pas les prix (`import.js:494`). Il n'existe aucun jeu pour S4 (`PRD-IMP` 2.2, points 2 et 3).
12. **Un prix peut être 0 ou absent sans que le moteur le dise.** La doctrine existe côté données (tiret = valeur manquante, jamais un zéro ; arbitrage du 01/09 « plus aucun montant nul », CLAUDE.md vague 48) ; le jeu d'import la porte pour `actes` (`import.js:88` à `97`, `446` à `458`). La saisie à l'écran de S2 laisse un prix vide devenir `null` (`configuration.js:1247`) et celle de S6 impose `required` sans plancher.

### 2.5 Ce que la non rétroactivité garantit déjà, et ce qu'elle ne garantit pas

* **Garantie structurelle, déjà là** : une pièce émise porte des lignes qui **copient** le prix (R6). Changer S2 ou S3 ne modifie aucune ligne existante, payée ou non. MECeF (R17), M9 (R16), les avoirs (R23) et les statistiques (R24) lisent les lignes, pas le catalogue.
* **Ce que la décision 3 ajoute** : (a) la **preuve**, par une sonde au geste, qu'aucun lecteur ne relit le catalogue sur une pièce émise ; (b) la **résolution à la date** : le prix d'une pièce créée à la date D est celui qui était en vigueur à D, y compris pour une pièce saisie après coup avec une date passée ; (c) la **mémoire** : savoir quel prix s'appliquait le 3 mars, ce que ni S2 ni S6 ne savent aujourd'hui ; (d) ~~la correction de R15~~ (sans objet : déjà soldé par la vague 109, mesuré au lot T0).
* **Ce qui n'est pas couvert** et qu'il faut trancher (section 5.5) : les lignes **impayées** d'une pièce ouverte, les pro-forma, les prescriptions pas encore encaissées.

---

## 3. Avis honnête sur la fusion

### 3.1 Ce que la fusion apporte

* **Elle supprime une liste que personne ne lit** (S4, constat 1) et l'écart analyses (S5 et S6, constat 2) : le double travail dont parle la Direction est réel, et il est **pire** que du double travail, puisqu'une des deux saisies n'a aucun effet.
* **Une seule règle de résolution** (carte valide à la date, trois états de la colonne assurée, `NON COUVERT`, `sos`) au lieu de trois chemins (`acteParCode`, `analyseParCode`, `D.tarifPrix`).
* **Un seul endroit où se brancher** pour la version datée, l'alerte et l'import. Sans la fusion, il faudrait écrire trois fois le circuit de la décision 3.
* **Un seul code et un seul libellé de facturation** par prestation, donc une couverture d'assurance qui ne dépend plus de la voie de saisie.

### 3.2 Ce que la fusion risque

| Risque | Où | Ampleur |
|---|---|---|
| **Régression de la facturation** : deux espaces de codes (constat 3), 32 lecteurs, 5 voies de tarification (prescription, soins, imagerie, caisse manuelle, certificats) | R1 à R10, P1 à P8 | **haute** : c'est la caisse |
| **Couverture d'assurance modifiée sans bruit** : l'appariement par libellé des exclusions (constat 4) | R7, R16 | **haute** pour le M9, invisible à `npm run check` |
| **Secteur perdu** : si la prestation fusionnée n'emporte pas le `secteur` de S2 en plus de la `famille` de S3, les groupes de prestation, le point des ventes et la maternité comme secteur (CLAUDE.md, vague 55) se faussent | R13, R24, P7 | moyenne à haute |
| **Montants non entiers** : le MECeF exige des montants entiers (`PRD-MECEF`) ; la grille n'en a que des entiers (mesuré), la migration doit le garder | R17 | faible si contrôlé à l'écriture |
| **États imprimés** : la grille tarifaire imprimée et ses totaux, la parité N1 des libellés (les libellés de `cfg-tarifs` et `cfg-catalogue` sont comparés) | R18, `parite-statuts.json` | moyenne |
| **Vecteurs et poste** : `vecteurs-cfg.js`, `vecteurs-consultation.js`, `vecteurs-img-demandes.js`, `gen-poste-jeu.js:14` à régénérer ; 21 fichiers Dart | 2.2 | moyenne, mécanique |
| **Quota du magasin** : 147 + 73 fiches deviennent des identités plus des versions ; le magasin persisté tient à environ 330 Ko de marge (CLAUDE.md, vague 64) | `store.js` | à **mesurer avant de semer** (non vérifié) |
| **Un prix d'analyse change le premier jour** : 39 analyses se rapprochent d'une ligne de grille par libellé normalisé, **seules 11 portent un prix égal à l'une des deux colonnes de la grille**, 28 ne sont égales à aucune des deux, 9 n'ont aucune correspondance et 2 lignes de grille LABO n'ont pas d'analyse (mesuré au lot T0) | S5 contre S3 | **haute** si migré sans décision |

### 3.3 Ce que la fusion ne doit pas absorber

* **Le modèle de résultat des analyses** (`examensLabo`, `variablesLabo`, `unitesLabo`, `plagesReactif`) et **les variables d'imagerie** (`variablesImagerie`) : ce sont des modèles, pas des prix. Ils gardent leurs écrans (`m5-valeurs-reference`, `cfg-imagerie-catalogue`) et leur validation par un professionnel nommé (`FAMILLES_A_VALIDER`, `parcours.js:4300` à `4313`).
* **Les garanties et les conventions des assureurs** (taux, plafonds, exclusions, accords préalables) : ce sont des règles de prise en charge qui s'appliquent **à** un prix, pas un prix. Elles ne sont d'ailleurs pas datées (`garantiesDe` lit la grille du souscripteur de la date, mais les taux eux-mêmes n'ont pas de version : `parcours.js:1972` à `1982`). Même logique, autre chantier (Q13).
* **La valorisation du stock et le CUMP** (`store.js:181` à `229`) : un coût, pas un tarif de vente.
* **Les natures de facture**, qui ne portent pas de prix.
* **La nomenclature physique des chambres** (lits, ailes, `D.CHAMBRES`) : seule la **journée facturée** rejoint le référentiel de prix.
* **Les primes (NS 132) et les barèmes de paie** : autre grille datée, autre circuit, autre propriétaire (M10, M11).

### 3.4 Comment la faire sans casser la caisse

Trois temps, dans cet ordre, **jamais l'inverse** :

1. **L'adaptateur de lecture d'abord.** Le nouveau référentiel est semé à l'identique et chaque lecteur actuel continue de recevoir exactement ce qu'il recevait (une projection de lecture, section 4.6). Un scénario compare, pour **chaque code** (147 + 73 + 48), le prix avant et après sur les cinq voies de tarification. Aucun écran ne change.
2. **L'écran unique ensuite.** Les trois écrans d'édition deviennent un seul, qui écrit **uniquement** dans le nouveau référentiel. Les anciennes collections ne s'éditent plus.
3. **Le retrait des anciennes listes en dernier**, après que les 32 lecteurs sont passés à l'accesseur daté et qu'une garde de génération (comme celle de `gen-pages`) refuse la réapparition d'une lecture directe de S2, S4 ou S6 pour un prix.

Mon avis : **faire la fusion, mais pas en un seul lot**. L'écran unique est la partie facile ; le risque est dans les deux espaces de codes, l'appariement par libellé du M9 et le secteur. La Direction décide l'écran, les sondes décident le reste.

---

## 4. Modèle cible

### 4.1 Deux collections, pas une

* **`tarifs` : l'identité d'une prestation tarifée**, qui change peu. `code` (unique, **non modifiable** comme RG-01), `famille` (les six de `D.FAMILLES_TARIF` plus `ACTE`, `HOSPITALISATION`, `PRODUIT` : proposition), `libelle` (le libellé **de facturation**, celui des exclusions de convention), `libelleGrille` (le libellé imprimé de la grille, conservé), `secteur` (un des six secteurs arrêtés, `D.secteurNormalise`), `codesAlias` (liste : ancien code d'acte, `codeTarif` de la grille, code d'analyse `L01`), `assurable` (`true`, `false`, `'sos'`), `variantesGrille`, `source`, `statut` (actif, archivé : RG-14).
* **`versionsTarif` : une ligne par version de prix**, **immuable pour ce qui est du prix** (principe de `parametres`, `packages/domaine/lib/src/parametres/parametres.dart:1` à `12` : une version est une fiche immuable, une correction ajoute une version). Champs : `id = code@dateEffet@version` ; `code` ; `version` (entier croissant par code) ; `dateEffet` (jour AAAA-MM-JJ, `null` = « depuis toujours », réservé à la migration) ; `prixNonAssure` (entier ou `null`) ; `etatNonAssure` (`montant` ou `manquant`) ; `prixAssure` (entier ou `null`) ; `etatAssure` (`montant`, `nc`, `manquant`) ; `assurable` ; `motif` ; `source` ; `origine` (`ecran`, `import`, `migration`, `semence`) ; `lot` (référence `IMP-AAAA-NNN` si import) ; `proposePar`, `proposeLe` ; `statut` (`propose`, `valide`, `refuse`, `retire`) ; `decidePar`, `decideLe`, `motifDecision`, `roleDecision`.

Pourquoi deux et pas une : les primes ont `grillePrimes` (le courant) et `historiquePrimes` (les versions) ; `parametres` n'a que des versions. Ici l'identité porte des champs mutables qui ne se versionnent pas par date (libellé, secteur, archivage), et les **mêler** aux versions obligerait à les recopier sur chaque version, exactement ce que les badges ont évité (CLAUDE.md, vague 54).

**Écarts de mise en œuvre (lot T1, E2362 à E2364).** (1) Le code d'une prestation est canonique (acte, sinon analyse, sinon grille) et la fiche porte `codeActe`, `codeGrille`, `codeAnalyse` : chaque lecteur historique garde son espace de codes ; `codesAlias` sert l'accesseur nouveau. (2) `etatAssure` a un QUATRIÈME état, `unique` (prix unique, la colonne assurée vaut la colonne non assurée) : les actes sans grille, les journées et les analyses n'ont jamais eu de prix assuré distinct. (3) `etatNonAssure` n'est écrit que quand il vaut `manquant` (quota). (4) Une proposition issue de la grille imprimée n'a pas de date d'effet : `aDater: true`, la décision la fixe (seule mutation permise d'une version, avec le statut). (5) `source` et `secteur` ne sont portés que quand ils existent (les 73 actes pour le secteur). (6) Les motifs des deux états `NON COUVERT` et `SOS` sont repris MOT POUR MOT de l'ancien `prix()`.

**`en vigueur` n'est jamais stocké.** C'est un état **calculé** (`valide`, `dateEffet` ≤ date, plus grande `(dateEffet, version)`) : un poste hors ligne n'a pas de tâche de minuit, et une bascule stockée serait fausse dès que l'horloge passe la date d'effet sans que personne ouvre le logiciel. Les états affichés sont `en vigueur`, `à venir`, `remplacée`, `en attente`, `refusée`, `retirée`.

### 4.2 Les trois états de la colonne assurée, conservés

Le modèle actuel les porte par trois indices : `prixAssure` (montant), `nonCouvert` (booléen) et `prixAssure === null` avec `assurable !== false` (tiret). Le nouveau modèle les **nomme** (`etatAssure`) pour supprimer l'ambiguïté, mais la **projection de lecture** (4.6) recompose les anciens champs : un lecteur existant ne voit aucune différence. La doctrine du tiret est conservée telle quelle : une valeur manquante n'est ni un zéro ni une exclusion, la ligne ne se facture pas.

### 4.3 La règle de résolution

`PR.tarifALaDate(code, date, assure)` :

1. retrouver la prestation par `code`, puis par `codesAlias` ;
2. parmi ses versions `valide` dont `dateEffet` ≤ `jourDe(date)` (ou `null`), retenir celle de plus grande `(dateEffet, version)` ;
3. choisir la colonne : `assure` vrai **et** `assurable` non `false` **et** `etatAssure` = `montant` → `prixAssure` ; `assurable === 'sos'` → prix non assuré avec la réserve SOS ; `nc` ou `assurable === false` → prix non assuré avec le motif « non couvert » ; sinon prix non assuré (RG-09, `data-tarifs.js:398` à `421`) ;
4. un état `manquant`, ou aucune version valide, rend **« absent »** avec un motif : la ligne ne se facture pas et le refus est nommé, jamais un zéro ;
5. une version `propose`, `refuse` ou `retire` **n'est jamais lue**.

La **date** est celle de la **pièce ou de la ligne** (`v.date` de `prescrire`, date d'émission de la facture), jamais l'horloge au moment du calcul, et se compare au **jour** (leçon E4, `parcours.js:2114` à `2116`). C'est la même date que celle de `carteValide(patient, date)` : la colonne et la version se choisissent à la même date.

### 4.4 Contrôle d'usage : `tarif_deja_utilise`

Transposition de `parametre_deja_utilise` (`ECARTS-MAQUETTE.md`, E2308 ; `ServiceParametres`, `service.dart:93`). Une version ne peut pas prendre effet à une date **à laquelle ou après laquelle** une pièce non archivée porte une ligne de ce code, sinon la réponse à « quel prix s'appliquait à la date D » changerait après coup alors que la ligne dit autre chose. Refus nommé : code `TARIF_DEJA_UTILISE`, motif (« la facture FN-2026-00042 du 03/11/2026 porte déjà cette prestation »), geste (« choisir une date d'effet postérieure, ou émettre un avoir pour corriger la pièce »). Le contrôle se lit **sur les lignes** (`acteCode`, `produitId`, `demandeId`), sans collection d'usages : la maquette n'a qu'un poste de vérité. Au poste, un fileul hors ligne peut avoir émis une pièce que la mère ne voit pas encore : la mère **refait** le contrôle à la réception (comme pour les paramètres) et, si une pièce arrive après coup avec un prix différent de celui de sa date, la **marque** `tarifEnEcart` (marqueur déduit localement, jamais réécrit : famille des marqueurs de `pont_activite.dart`, `marqueursLocaux`).

### 4.5 Migration des données semées (rien n'est inventé)

Règle générale : **la migration ne change aucun prix facturé aujourd'hui**. Chaque prix **effectivement lu par la caisse** devient la version 1 `valide`, `dateEffet: null`, `origine: 'migration'`. Tout prix **documenté** qui diffère arrive en **version proposée**, soumise à la Direction.

| Cas | Population | Règle |
|---|---|---|
| A | 28 actes rapprochés d'une grille (`codeTarif`) | une prestation ; `code` = code d'acte, `codesAlias` = code de grille ; libellé de facturation = libellé de S2 (exclusions M9) ; prix = valeur actuelle de S2 ; un écart avec la grille (édité depuis) est **listé**, pas corrigé |
| B | 45 actes sans grille (41 + 3 journées + `GY-SAA`) | une prestation chacun ; prix de S2 ; `etatAssure` d'après les champs présents (`GY-SAA` porte son assuré aligné sur l'AMIU) ; marquages `tarifProvisoire` et `tarifArreteLe` **conservés** dans la source et le motif |
| C | 119 lignes de grille sans acte | une prestation chacune, prix de la grille tel que lu aujourd'hui par `D.tarifPrix` (donc S3, pas S4 : c'est S3 que la caisse lit) ; si S4 a été édité, l'écart est listé |
| D | 41 lignes `LABO` et 48 analyses | rapprochement par **libellé normalisé** (la fonction de `data-tarifs.js:513` à `519`), et rien d'approximatif : 39 correspondances, 9 analyses sans ligne (`L05`, `L11`, `L27`, `L29`, `L30`, `L31`, `L33`, `L34`, `L48`, mesuré) et 2 lignes LABO sans analyse (`LAB-BU`, `LAB-SDW`). Version 1 = prix de `analyses` (ce que la caisse facture). Le prix de la grille, **s'il diffère**, arrive en **version 2 proposée** avec l'alerte (39 versions 2 proposées sur la semence : 28 prix égaux à aucune colonne, 11 égaux à une seule colonne dont l'autre colonne diffère) |
| E | 3 journées d'hospitalisation | prix de `D.TYPES_CHAMBRE` ; `D.TYPES_CHAMBRE.tarif` devient une lecture du référentiel |
| F | produits | **hors fusion initiale** (4.7) |

Sont écartés de la migration : tout doublon de **libellé** entre S2 et S3 non rapproché par la règle existante (libellé identique ou correspondance nommée, `data-tarifs.js:470` à `511`) : **aucun rapprochement nouveau n'est introduit**. Un acte que la grille décline (4 : `MA02`, `MA14`, `MG05`, `SO12`) garde `variantesGrille` et son motif ; on ne choisit pas la variante à la place de la clinique.

`VERSION` (`store.js:115`) vaut **77** à la date de ce document ; `PRD-IMP` en prévoit 78. Ce chantier prend **le numéro suivant libre à la mise en service** (la constante est la seule source, CLAUDE.md, vague 66) : les deux collections sont **semées**, donc sans incrément un poste garderait l'ancien jeu.

Les collections à déclarer : `LIBELLES` pour la corbeille (`store.js:4169`, `4268`), **`S.COLLECTIONS_ESSENTIELLES`** (`store.js:3875`, sinon le vidage des jeux de test efface les prix et rouvre une caisse sans tarif : leçon de la vague 68), `cfbEssentielles` côté domaine (`cfb_donnees.dart:170` à `200`, tenu par les vecteurs), le schéma relationnel (4.8).

### 4.6 L'adaptateur de compatibilité : une source, jamais deux écritures

* **Un seul écrivain** : le moteur du socle (`PR.proposerTarif`, `PR.decider`, `PR.importerTarifs`). Aucun écran n'écrit plus S2, S4 ni S6.
* **Les anciennes collections deviennent des projections de lecture**, reconstruites **à l'hydratation, à chaque décision et au changement de jour** (premier boot ou première lecture du jour), jamais éditées. `actes`, `analyses` et `catalogueTarifs` gardent leurs champs actuels, valeurs **en vigueur aujourd'hui**. Les lecteurs non migrés (`S.collection('actes').active()`, 11 sites ; `analyses`, 9 sites) fonctionnent sans modification.
* **Les accesseurs `D.tarif`, `D.tarifPrix`, `acteParCode`, `analyseParCode`** sont réécrits pour lire le nouveau référentiel avec la date. C'est ce qui répare, sans autre geste, les constats 1 et 2 : la **constante** n'est plus lue.
* **Une garde de parité** compare, à chaque amorçage et au banc, la projection au résultat de `tarifALaDate(code, aujourd'hui)` pour chaque code : un écart est une erreur nommée, pas un affichage différent. Même esprit que la garde de `gen-pages` sur les scripts d'`index.html`.
* La projection est **un pont, pas une cible** : le lot de retrait (T7) la supprime quand les 32 lecteurs sont passés à l'accesseur daté.

### 4.7 Les produits

Trois options pour l'écran unique :

* **A. Éditables dans l'écran**, avec versions. Cohérent avec la décision 3 (« le prix d'un produit »), mais : le prix d'achat est un coût qui nourrit la valorisation et le CUMP, il est écrit par la **réception** et l'import Grand Stock ; 184 références et un RG-02 à contrôler ; le caissier et le gestionnaire de stock détiennent l'édition de produits.
* **B. Lecture seule dans l'écran, édition dans M6.** L'onglet « Produits » montre code, désignation, prix d'achat en vigueur, **prix de vente dérivé (RG-02)**, date d'effet, version, avec un renvoi « Modifier dans Référentiel produits ». Le **moteur de version et d'alerte est le même** (famille `PRODUIT`), mais le geste d'écriture reste à M6 et à l'import `tarifs-produits` du `PRD-IMP`.
* **C. Exclus**, comme aujourd'hui, sauf pour la règle de non rétroactivité.

**Mise en œuvre (lot T5, 12/11/2026, option B tranchée par la Direction le 11/11/2026)** : famille `PRODUIT` dans `tarifs` et `versionsTarif`, prix d'achat versionné, prix de vente dérivé (RG-02), onglet en lecture seule, bouton « Historique de prix » sur chaque ligne, « Changer le prix d'achat » à `m6-produits`, jeu `tarifs-produits`, RG-02 tenu à l'écriture (E846 corrigé) ; la question de la réception de M7 est tranchée par la lecture (elle ne met à jour que le CUMP : E2436).

**Recommandation : B, et en lot séparé (T5).** Les produits ne sont pas une prestation tarifée : leur prix de vente n'est pas un choix de la clinique mais la conséquence de RG-02. Les montrer **à côté** des prestations répond au « un seul écran » sans obliger le gestionnaire de stock à passer par un écran de Direction. Le prix qui doit être **versionné** est le prix d'achat (`PRD-IMP` : `tarifs-produits`, « nouvelle version datée », ligne 351). **Non vérifié** : si les réceptions de M7 mettent à jour `prixAchat` (la recherche dans `m7-achats.js` ne montre que le formulaire produit et les lignes de besoin, `m7-achats.js:442`, `562`) ; la réponse décide si l'alerte sur un produit est fréquente ou rare. Pour le **médicament**, une alerte n'a de sens que si le prix de **vente** change, c'est-à-dire si le prix d'achat change (RG-02) ; pour les autres catégories, `prixVente` est un champ propre (`m6-stock.js:435`).

### 4.8 Tables relationnelles

Régénération par `prototype_html/build/gen-schema-pg.js` après ajout au magasin (CLAUDE.md, vague 70) : `cfg.tarifs` et `cfg.versions_tarif` avec **clé étrangère** de la version vers la prestation (aucun orphelin attendu : à vérifier au chargement), une table fille pour `codes_alias` et pour `variantes_grille` (`cfg.actes_variantes_grille` existe déjà, 16 lignes, `DICTIONNAIRE-DONNEES.md:50`). Sorties : `api/schema/`, `packages/schema/postgres/0001_modules.sql`, `DICTIONNAIRE-DONNEES.md`. La projection (`api/projection.php`) tient la copie relationnelle sur les deux chemins d'écriture (`magasin.php`, `crud.php`) : la **parité** (`php api/projection.php --verifier`) fait partie des critères de sortie. Un champ inconnu va dans `extra`, une collection inconnue est nommée dans `projection_erreurs`.

---

## 5. Le circuit de changement de prix

### 5.1 Ce que le logiciel « constate »

Un **changement** est constaté quand une proposition diffère de **la version en vigueur à sa date d'effet** (ou, à défaut, de la dernière version valide) sur au moins un de : `prixNonAssure`, `prixAssure`, `etatAssure`, `assurable`. Une ligne identique est « inchangée » : ni version, ni alerte, et l'import la **compte** (un doublon ignoré en silence est une donnée perdue sans le dire, `PRD-IMP` ligne 449). Une **création** de prestation est une première version : même circuit, sans variation à afficher.

### 5.2 Les états d'une version

`propose` → (`valide` | `refuse`) ; `propose` → `retire` (par son auteur) ; `valide` à venir → `retire` (Direction, DAF, administrateur, avec motif). Une version `valide` **déjà en vigueur et déjà utilisée par une pièce** ne se retire **pas** (même règle que `parametre_deja_utilise`) : on la remplace par une nouvelle version. RG-14 : rien ne se supprime, une version refusée ou retirée reste lisible dans l'historique.

### 5.3 L'alerte de validation Oui/Non

* **Déclenchement** : création d'une version `propose`, à l'écran ou à l'import.
* **Contenu** : code, libellé, ancien prix puis nouveau (non assuré et assuré), variation en pourcentage, date d'effet, auteur, motif, source (écran ou lot `IMP-…`), et une **information utile** : le nombre de pièces émises avec ce code sur les 30 derniers jours (calculé sur les lignes), pour mesurer ce que le changement touchera.
* **Décision** : **Oui** (la version devient `valide` et prend effet à la date indiquée) ou **Non** (`refuse`, **motif obligatoire**, comme les chiffres de la validation par modale : `PRD-M13` Q4). Pas de « Oui, mais plus tard » en v1.
* **Qui valide** : `direction`, `da`, `admin`, qui sont déjà les profils des familles `actes` et `analyses` (`parcours.js:4316` à `4319`). Un fileul **ne valide pas** : la garde `CONFIGURATION_DE_LA_MÈRE` existe déjà (`parcours.js:4395` et suivantes).
* **Qui est notifié** : par la **source dérivée** `prix_a_valider` à ajouter à `notifications.js` (une alerte **disparaît quand sa source cesse de la produire**, règle du moteur ; regroupée par lot au-delà de trois, règle du moteur), adressée aux postes `da` et `direction` ; **lien** vers l'onglet « Alertes » de l'écran unique (`LIENS_NOTIF`, `notifications.js:118` à `124`). Le moteur **route, il ne décide** : aucun seuil n'est écrit dans `notifications.js`. À la décision, **`PR.notifier`** (`parcours.js:626`) adresse le **retour** au poste de l'auteur (« votre changement de prix X a été accepté ou refusé, motif ») : une alerte dérivée ne peut pas porter un retour.
* **Rien n'est appliqué tant que l'alerte est ouverte** : la résolution (4.3) ignore les propositions, **le prix en vigueur ne bouge pas**.
* **Centre des validations** : la famille « changements de prix en attente » est ajoutée à `adm-validations` avec son compte **lu, jamais écrit** (doctrine de `FAMILLES_A_VALIDER`).

### 5.4 Relation avec la validation par modale (`PRD-M13`)

La décision du 08/11, arrêtée le 09/11, dit : le choix **Valider** dans la modale, et enregistrer par un profil de la famille valide (Q1 oui). Les deux circuits cohabitent sans se confondre : **le marquage « tarif d'attente »** (`tarifProvisoire`) reste régi par `PRD-M13` ; **un changement de prix** suit la règle de ce PRD. Proposition (Q3) : quand l'auteur du changement est lui-même de la famille (Direction, DAF, administrateur) et coche **Valider** dans la modale d'enregistrement, la version naît `valide` **en un geste**, journalisée avec son rôle ; sinon elle naît `propose` et l'alerte part. C'est le précédent de `PRD-M13`, et c'est ce qui évite que chaque correction de la DAF attende la Direction.

### 5.5 Le champ Oui/Non de l'import

Colonne **« Valider (Oui/Non) »**, avec une colonne **« Motif »** et une colonne **« Date d'effet »** (obligatoire, mode `versionner` du `PRD-IMP`).

| Valeur | Importateur détenant le droit de validation | Importateur sans ce droit |
|---|---|---|
| **Oui** | version `valide` d'emblée, prend effet à la date d'effet, tracée « validée à l'import `IMP-…` » | **le Oui vaut proposition** : version `propose`, alerte ; la vérification **le dit** ligne par ligne |
| **Non** | la ligne n'est **pas appliquée** ; **motif obligatoire**, consignée au rapport et au lot ; **aucune version fiche** (un Non est la décision de l'importateur, pas un refus de validateur) | idem |
| **vide** | version `propose`, alerte (la valeur par défaut est la prudence) | idem |

Un **Non** n'est pas une erreur : il ne fait pas échouer le fichier (la règle « un refus refuse le fichier entier », `import.js:807`, s'applique aux erreurs de format et de règle, pas à ce choix). Le gestionnaire de stock, sur un **fileul**, ne dépose qu'une **demande d'import** vérifiée (`demandesImport`, famille B, `PRD-IMP` 8.3) : la mère applique, **refait les mêmes contrôles** et crée les versions.

### 5.6 Cas limites

| Cas | Règle proposée |
|---|---|
| **Date d'effet passée** | refus nommé `TARIF_DEJA_UTILISE` si une pièce non archivée porte déjà le code à partir de cette date ; sinon **acceptée seulement avec une case « date passée » cochée et un motif**, et réservée à la Direction et à la DAF. Jamais silencieuse. |
| **Date d'effet dépassée pendant l'attente** | l'alerte le signale ; au moment du **Oui**, le contrôle d'usage est **rejoué** ; s'il échoue, le Oui est refusé avec le geste « refuser puis reproposer avec une date d'effet d'aujourd'hui ». Aucun décalage automatique. |
| **Deux changements le même jour** | **une seule proposition en attente par prestation** (`CHANGEMENT_EN_ATTENTE`, refus nommé) ; deux versions `valide` à la même date d'effet : la plus grande `version` l'emporte, les deux restent lisibles ; la seconde est refusée par `tarif_deja_utilise` dès qu'une pièce a été émise ce jour. |
| **Prix zéro** | refusé (`PRIX_ZERO`) : un zéro n'est pas un tarif (arbitrage « plus aucun montant nul »). La gratuité passe par la remise motivée ou la prise en charge du personnel, pas par un prix à 0. |
| **Prix absent** | une proposition peut porter `manquant` (le tiret) : elle **ne se valide pas** (`TARIF_ABSENT`, déjà en place pour `actes` et `analyses`, `parcours.js:4415`) et la ligne ne se facture pas. |
| **Variation extrême** | **proposition à valider** : afficher la variation en pourcentage à l'alerte, sans seuil bloquant ; un seuil paramétrable (`tarifs.variation_alerte_pct`, règle du 09/11) pourrait la mettre en évidence, **aucune valeur documentée** : à décider (Q8). |
| **Assurance, facture émise sous une couverture ancienne** | **rien ne se recalcule** : les lignes sont figées (R6), M9 lit les lignes (R16), l'avoir porte les lignes d'origine (R23). Pour une pièce **nouvelle** datée D, la colonne se choisit par `carteValide(patient, D)` (qui lit `couverturesAssurance` à la date, `parcours.js:2024`, `2110`) et la version par D. Les deux dates sont **la même**. |
| **Fiches sans montant, anciennes demandes** | R15 : la valeur d'une analyse passée sans montant ne se relit **jamais** au catalogue courant ; elle devient « non renseignée » (Q14). |
| **Lignes impayées d'une pièce ouverte, prescription pas encore encaissée** | **le prix est figé à la création de la ligne** (`prescrire` crée la pièce `impayee` d'emblée, `parcours.js:196`, `272`) : le patient a été informé de ce prix. Un changement ultérieur **ne touche aucune ligne existante**, payée ou non (Q4). |
| **Pro-forma** | une pro-forma est une estimation non fiscale (`m8-facturation.js:329` à `330`). **Non vérifié** : s'il existe une conversion pro-forma vers vente ; proposition : à la conversion, **le prix en vigueur à la date de conversion** s'applique et l'**écart avec la pro-forma est affiché**, sauf si la conversion intervient dans une durée de validité paramétrable (`tarifs.validite_proforma_jours`, défaut 30 : **proposition, aucun document**) (Q5). |
| **Retrait d'une alerte par son auteur** | autorisé tant que `propose`, journalisé. |

### 5.7 Journal, annulation, archivage

* **RG-12** : une entrée de journal à **chaque** transition (`proposition`, `validation`, `refus`, `retrait`) avec auteur, rôle et motif. Mais le journal est **plafonné à 400 entrées de 100 caractères** (`store.js:3987` à `4010`) : **l'historique d'un prix ne vit pas dans le journal**, il vit dans `versionsTarif`. C'est la raison même du versionnement.
* **Annulation** : le toast d'annulation du kit (`annulable()`) s'applique à une proposition (retrait), **pas** à une validation : une décision de la Direction se **remplace** par une nouvelle version, elle ne s'efface pas.
* **RG-14** : une prestation s'**archive** (elle reste lisible, la restauration existe), une version ne se supprime pas. `S.corbeille()` les range (`LIBELLES`).

---

## 6. L'écran unique

### 6.1 Identité et plan

Un seul écran, **« Tarifs et prix »** (T15, décidé le 11/11/2026), dans le domaine CFG. Livré au lot T2 : les six onglets ci-dessous, avec les identifiants `prestations`, `analyses`, `imagerie`, `produits`, `alertes`, `historique`. Identifiant technique proposé : **`cfg-tarifs`** (le plus ancien et le plus référencé : alias d'ACCUEIL, recherche `nav.js:1625`, jeux d'import, vecteurs).

| Onglet | Contenu |
|---|---|
| **Prestations** (filtre par famille : consultations, actes, gynéco-obstétrique, soins AMI, hospitalisation, certificats) | colonnes : code, libellé, famille, secteur, prix non assuré, prix assuré avec ses trois états, couverture, en vigueur depuis, version, statut ; filtres avancés : famille, secteur, couverture (`oui`, `non`, `SOS`), état du prix (valide, **en attente**, à venir, **manquant**, provisoire), plage de dates d'effet |
| **Analyses** | prix de la famille `LABO` ; désignation, catégorie, échantillon, délai en **lecture** si le biologiste les tient à `m5-catalogue` (Q10) |
| **Imagerie** | les 23 lignes `IMAGERIE` ; **renvoi** vers `cfg-imagerie-catalogue` pour le modèle de compte rendu |
| **Produits** | **lecture seule** (4.7, option B) |
| **Alertes** | les changements `propose` : comparaison ancien et nouveau, boutons Oui et Non (gardés par le droit de valider), regroupés par lot |
| **Historique** | toutes les versions d'un prix (sélection d'une prestation) : date d'effet, version, prix, statut, auteur, valideur, motif ; **comparaison de deux versions** |

Chaque ligne ouvre un **tiroir de détail** (le gabarit de `K.crud`) avec la courbe des versions et les pièces émises sous chacune (compte, jamais la liste des patients : RG-13). L'impression **« grille tarifaire »** porte « en vigueur au JJ/MM/AAAA », la version, et un pied normalisé ; un total n'a pas de sens ici (prix unitaires), aucune colonne `somme`.

Le bouton **« Importer les données »** vient de **`K.importer`** (`PRD-IMP` 7.1, fabrique unique du kit, absent sans le droit d'import du jeu), posé sur l'écran par la clé `importer: 'tarifs'` de `K.crud` ou par `K.importer('tarifs')` dans un écran construit à la main.

### 6.2 Droits (une fiche RBAC par rôle)

Aujourd'hui le droit de modifier un prix est celui d'**éditer** l'écran. Il faut distinguer **proposer** de **valider**. Proposition :

| Profil | Voir | Proposer (éditer) | Valider (Oui/Non) | Importer | Remarque |
|---|---|---|---|---|---|
| admin | tout | oui | oui | oui | inchangé |
| da | tout | oui | oui | oui | porte déjà 111 |
| direction | tout | oui | oui | oui | porte 110 ; « signer n'est pas saisir » reste vrai : valider ne **saisit** pas |
| comptable | prestations, analyses, imagerie | non | non | non | proposition : il lit les prix qu'il écrit en comptabilité |
| gestionnaire de stock (**fileul**) | onglet Produits | **non** sur les prestations ; sur les produits, **uniquement** par l'import `tarifs-produits` (prix d'achat) via la demande d'import | non | oui, `tarifs-produits` seulement | `PRD-IMP` Q4 : il n'édite pas le prix de vente des prestations |
| caissier | prestations (lecture) | non | non | non | **perd l'édition des produits** à M6 à arbitrer : il la détient aujourd'hui (`rbac.json`) ; à confirmer (Q9) |
| biologiste (laborantin) | analyses (lecture) | non | non | non | perd l'édition du prix d'analyse de `m5-catalogue` mais **garde** désignation, échantillon, délai (Q10) |
| reception, médecin, autres | lecture comme aujourd'hui (`reception` 100) | non | non | non | inchangé |

Le droit de valider est porté par la **liste de rôles de la famille** (comme `FAMILLES_A_VALIDER`) et **jamais** par `editer` : un `editer` sur l'écran ne vaut pas décision. Le **moteur refuse aussi** (`PR.decider` revérifie le rôle) : masquer un bouton ne protège rien (précédent `S.garder`, CLAUDE.md vague 69). Les commandes d'écriture sont `K.commande` (absentes, jamais grisées). L'**audit RBAC** (`npm run audit-rbac`) est étendu : 0 promesse, 0 lecture non dite sur le nouvel écran pour chaque profil. Les fiches RBAC sont semées : même incrément de `VERSION`.

### 6.3 Les anciens écrans

**Jamais retirés du manifeste** (doctrine de la vague 36 : retirer une entrée supprime la page et casse tout lien qui la vise). `cfg-catalogue` et `m5-catalogue` (pour le prix) deviennent des **pages-renvoi hors ruban** (`STANDALONE`, module CFG ou M5), comme `m2-visites`, `m1-certificats-externes` et `m1-dossier-etendu`. Les entrées d'ACCUEIL (`nav.js:148`, `149`) restent des alias résolus sur l'entrée canonique. Les rubriques de recherche (`nav.js:1625` à `1629`) pointent vers les onglets du nouvel écran, et la recherche **filtrée par RBAC** (RG-13) n'offre jamais un lien vers un onglet interdit. `gen-pages` **échoue** si un `servant` ou un `ecran:` désigne un identifiant mort (garde existante). Les cartes de hub, les accès rapides et la matrice RBAC lisent l'index à la source (leçon de la vague 67 : les drapeaux d'un écran viennent de l'index, pas de l'appelant).

La parité N1 compare les libellés : tout libellé changé est une **déclaration** (nouvelle fiche de parité, écart consigné), pas une dérive silencieuse. Les statuts « porté » de `cfg-tarifs`, `cfg-catalogue`, `m5-catalogue` repassent à « à porter » jusqu'à la remesure.

---

## 7. Importation

### 7.1 Articulation avec `PRD-IMP`

Ce PRD **remplace** pour les tarifs les propositions du `PRD-IMP` :

* ses jeux `catalogue-tarifaire` (ligne 357) et `actes` (ligne 358) deviennent **un seul jeu `tarifs`** (écrit `tarifs` et `versionsTarif`, mode `versionner`) ; sa question Q2 (« catalogueTarifs alimente-t-elle la facturation ? ») est **close** par la décision F : la facturation lit désormais le seul référentiel ;
* son jeu `analyses` se **scinde** comme il le recommandait (Q3) : `analyses-modele` (écrit `examensLabo`, inchangé) et les **prix d'analyses** passent par le jeu `tarifs` (famille `LABO`) ;
* `tarifs-produits` (ligne 351) **reste un jeu distinct** (prix d'achat, mère seule), mais écrit par le même moteur de version et d'alerte (T5).

Les lignes 111, 129, 264, 357 et 358 du `PRD-IMP` sont à amender quand le lot T4 s'engage ; ce document **n'y touche pas**.

### 7.2 Règles du jeu `tarifs`

Colonnes : code, désignation, famille, secteur, prix non assuré (type `tarif`), prix assuré (type `tarif`), couverture, **date d'effet** (obligatoire), **Valider (Oui/Non)**, motif, source. Contrôles : un tiret n'est jamais un zéro (`manquant`) ; `NC` interdit en colonne non assuré (`import.js:446` à `458`) ; zéro refusé ; famille et secteur dans les listes arrêtées ; prix entiers ; un écart d'orientation des colonnes par rapport à la grille (pansement 9 000 contre 6 000, soin intraveineux 1 000 contre 800) est un **avertissement**, jamais corrigé (le fichier fait foi, `PRD-IMP` ligne 357). Doublon : **nouvelle version datée** pour un code existant ; code inconnu : création de la prestation ; prix identique : « inchangé » compté, aucune version.

La vérification est **tout ou rien sur les erreurs** (une erreur refuse le fichier), **ligne à ligne sur les décisions** (un Non n'est pas une erreur). La modale de vérification affiche, pour chaque ligne qui change, **l'ancien prix, le nouveau et la variation** : l'agent doit voir ce qu'il importe avant de l'importer. L'import écrit par un **seul** chemin, celui de `PR.proposerTarif` : la même vérification que la saisie à l'écran, pas une seconde.

### 7.3 Importer à un fileul

Famille R : « la mère seule écrit ». Un poste fileul qui importe des prix dépose une **demande d'import vérifiée** (famille B, ajout seul) que la mère applique après avoir refait les contrôles (`PRD-IMP` 8.3, lot L6). C'est la réponse du 10/11 sur le poste du gestionnaire de stock : elle **ne contourne pas** la validation Oui/Non, elle en est l'amont.

---

## 8. Poste Flutter, hors ligne, synchronisation

### 8.1 Hors ligne et synchronisation (section obligatoire)

* **Familles** (`SPEC-protocole-synchronisation.md:54` à `63`) : `tarifs` et `versionsTarif` sont de **famille R** (la mère seule écrit, un poste ne modifie pas un référentiel, il le demande). Une version est une **fiche immuable** `code@dateEffet@version` : aucune règle de fusion nouvelle, exactement la conclusion d'inventaire du lot L0 des paramètres. Les décisions Oui et Non sont **appliquées à la mère**.
* **Proposition faite à un fileul** : le fileul **ne peut pas** écrire `versionsTarif` ; il dépose une **proposition** (famille B, ajout seul : proposition de collection `propositionsTarif`, ou réutilisation de `demandesImport` pour les imports) que la mère transforme en version `propose` après avoir refait les contrôles. **Non vérifié** : si les postes de la DAF et de la Direction sont des fileuls ; la recherche dans le dépôt ne le dit pas (Q11). Si ce sont des fileuls, la **décision** Oui ou Non est elle aussi une pièce de famille B appliquée par la mère.
* **Résolution hors ligne** : le prix se calcule **à la date de la pièce**, sans horloge ni tâche planifiée ; une version `à venir` s'active quand la date arrive, **sans connexion**. Un fileul qui n'a pas encore reçu une version dont la date d'effet est passée facture à l'ancien prix ; la mère **marque** la pièce `tarifEnEcart` à réception, **elle ne la réécrit pas** (pièce émise immuable, famille C).
* **Mobiles** : aucun lecteur de prix dans `apps/mobile/lib` (2.2). `tarifs` et `versionsTarif` en vigueur suivent la configuration comme `catalogueTarifs` aujourd'hui (`cfbEssentielles`, `configuration_sync.dart:9` à `23`) ; **les propositions, refus et motifs ne partent jamais vers un téléphone** (donnée financière, RG-13). Liste prudentielle à valider.
* **Relais** : opaque, il ne reçoit que du chiffré (`apps/web`, aucune règle tarifaire) ; aucune route à écrire.
* **Quota** : deux collections ajoutées au socle, à **mesurer avant de semer** (leçon de la vague 64), champs nuls non écrits.

### 8.2 Ce qu'il faut porter

* **Domaine Dart** : `packages/domaine/lib/src/tarifs/` sur le modèle de `parametres/` (règles pures, un refus se nomme avec code, motif et geste, aucune date lue sur l'horloge) : `resoudreTarif`, `proposerVersion`, `deciderVersion`, `controleUsage`, `projeterCompatibilite`. Les vecteurs viennent **de l'écran réel de la maquette piloté dans Chrome** (CLAUDE.md, portage Flutter) : `vecteurs-tarifs.js`, pas de la lecture du code. Le domaine reprend `prixTarif` de `imagerie/img_demandes_tarif.dart:12` et `csTarifPrix` de `cs_moteur.dart:504`.
* **Poste** : un écran unique à la place de `cfa_tarifs.dart` (424 lignes) et `cfa_catalogue.dart` (163 lignes) ; les 8 groupes de lecteurs P1 à P8 passent à l'accesseur daté ; le jeu de départ `gen-poste-jeu.js:14` ; les garde-fous de `Magasin` (« réglé sur la mère ») pour `tarifs` et `versionsTarif` ; la liste `collectionsConfiguration()` (`configuration_sync.dart:23`) ; `collectionsDeLaMereSeule` (`pont_activite.dart:45`) n'est pas concernée (elle vise l'activité).
* **Écarts à consigner** (E2337 et suivants) : divergence maquette et poste sur `catalogueTarifs` (constat 10) ; libellés de l'écran unique ; tout comportement du poste qui diffère de la maquette.
* **Limite à dire** : le SDK Flutter n'est pas dans l'environnement de rédaction (CLAUDE.md : « se réinstalle »). Rien ne se déclare « porté » sans `flutter analyze`, `flutter test` et la parité N1 mesurée à 100 % (`parite_ecrans_test.dart` refuse sinon).

---

## 9. Lots proposés

Ordre et dépendances. **T1 à T3 ne dépendent pas du PRD d'import** ; T4 en dépend ; T5 s'aligne sur son lot L2.

| Lot | Contenu | Dépend de | Preuve exigée |
|---|---|---|---|
| **T0 caractérisation** | scénarios qui **établissent l'état actuel** sans rien corriger : (a) un prix modifié à `cfg-catalogue` change-t-il la prochaine prescription d'imagerie, de soins ? (b) un prix d'analyse modifié à `cfg-tarifs` est-il facturé par la caisse manuelle et par `prescrire` ? (c) quels lecteurs relisent le catalogue sur une pièce émise ? (d) mesure de la marge de quota | | **les constats 1, 2 et 9 passent de « lus » à « mesurés »** ; si un constat est faux, le PRD est corrigé avant T1 |
| **T1 socle et adaptateur** | `tarifs`, `versionsTarif`, migration, `PR.tarifALaDate`, accesseurs, projection de lecture, garde de parité, `COLLECTIONS_ESSENTIELLES`, `LIBELLES`, `VERSION`, schéma relationnel | T0 | **comparaison exhaustive** : pour chaque code (147 + 73 + 48) et chacune des cinq voies, prix avant égal prix après, assuré et non assuré ; `check` 0 erreur, 0 lien cassé ; `projection --verifier` : 0 écart |
| **T2 écran unique, lecture et édition** | écran, historique, comparaison, droits proposer et valider, pages-renvoi, recherche, hubs, `audit-rbac` | T1 | scénario au geste sur chaque onglet et chaque profil ; audit RBAC : 0 promesse, 0 lecture non dite ; N1 remesurée |
| **T3 circuit Oui/Non** | `PR.proposerTarif`, `PR.decider`, `tarif_deja_utilise`, source de notification, retour à l'auteur, centre des validations, modale de saisie avec **Valider**, cas limites de 5.6 | T1, T2 | un scénario par cas limite de 5.6 ; **mutations** ci-dessous |
| **T4 import** | jeu `tarifs`, colonne Oui/Non, date d'effet, vérification avec comparaison ancien et nouveau, lot, annulation par archivage | T3, **PRD-IMP L0 (`K.importer`) et L1** | scénarios 7.2 ; un lot refusé ne laisse aucune valeur dans `lotsImportation` |
| **T5 produits** | onglet lecture seule ; versions du prix d'achat ; jeu `tarifs-produits` sur le même moteur ; contrôle RG-02 à l'écriture (corrige E846) ; question de la réception (4.7) | T3, **PRD-IMP L2** | RG-02 : aucun médicament vendu avec marge ; une pièce émise garde son prix |
| **T6 poste Flutter** | domaine, vecteurs, écran, lecteurs, sync, parité | T2, T3 | `flutter analyze`, `flutter test`, vecteurs rejoués, banc de synchronisation à deux postes (`npm run banc:sync`) : un fileul reçoit les versions, ne peut pas les écrire, sa proposition est appliquée par la mère |
| **T7 retrait des anciennes listes** | suppression des projections, de `D.CATALOGUE` et `D.ANALYSES` comme **sources** (ils restent semence), garde de génération contre toute lecture directe, `TYPES_CHAMBRE` en lecture | T1 à T6 | garde de build verte ; recherche textuelle des lectures directes : zéro |

### 9.1 Scénarios au geste (à écrire, aucun n'existe)

1. **Une seule liste** : modifier un prix à l'écran unique ; la prescription, la caisse manuelle, les soins, l'imagerie et un certificat lisent **la même valeur** (cinq voies).
2. **Non rétroactivité** : émettre une pièce à la date D ; valider un changement dont la date d'effet est D+1 ; rouvrir la pièce, émettre un avoir, éditer le relevé M9, relire l'écran de l'assurance du personnel : **montants identiques**, au franc près.
3. **Date d'effet future** : décaler l'horloge du banc (`window.__SIGH_HORLOGE.decaler`) : le prix **bascule le jour dit** sans rechargement ni connexion.
4. **Une proposition en attente ne change rien** : prix en vigueur identique, alerte visible, cloche et badge ; le Oui change le prix, le Non non, le retour arrive à l'auteur.
5. **Import** : fichier avec une ligne Oui par un validateur, une ligne Oui par un non validateur, un Non avec motif, une ligne vide, une ligne identique, une date passée utilisée, un prix zéro, un tiret : chaque ligne a son **sort nommé**, rien d'écrit à la vérification.
6. **Deux changements le même jour** et **date passée déjà utilisée** : refus nommés.
7. **Droits** : le gestionnaire de stock ne voit pas la commande de saisie d'un prix de prestation ; le biologiste ne modifie plus un prix d'analyse ; une URL directe d'un onglet interdit renvoie au 403.
8. **Migration** : la comparaison exhaustive de T1, plus la liste des écarts S2 contre S3 et S5 contre S3, **affichée** à la Direction.
9. **Vidage des jeux de test** : les deux collections survivent (leçon de la vague 68).
10. **Fileul** : voir T6.
11. **Rejeu après rechargement** : le magasin persisté ne perd aucune version (le quota).

### 9.2 Mutations (la sonde doit rougir)

(a) retirer le contrôle `tarif_deja_utilise` → le scénario 6 rougit ; (b) résoudre à la date du jour et non à la date de la pièce → le scénario 2 rougit ; (c) lire une version `propose` comme en vigueur → le scénario 4 ; (d) faire relire le catalogue à une pièce émise (R15 non corrigé) → le scénario 2 ; (e) retirer l'alias de code → la comparaison exhaustive ; (f) faire valider un fileul → le scénario 10 ; (g) laisser le caissier valider → l'audit RBAC. Une sonde qui ne rougit pas ne prouve rien.

### 9.3 Risques

| Risque | Gravité | Parade |
|---|---|---|
| La caisse facture un autre prix après la migration | **haute** | comparaison exhaustive à T1 ; projection de lecture ; migration sans changement de prix |
| La couverture d'assurance change à cause d'un libellé | **haute** | libellé de facturation = libellé de S2 ; sonde sur trois exclusions de convention réelles |
| Un prix d'analyse change le jour même | **haute** | version 1 = prix facturé aujourd'hui, grille en proposition (Q2) |
| Alerte noyée (150 lignes importées) | moyenne | une alerte par lot, comparaison ligne à ligne (Q8) |
| Quota du magasin | moyenne | mesurer avant de semer |
| Divergence maquette et poste | moyenne | un écart consigné par différence ; vecteurs régénérés |
| Un validateur valide son propre changement sans qu'on le voie | moyenne | rôle et motif tracés sur la version ; Q3 |
| Parité N1 cassée par un libellé | faible | déclaration explicite des libellés |

---

## 10. Impression et états

La grille tarifaire imprimée (`configuration.js:1260` à `1290`, `m5-laboratoire.js:1276` à `1282`) devient un **état unique** daté : « en vigueur au JJ/MM/AAAA », version la plus récente par ligne, prestations en attente listées à part. Le filtre en force est relevé sur la page par `print.js` : un état imprimé depuis un onglet filtré le **dit**. L'historique d'un prix et la comparaison de deux versions sont imprimables (signature de la DAF et de la Direction). Les pièces émises, elles, **ne se réimpriment jamais avec le prix d'aujourd'hui** : elles lisent leurs lignes.

## 11. Ce qui n'est pas documenté

Aucun document du dépôt ne fixe : qui, de la Direction ou de la DAF, décide un changement de prix ; la durée de validité d'une pro-forma ; un seuil de variation à signaler ; la liste des profils autorisés à importer des prix ; si les postes de la DAF et de la Direction sont des fileuls ; si les réceptions de M7 mettent à jour le prix d'achat. Tout ce qui est écrit à ce sujet plus haut est une **proposition à valider**.

---

## 12. Questions ouvertes pour la Direction, avec une recommandation chacune

**Q1. Un seul code ou deux ?** Les actes ont un code (`SO02`) et la grille un autre (`SIV`). *Recommandation : une prestation, un code canonique, l'autre en alias résolu à la lecture ; le libellé de facturation est celui des actes (les exclusions de convention s'y appuient), le libellé de grille est conservé à côté.*

**Q2. Prix d'analyses : lequel est le prix de départ ?** La caisse facture aujourd'hui la valeur d'attente de `analyses` ; la grille donne deux colonnes qui diffèrent sur 28 des 39 analyses rapprochables (les 11 autres n'égalent qu'une colonne). *Recommandation : la valeur facturée aujourd'hui devient la version 1 (aucun changement le premier jour) ; les prix de la grille arrivent en version 2 proposée, soumise à Oui ou Non analyse par analyse, avec les 10 analyses sans grille signalées.*

**Q3. L'auteur peut-il valider son propre changement ?** *Recommandation : oui pour la Direction, la DAF et l'administrateur, **en un geste** par le choix Valider de la modale (précédent `PRD-M13` Q1), tracé avec son rôle ; non pour tous les autres, dont les propositions deviennent des alertes. Alternative : deux personnes toujours (« signer n'est pas saisir »), plus sûre, mais chaque correction de la DAF attend la Direction.*

**Q4. Le prix d'une ligne impayée est-il figé à la prescription ?** *Recommandation : oui. Le patient a été informé de ce prix ; un changement ne touche aucune ligne existante.*

**Q5. Une pro-forma accepte-t-elle un prix pour une durée ?** *Recommandation : à la conversion, le prix en vigueur à la date de conversion, avec l'écart affiché, sauf pendant une durée paramétrable (défaut 30 jours, proposition).*

**Q6. Une date d'effet passée est-elle permise ?** *Recommandation : refusée dès qu'une pièce a utilisé la prestation depuis cette date ; sinon permise à la Direction et à la DAF seulement, avec une case explicite et un motif.*

**Q7. Le champ Oui/Non : quelle valeur par défaut et quel sort du Non ?** *Recommandation : vide vaut « à valider » (prudence) ; un Oui d'un importateur sans droit de validation vaut proposition ; un Non est consigné au lot avec son motif, sans créer de version.*

**Q8. Une alerte par ligne ou par lot ? « Tout accepter » est-il permis ?** La doctrine du centre des validations est « jamais de validation en masse » (CLAUDE.md, vague 49) ; or 150 prix importés ne se valident pas un à un. *Recommandation : une alerte par lot, décision **ligne par ligne** avec la comparaison affichée ; un « Oui à tout » n'est offert qu'après l'affichage de la comparaison, journalisé comme un geste, et n'est jamais disponible pour une variation que la Direction aura décidé de signaler (seuil `tarifs.variation_alerte_pct`, à fixer par elle, **aucune valeur proposée**).*

**Q9. Produits : lecture seule dans l'écran (option B) ?** Et le caissier garde-t-il l'édition des produits (`rbac.json`) ? *Recommandation : B, en lot séparé ; le prix d'achat se versionne par M6 et l'import `tarifs-produits` ; le caissier perd l'édition (il sert, il ne tarife pas), à confirmer.*

**Q10. Le biologiste garde-t-il la main sur le prix des analyses ?** *Recommandation : non (un prix est un acte de Direction ou de DAF), mais il garde désignation, échantillon, délai et tout le modèle de résultat.*

**Q11. Les postes de la DAF et de la Direction sont-ils la mère ou des fileuls ?** Non vérifiable dans le dépôt. *Recommandation : décisions prises à la mère ; si ce sont des fileuls, leur décision est une pièce de famille B appliquée par la mère, qui refait les contrôles.*

**Q12. La journée d'hospitalisation passe-t-elle au référentiel ?** *Recommandation : oui, et `D.TYPES_CHAMBRE.tarif` devient une lecture ; la nomenclature des lits reste à M3.*

**Q13. Faut-il dater aussi les garanties des assureurs ?** Même logique, autre chantier. *Recommandation : oui, dans un PRD séparé, après T7.*

**Q14. Que montre l'assurance du personnel pour une demande ancienne sans montant ?** *Recommandation : « non renseigné », jamais le prix courant (R15).*

**Q15. Nom de l'écran unique.** *Recommandation : « Tarifs et prix », identifiant `cfg-tarifs`.*

---

## 13. Priorités

**Indispensable** : T0, T1, T2, T3 (la décision 1 et la décision 3, et le moteur d'alerte de la décision 2). **Important** : T4 (import avec Oui/Non), T6 (poste). **Souhaitable** : T5 (produits dans l'écran), T7 (nettoyage). Sans T0, on corrige des défauts qu'on n'a pas vus : c'est lui qui dit si les constats 1 et 2 sont réels.
