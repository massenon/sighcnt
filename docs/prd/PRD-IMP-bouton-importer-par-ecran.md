# PRD-IMP : le bouton « Importer les données » dans chaque écran qui reçoit des données en masse

Statut : **proposé le 10/11/2026** (brouillon pour la Direction). Aucune ligne de code n'est écrite par ce document.
Sources : demande de la Direction du 10/11/2026 ; décision de la Direction du 10/11/2026 transmise avec la demande (la rangée « Importation de données » devient visible aux autres postes, avec un RBAC créé pour l'import) ; `prototype_html/assets/js/modules/import.js` (moteur, 1311 lignes) ; `prototype_html/assets/js/nav.js` ; `packages/rbac/data/rbac.json` ; `packages/domaine/lib/src/import/` ; `apps/poste/lib/modules/imp/imp_ecrans.dart` ; `docs/architecture/ECARTS-MAQUETTE.md` (E2000 à E2060) ; `docs/specs/SPEC-protocole-synchronisation.md` ; `CLAUDE.md`.
Règle de lecture : chaque affirmation sur le moteur cite `fichier:ligne`. Ce qui n'a pas été vérifié est dit **non vérifié**. Une valeur ou un libellé proposé sans source documentaire est une **proposition à valider**. Le code n'a été que lu : aucun banc n'a été lancé pour écrire ce document.

Note de méthode : `CLAUDE.md` renvoie à un « PRD d'import du 01/11/2026 » ; il n'existe pas dans `docs/prd/` (mesuré). La trace de ce chantier est le bloc E2000 à E2060 de `ECARTS-MAQUETTE.md`. Le présent PRD en tient lieu et le complète.

---

## 1. Problème et demande

### 1.1 La demande (10/11/2026)

Chaque écran de référentiel ou de registre qui doit pouvoir recevoir des données en masse porte un bouton **« Importer les données »**. Il ouvre une fenêtre en **trois temps** : (1) un **modèle de fichier** téléchargeable, (2) une **vérification** qui liste les erreurs ligne par ligne sans rien écrire, (3) l'**import**. Écrans cités : **Catalogue tarifaire (deux prix)**, **Transferts gros → détail**, **Référentiel produits**, « et autres écrans » : d'où l'inventaire de la section 3.

Le **gestionnaire de stock** doit importer le stock, le référentiel tarifaire et le catalogue **depuis son poste**. Aujourd'hui l'onglet « Système » du ruban est réservé à l'administrateur et à la DAF (`nav.js:1570`, `RUBAN_SYSTEME_ROLES = ['admin', 'da']`, décision du 05/11/2026), et le module « Importation de données » (IMP) y vit (`nav.js:696`) : il ne le voit pas. Le bouton vit donc dans l'écran métier.

### 1.2 Décision de la Direction du 10/11/2026, à intégrer

La rangée **« Importation de données » (IMP) devient visible aux autres postes** que l'administrateur et la DAF, avec **un RBAC créé pour l'import**. Elle remplace, **pour cette seule rangée**, la décision du 05/11/2026.

**Hypothèse à écrire et à faire confirmer (Q1)** : on rend visible **la rangée IMP**, pas tout l'onglet « Système ». Le reste de l'onglet (paramètres, modules, SMTP, SMS, sécurité, mode mère) reste réservé à l'administrateur et à la DAF, sauf demande contraire. Un profil qui détient un droit d'import voit donc un onglet « Système » réduit à une seule rangée (section 7.4).

### 1.3 Ce que ce PRD ne fait pas

Il n'ouvre aucune importation de donnée de santé, de paie nominative, d'écriture courante ni de pièce certifiée (section 5). Il ne touche ni `K.crud` ni la matrice existante en dehors de ce que la section 7 décrit. Il ne supprime pas l'écran de supervision des lots.

---

## 2. Ce qui existe, mesuré

### 2.1 Le moteur de la maquette

| Élément | Constat | Source |
|---|---|---|
| Un moteur, dix jeux déclaratifs | `grand-stock`, `personnel`, `patients`, `actes`, `analyses`, `fournisseurs`, `assureurs`, `souscripteurs`, `plan-comptable`, `soldes-ouverture` | `import.js:124, 245, 309, 414, 469, 507, 549, 584, 631, 660` |
| Un jeu déclare : colonnes (type, obligatoire, liste de contrôle), `cle`, `existe`, `regles`, `reglesLot`, `ecrire`, `dependances` | Tout le contrôle et l'écriture sont des fonctions du jeu | `import.js:124 à 242` (modèle complet : Grand Stock) |
| Types de cellule | `texte`, `entier`, `decimal`, `date` (AAAA-MM-JJ ou JJ/MM/AAAA), `liste`, `tarif` | `import.js:41 à 99` |
| Le type `tarif` respecte la doctrine « un tiret n'est pas un zéro » | tiret = `manquant`, `NC`/`non couvert` = `nc`, entier = `montant` ; un tiret écrit `null`, jamais 0 | `import.js:88 à 97` et `import.js:446 à 458` |
| Analyse complète avant écriture, tout ou rien | Un seul refus refuse le fichier entier ; les avertissements ne bloquent pas | `import.js:726 à 809`, décision finale `import.js:807` |
| Refus nommé | ligne, colonne, valeur, code, motif, geste | `import.js:769 à 779` |
| Doublon : un seul comportement, **refuser** | `DOUBLON_FICHIER` et `DOUBLON_MAGASIN` sont des refus ; aucun mode « ignorer » ni « mettre à jour ». Exception du lot IDEM (13/11/2026, poste) : le MÊME inventaire déjà importé par une demande (identité de contenu) n'est ni refusé ni réécrit, il est `LOT_DEJA_IMPORTE` (lignes ignorées et nommées) ; voir `docs/plans/PLAN-importation-bouton-par-ecran.md` | `import.js:782 à 789` |
| Fichier refusé consigné, rien d'écrit | lot `refuse`, 100 constats gardés | `import.js:855 à 865` |
| Écriture atomique, rejouée avant écriture | l'analyse est refaite sur les lignes d'origine (un autre poste a pu créer la même fiche) ; en cas d'échec on retire ce qui vient d'être posé | `import.js:867 à 896` |
| Fiches marquées `source`, `lotImport`, `validePar`, `dateImport` | | `import.js:881 à 883` |
| Journal RG-12 | `S.log('Import'...)`, `S.log('Import refusé'...)`, `S.log('Import annulé'...)` | `import.js:863, 902, 925` |
| Annulation d'un lot = archivage (RG-14), refusée si un acte s'appuie dessus | `dependances` par jeu ; rollback si un archivage est refusé | `import.js:906 à 927` |
| Modèle téléchargeable généré **depuis la déclaration du jeu** (une source) | classeur `.xlsx` de trois feuilles (Données, Instructions, Listes), listes déroulantes, ligne d'exemple ignorée si inchangée ; modèle `.csv` | `import.js:944 à 993`, ligne d'exemple `import.js:763` |
| Lecture de fichier | `.xlsx` (feuille « Données », à défaut la première) et `.csv`/`.txt` UTF-8, séparateur détecté parmi `;` `,` tabulation | `import.js:818 à 838`, `vendor/xlsx-mini.js:373 à 380` |
| Rapport d'erreurs `.xlsx` | feuilles Erreurs et Résumé | `import.js:995 à 1005` |
| Historique des lots, annulation | collection `lotsImportation` (référence `IMP-AAAA-NNN`) | `import.js:843 à 853, 1029 à 1068` |
| Statut d'un jeu | `supporte` ou `proposition` (l'analyse du laboratoire est une proposition à valider, validée par la famille `jeux_import`) | `import.js:470, 1071 à 1079` |
| Bouton absent sans droit | « Téléverser » et « Annuler le lot » sont des commandes déclarées (`K.commande`, `K.commandeIcone`) ; elles consultent `d.editer` ou `d.annuler` de l'écran | `import.js:1136, 1050` ; `_kit.js:176 à 193` |

Le moteur ne contient **aucune borne de taille** de fichier ni de nombre de lignes (recherche de `MAX`, `taille`, `maxLignes` dans `import.js` et `xlsx-mini.js` : rien de pertinent). La tenue sur 20 000 lignes (par exemple 18 000 patients) est **non vérifiée**.

### 2.2 Écarts constatés dans le code actuel (à lever par ce PRD)

1. **La liste `roles` de chaque jeu est décorative.** Elle est déclarée (`import.js:126, 247, 311…`) mais jamais lue : `peutOuvrir` n'interroge que `N.can` sur l'écran du jeu (`import.js:1023 à 1027`). Le « droit d'importer » est donc aujourd'hui le droit d'**éditer l'écran** `imp-*`. Aucun droit d'import distinct n'existe.
2. **Le jeu `actes` n'écrit pas la collection du « Catalogue tarifaire (deux prix) ».** L'écran `cfg-catalogue` lit et écrit `catalogueTarifs` (`configuration.js:3956 à 3958`) ; `catalogueTarifs` n'est lue que par `store.js` et `configuration.js` (recherche dans `assets/js` : `store.js:1841, 3878, 4268` et `configuration.js:3957`). La facturation lit `actes` (`parcours.js:154 à 155`). Le jeu `actes` (`import.js:419`) écrit `actes`. Importer un catalogue au bouton de `cfg-catalogue` demande donc un **nouveau jeu** ou une décision de rattachement (Q2).
3. **Même défaut au laboratoire.** `m5-catalogue` lit et écrit `analyses` (tarif, `tarifProvisoire`) ; le jeu `analyses` écrit `examensLabo` (le modèle de résultat) (`import.js:475, 494`). Importer le catalogue au bouton de l'écran n'importe pas ses prix (Q3).
4. **Un doublon refuse le fichier entier.** Pour un référentiel de plusieurs milliers d'articles, trois articles existants bloquent tout (`import.js:807`). Un mode déclaré par jeu est nécessaire (section 6.4).
5. **L'historique recopie des valeurs de cellule.** `consigner` garde 100 constats avec leur `valeur` (`import.js:861`) et le rapport les écrit (`import.js:998`) ; la liste des lots est visible de qui ouvre `imp-accueil` (`import.js:1275 à 1285`). Pour les jeux `patients` et `personnel`, cela recopie noms, téléphones, salaires dans un registre lisible hors du cercle habilité (RG-13). À corriger avant d'élargir l'accès (section 5.3).
6. **Le jeu `patients` accepte `groupeSanguin`** (`import.js:327`) : c'est une donnée clinique d'identification, à arbitrer (Q9).
7. **Le Grand Stock est hôte de deux faces** (import et reprise valorisée) sous un seul identifiant d'écran (`import.js:1147 à 1160`) : le bouton commun ne doit pas rompre cet assemblage.
8. **`m12-ouverture`** existe au manifeste (`nav.js`, vague 57) mais n'est pas dans la mesure du 06/11/2026 (327 écrans) : classé en plus (219 écrans classés au tableau 3.2).
9. Le **numéro de version courant** est 77 (`store.js:115`) ; `CLAUDE.md` cite encore 68 : le texte de cadrage est en retard sur le code.

### 2.3 Le poste Flutter

L'import **existe au poste** : moteur et dix jeux portés dans `packages/domaine/lib/src/import/` (`moteur_import.dart` 814 lignes, `jeux_import.dart` 963 lignes, `donnees_import.dart`), écran `apps/poste/lib/modules/imp/imp_ecrans.dart` (583 lignes) avec classeur `.xlsx` écrit et lu par `archive` et `xml` (E2005), sélecteur natif injectable, test `packages/domaine/test/import_test.dart` et vecteurs `packages/domaine/test/vecteurs/import.json` tirés de la maquette par `prototype_html/build/vecteurs-import.js`. Le classeur du poste se relit à l'identique de celui de la maquette (E2004). Les commandes d'écriture du poste sont absentes sans droit : `if (c.droit.editer)` (`imp_ecrans.dart:367, 464`), `c.droit.annuler` pour l'annulation (`imp_ecrans.dart:150`). Le droit d'import distinct n'existe pas non plus au poste.

### 2.4 Ce que dit la synchronisation sur un import

Rien n'est posé pour l'import dans `SPEC-protocole-synchronisation.md` (non vérifié : recherche limitée à la liste des familles lues). Ce qui s'applique par la nature de chaque collection :

* **Référentiels de configuration, famille R** : `cfbEssentielles` (`actes`, `analyses`, `produits`, `assureurs`, `fournisseurs`, `comptes`, `banques`, `naturesFacture`, `centresCouts`, `secteurs`, `postes`, `personnel`, `souscripteurs`, `garanties`, `catalogueTarifs`, `materiel`…) : « la mère seule écrit, un poste fileul rattaché a ses écrans de configuration en lecture seule et le moteur refuse l'écriture » (`packages/domaine/lib/src/configuration/cfb_donnees.dart:178`, spec 9). Un import de référentiel **au poste fileul est donc refusé par la règle existante**.
* **`produits`** est dans `collectionsDeLaMereSeule` (`apps/poste/lib/sync/pont_activite.dart:45`) : un fileul le reçoit sans jamais l'envoyer ; les **compteurs** (`stockGros`, `stockDetail`, `stock`, `quantiteRestante`) ne sont jamais écrasés, ils voyagent par variations (`fusion_activite.dart:21`).
* **`patients`** : famille de fusion par champ, code `CNT` unique, doublon marqué `codeEnDoublon` jamais corrigé en silence (`fusion_activite.dart:40`, `pont_activite.dart:164`).
* **`factures`, `avoirs`, `ecritures`, `mouvements`, `lots`, `admissions`** : règles de fusion propres, pièces émises immuables (`pont_activite.dart:15 à 45`).

---

## 3. Inventaire des écrans

### 3.1 Lecture et chiffres

Le tableau 3.2 classe **219 écrans** : les 218 registres, configurations, formulaires et outils des modules métier relevés par `prototype_html/build/mesures/inventaire-fonctions-ecrans.json` (mesure du 06/11/2026, 327 écrans au total, collection déduite du code de chaque écran : approximation, voir ci-dessous), plus `m12-ouverture`. Les **109 autres écrans** de la mesure n'ont **pas de collection propre** (recompte par module et par type, fait sur le fichier de mesure) : 20 tableaux de bord de poste (DASH), 13 écrans de pilotage (PIL), 22 de la console mère (MERE), 12 du panneau relais (RLS), 3 de support (SUP), 1 d'authentification (AUTH), et 38 écrans des modules métier de type tableau de bord (21), statistique (10), renvoi (4), état calculé (1), ou sans type relevé (2). Ils sont écartés : ce sont des lectures ou la console du serveur.

Colonne **Collection** : relevée par recherche de `collection('x')` et `collection: 'x'` dans le bloc de l'écran (les cas où elle n'apparaît pas sont laissés avec le nom de ce que l'écran manipule). **Approximation assumée** : à vérifier écran par écran au lot qui le branche.

Natures : référentiel, catalogue, registre opérationnel, pièce comptable ou certifiante, donnée clinique, calculé, configuration. Verdicts :

* **OUI** : un jeu d'import est pertinent (existant ou à créer, voir colonne jeu) ;
* **OUI, restreint** : pertinent avec une restriction nommée ;
* **NON** : l'import est à **refuser** (l'écran n'aura pas de bouton) ;
* **NON (à REFUSER)** : donnée sensible : le refus est une règle, pas un oubli (section 5) ;
* **NON recommandé** : techniquement possible, mauvais usage, motif écrit ;
* **sans objet** : lecture, vue ou outil, aucun registre propre ;
* **existant** : écran de jeu déjà en service.

Compte du tableau (219 écrans) : OUI et OUI restreint, avec ou sans jeu existant : voir 3.3 ; les écrans cliniques, de paie, de pièces et de sécurité sont tous classés NON.

### 3.2 Tableau des écrans

| Écran | Mod. | Collection | Nature | Jeu d'import | Import en masse pertinent | Motif | Profils qui importeraient |
|---|---|---|---|---|---|---|---|
| `adm-enquetes` | M13 | enquetes | registre / modèle | aucun | **NON** | Document de gestion saisi par son auteur. | sans objet |
| `cfg-branding` | CFG | ressources | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-catalogue` | CFG | catalogueTarifs | catalogue | à créer `catalogue-tarifaire` | **OUI** | Écran du « catalogue tarifaire (deux prix) » : il écrit `catalogueTarifs`, que seul lui lit (grep : store.js, configuration.js). Le jeu `actes` existant écrit `actes`, que lit la facturation (parcours.js:154). Deux collections, deux jeux : décision Q1. | DAF, admin, Direction (écriture 110 déjà) |
| `cfg-centres-couts` | CFG | centresCouts | référentiel | à créer `centres-couts` | **OUI** | Écran réel : `cfg-centres-couts` (CFG) ; code = imputation portée par les écritures (vague 55). | DAF, comptable, admin |
| `cfg-certificats` | CFG | certificats | modèle | aucun | **NON** | Modèle de pièce certifiante. | sans objet |
| `cfg-comptabilite` | CFG | calendrier fiscal | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-compte` | CFG | compte | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-entetes` | CFG | entête | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-fiscalite` | CFG | paramètres fiscaux | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-imagerie-catalogue` | CFG | examensImagerie, variablesImagerie | catalogue (proposition à valider) | à créer `catalogue-imagerie` | **OUI, restreint** | Examens créés `aValider` comme les analyses (import.js:474) : le professionnel nommé arrête les variables. | Échographiste n’écrit pas le catalogue ; DAF, admin |
| `cfg-modules` | CFG | modulesActifs | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-natures-facture` | CFG | naturesFacture | référentiel | à créer `natures-facture` | **OUI** | Référentiel court (code, libellé, secteur) lu par plusieurs modules. | DAF, admin |
| `cfg-notifications` | CFG | modelesMessage | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-organisation` | CFG | postes, secteurs | référentiel | à créer `organisation` (différé) | **NON recommandé** | Arbre de rattachement : l’import à plat ne dit pas la hiérarchie. | sans objet |
| `cfg-pair` | CFG | mode pair | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-poste` | CFG | poste | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-rappels` | CFG | rappels | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-regles` | CFG | parametres | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-smtp` | CFG | SMTP | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-systeme` | CFG | baremeNS131 | paramétrage d’exploitation | aucun | **NON** | Réglage de la clinique ou du poste : porte d’administration, jamais en masse (secrets SMTP, validations, barème NS 131 derrière sa porte). Règle de paramétrage du 09/11 : versions immuables datées. | sans objet |
| `cfg-tarifs` | CFG | produits, analyses, actes | catalogue | jeu `actes` existant + `tarifs-produits` à créer | **OUI** | Lit trois collections ; le bouton porte DEUX jeux (actes, tarifs des produits) choisis dans la fenêtre. Tarif des produits : prix d’achat sans marge (RG-02), mise à jour avec date d’effet. | DAF, admin, Direction |
| `cfg-types-piece` | CFG | typesPiece | pièce certifiante | aucun | **NON** | Types et numérotation des quatorze pièces : une collision de sigle se tranche à la main. | sans objet |
| `ged-archives` | GED | documents | pièces archivées | aucun | **NON** | Pièces de l’établissement avec empreinte et conservation : dépôt unitaire. | sans objet |
| `ged-bibliotheque` | GED | documents | pièces archivées | aucun | **NON** | Pièces de l’établissement avec empreinte et conservation : dépôt unitaire. | sans objet |
| `ged-workflow` | GED | documents | pièces archivées | aucun | **NON** | Pièces de l’établissement avec empreinte et conservation : dépôt unitaire. | sans objet |
| `imp-accueil` | IMP | lotsImportation | historique | existant | **existant** | Point central : historique et modèles ; supervision des lots (voir 7). | Tout détenteur d’un droit d’import (ses lots), DAF, admin (tous) |
| `imp-actes` | IMP | lotsImportation + cibles | écran de jeu | `actes` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-analyses` | IMP | lotsImportation + cibles | écran de jeu | `analyses` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-assureurs` | IMP | lotsImportation + cibles | écran de jeu | `assureurs` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-fournisseurs` | IMP | lotsImportation + cibles | écran de jeu | `fournisseurs` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-patients` | IMP | lotsImportation + cibles | écran de jeu | `patients` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-personnel` | IMP | lotsImportation + cibles | écran de jeu | `personnel` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-plan-comptable` | IMP | lotsImportation + cibles | écran de jeu | `plan-comptable` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-soldes-ouverture` | IMP | lotsImportation + cibles | écran de jeu | `soldes-ouverture` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `imp-souscripteurs` | IMP | lotsImportation + cibles | écran de jeu | `souscripteurs` | **existant** | Écran du jeu : conservé comme page de supervision ; le bouton des écrans métier ouvre la MÊME fenêtre. | voir 6.1 |
| `m1-antecedents` | M1 | patients (antécédents) | donnée clinique (RG-13) | aucun | **NON** | Donnée de santé : saisie par le soignant habilité, jamais importée en masse. | sans objet |
| `m1-constantes` | M1 | constantes | donnée clinique (RG-13) | aucun | **NON** | Donnée de santé : saisie par le soignant habilité, jamais importée en masse. | sans objet |
| `m1-contre-reference` | M1 | références | donnée clinique | aucun | **NON** | Fiche médicale liée à un patient. | sans objet |
| `m1-documents` | M1 | documentsPatient | donnée clinique (RG-13) | aucun | **NON** | Donnée de santé : saisie par le soignant habilité, jamais importée en masse. | sans objet |
| `m1-externe` | M1 | demandesAnalyses, demandesImagerie | pièce de circuit | aucun | **NON** | Demande qui fabrique facture et file : jamais en masse. | sans objet |
| `m1-patient-nouveau` | M1 | patients | formulaire | porté par `patients` | **voir ci-dessus** | Page de saisie d’un dossier : pas de bouton propre (la reprise se fait au répertoire). | Accueil |
| `m1-patients` | M1 | patients | donnée clinique administrative (RG-01, RG-13) | `patients` existant | **OUI, restreint** | Identité administrative seulement, jamais de dossier médical (jeu import.js:309). Code CNT jamais modifié (RG-01). | Accueil, agent administratif, DAF, admin |
| `m1-pieces` | M1 | pieces | pièce certifiante | aucun | **NON** | Pièce numérotée comme le registre papier, passe par la caisse. | sans objet |
| `m1-reference` | M1 | références | donnée clinique | aucun | **NON** | Fiche médicale liée à un patient. | sans objet |
| `m10-assurance-personnel` | M10 | patients, consultations | calculé | aucun | **sans objet** | Vue du dossier de l’agent, n’ouvre aucune saisie (vague 20). | sans objet |
| `m10-badges` | M10 | badges | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-badges-impression` | M10 | vue ou modèle | vue | aucun | **sans objet** | Vue, gabarit ou outil. | sans objet |
| `m10-badges-modeles` | M10 | vue ou modèle | vue | aucun | **sans objet** | Vue, gabarit ou outil. | sans objet |
| `m10-badges-verification` | M10 | vue ou modèle | vue | aucun | **sans objet** | Vue, gabarit ou outil. | sans objet |
| `m10-conges` | M10 | conges | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-contrats` | M10 | contrats | donnée de paie | à créer `contrats` (différé) | **NON recommandé** | Un contrat engage la paie et les dates : reprise par saisie, après la fiche personnel. | sans objet |
| `m10-employe-profil` | M10 | vue ou modèle | vue | aucun | **sans objet** | Vue, gabarit ou outil. | sans objet |
| `m10-evaluations` | M10 | evaluations | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-evenements` | M10 | evenements | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-fiches-poste` | M10 | fichesPoste | référentiel documentaire | aucun | **NON recommandé** | Texte long, validé par la Direction : 44 fiches se reprennent à la main, un import en masse n’apporte rien. | sans objet |
| `m10-missions` | M10 | missions | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-participations` | M10 | participations | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-personnel` | M10 | personnel | référentiel (paie, RG-13) | `personnel` existant | **OUI, restreint** | Jeu existant (import.js:245) ; la colonne Salaire de base est à REFUSER sans droit paie (voir 6.3). | DAF, admin |
| `m10-planning` | M10 | planning | registre opérationnel | aucun | **NON** | Planning validé : RG-11 calcule les primes depuis lui. | sans objet |
| `m10-presences` | M10 | presences | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-prestataires` | M10 | prestataires | référentiel | à créer `prestataires` | **OUI** | Référentiel plat (nom, IFU, spécialité, tarif d’acte) proche de `fournisseurs`. | DAF, admin |
| `m10-primes` | M10 | grillePrimes | référentiel daté | aucun | **NON** | Grille versionnée par date : modification derrière sa porte (NS 132). | sans objet |
| `m10-sanctions` | M10 | evaluations | registre RH / paie (RG-13) | aucun | **NON** | Registre de gestes datés ou donnée RH nominative : jamais en masse. | sans objet |
| `m10-securite-entretien` | M10 | vue ou modèle | vue | aucun | **sans objet** | Vue, gabarit ou outil. | sans objet |
| `m11-avances` | M11 | avances | donnée de paie (RG-13) | aucun | **NON (à REFUSER)** | Paie : montants nominatifs et retenues sur bulletin. Reprise des prêts à l’ouverture : saisie individuelle par la DAF. | sans objet |
| `m11-bulletins` | M11 | bulletins | donnée de paie (RG-13) | aucun | **NON (à REFUSER)** | Paie : montants nominatifs et retenues sur bulletin. Reprise des prêts à l’ouverture : saisie individuelle par la DAF. | sans objet |
| `m11-calcul` | M11 | calculé | calculé | aucun | **sans objet** | Calcul depuis personnel et barèmes. | sans objet |
| `m11-cotisations` | M11 | calculé | calculé | aucun | **sans objet** | Calcul depuis personnel et barèmes. | sans objet |
| `m11-heures-sup` | M11 | heuresSup | donnée de paie (RG-13) | aucun | **NON (à REFUSER)** | Paie : montants nominatifs et retenues sur bulletin. Reprise des prêts à l’ouverture : saisie individuelle par la DAF. | sans objet |
| `m11-ortb` | M11 | calculé | calculé | aucun | **sans objet** | Calcul depuis personnel et barèmes. | sans objet |
| `m11-prets-etudes` | M11 | prets | donnée de paie (RG-13) | aucun | **NON (à REFUSER)** | Paie : montants nominatifs et retenues sur bulletin. Reprise des prêts à l’ouverture : saisie individuelle par la DAF. | sans objet |
| `m12-analytique` | M12 | écritures, factures | calculé | aucun | **sans objet** | Lecture calculée du journal ; `m12-echeances` lit le calendrier fiscal dérivé de `D.CALENDRIER_FISCAL`. | sans objet |
| `m12-balance` | M12 | écritures, factures | calculé | aucun | **sans objet** | Lecture calculée du journal ; `m12-echeances` lit le calendrier fiscal dérivé de `D.CALENDRIER_FISCAL`. | sans objet |
| `m12-banques` | M12 | banques, rapprochements | référentiel + registre | à créer `comptes-bancaires` (différé) | **NON recommandé** | Un numéro de compte bancaire est une donnée sensible ; très peu de lignes : saisie. | sans objet |
| `m12-baseline-2025` | M12 | écritures, factures | calculé | aucun | **sans objet** | Lecture calculée du journal ; `m12-echeances` lit le calendrier fiscal dérivé de `D.CALENDRIER_FISCAL`. | sans objet |
| `m12-budgets` | M12 | budgets | donnée de pilotage | à créer `budgets` | **OUI, restreint** | Prévu par centre, nature et exercice : exercice clos refusé. | Comptable, DAF, admin |
| `m12-cloture` | M12 | exercices | pièce certifiante | aucun | **NON** | Deux gestes humains, empreinte SHA-256. | sans objet |
| `m12-depenses` | M12 | ecritures, personnel | pièce comptable | aucun | **NON** | Dépense multi-lignes avec justificatif : saisie à la caisse ou au comptable. | sans objet |
| `m12-echeances` | M12 | écritures, factures | calculé | aucun | **sans objet** | Lecture calculée du journal ; `m12-echeances` lit le calendrier fiscal dérivé de `D.CALENDRIER_FISCAL`. | sans objet |
| `m12-ecritures` | M12 | ecritures | pièce comptable (RG-10) | `soldes-ouverture` seul | **NON** | Écriture courante : naît d’une opération (encaissement, paie, dépense) ou de la saisie du comptable avec pièce équilibrée. Seul le report d’ouverture s’importe. | sans objet |
| `m12-grand-livre` | M12 | écritures, factures | calculé | aucun | **sans objet** | Lecture calculée du journal ; `m12-echeances` lit le calendrier fiscal dérivé de `D.CALENDRIER_FISCAL`. | sans objet |
| `m12-immobilisations` | M12 | immobilisations | registre comptable | à créer `immobilisations` | **OUI, restreint** | Reprise du parc : date d’acquisition, valeur, durée, compte SYSCOHADA ; amortissement semestriel calculé, jamais importé. Compte inconnu refusé. | Comptable, DAF, admin |
| `m12-journaux` | M12 | écritures, factures | calculé | aucun | **sans objet** | Lecture calculée du journal ; `m12-echeances` lit le calendrier fiscal dérivé de `D.CALENDRIER_FISCAL`. | sans objet |
| `m12-plan-comptable` | M12 | comptes | référentiel | `plan-comptable` existant | **OUI** | Jeu existant (import.js:631). Le comptable est le détenteur naturel. | Comptable, DAF, admin |
| `m13-ambulance` | M13 | ambulance | registre opérationnel | aucun | **NON** | Intervention : geste du jour avec patient. | sans objet |
| `m13-courriers` | M13 | courriers | registre opérationnel | à créer `courriers` (reprise du registre papier) | **OUI, restreint** | Courriers départ/arrivée : reprise du cahier (date, sens, objet, correspondant). Numéros d’ordre jamais réécrits ; pièce numérisée jamais importée par fichier. | Agent administratif, DAF, admin |
| `m13-evenements` | M13 | evenementsEtablissement | registre / modèle | aucun | **NON** | Document de gestion saisi par son auteur. | sans objet |
| `m13-maintenance` | M13 | materiel | référentiel | à créer `parc-technique` (différé) | **NON recommandé** | Marque et numéro de série manquent physiquement (vague 51) : un fichier ne les crée pas. | sans objet |
| `m13-plan-annuel` | M13 | planAnnuel | registre / modèle | aucun | **NON** | Document de gestion saisi par son auteur. | sans objet |
| `m13-repertoire-ambulances` | M13 | ambulances | référentiel d’urgence | aucun | **NON** | Aucun numéro d’urgence inventé (vague 30) : fiche vérifiée à la main, datée. | sans objet |
| `m13-reunions` | M13 | reunions | registre / modèle | aucun | **NON** | Document de gestion saisi par son auteur. | sans objet |
| `m14-audit` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m14-roles` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m14-sauvegardes` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m14-securite-utilisateurs` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m14-sessions` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m14-soignants` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m14-taches` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m14-utilisateurs` | M14 | utilisateurs, rbac, audit | sécurité | aucun | **NON (à REFUSER)** | Comptes, droits, sessions, journal : aucun import (RG-12, RG-13). `m14-sauvegardes` porte déjà « Importer par module » (JSON), non porté au poste (E608). | sans objet |
| `m2-affichage` | M2 | vue ou file | vue / file | aucun | **sans objet** | File ou vue du jour. | sans objet |
| `m2-agenda-medecin` | M2 | vue ou file | vue / file | aucun | **sans objet** | File ou vue du jour. | sans objet |
| `m2-consultation-fiche` | M2 | consultations | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-consultations` | M2 | consultations | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-dashboard-imagerie` | M2 | demandesImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-domicile` | M2 | consultations | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-dossier-consultation-nouveau` | M2 | dossiersConsultation | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-dossiers-consultation` | M2 | dossiersConsultation | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-file-attente` | M2 | vue ou file | vue / file | aucun | **sans objet** | File ou vue du jour. | sans objet |
| `m2-imagerie` | M2 | demandesImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-imagerie-cr` | M2 | crImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-imagerie-demandes` | M2 | demandesImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-imagerie-irm` | M2 | demandesImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-imagerie-mammographie` | M2 | demandesImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-imagerie-radiographie` | M2 | demandesImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-imagerie-scanner` | M2 | demandesImagerie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-ordonnance-nouvelle` | M2 | ordonnances | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-ordonnances` | M2 | ordonnances | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-pathologies` | M2 | pathologies | référentiel (proposition validée) | à créer `pathologies` (différé) | **NON recommandé** | 54 entrées arrêtées par les médecins ; un tableau de morbidité se gère à la main. | sans objet |
| `m2-prescriptions` | M2 | prescriptions | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m2-registre-appels` | M2 | vue ou file | vue / file | aucun | **sans objet** | File ou vue du jour. | sans objet |
| `m2-rendezvous` | M2 | consultations | registre opérationnel | aucun | **NON** | Rendez-vous pris à l’accueil devant la personne. | sans objet |
| `m2-salle-soins` | M2 | administrations | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Donnée de santé nominative, circuit de prescription et de caisse : jamais en masse. | sans objet |
| `m3-administrations` | M3 | administrations | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-admissions` | M3 | admissions | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-bloc-checklist` | M3 | checklistsBloc | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-bloc-cro` | M3 | crOperatoires | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-bons-pansements` | M3 | ordonnances | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-chambres` | M3 | chambres | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-cpa` | M3 | cpa | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-cr-anesthesie` | M3 | crAnesthesie | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-demande-examen` | M3 | demandesAnalyses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-feuille-temperature` | M3 | releves | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-glasgow` | M3 | scoresGlasgow | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-observation` | M3 | observations | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-rapport` | M3 | rapportsMedicaux | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-soins` | M3 | soins | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-sortie-avis-medical` | M3 | sortiesAvisMedical | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-sorties` | M3 | admissions | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-surveillance` | M3 | releves | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-transfusion` | M3 | surveillancesTransfusion | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m3-visites-patients` | M3 | visitesHospi | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Hospitalisation et bloc : un lit ne porte qu’une admission active, sorties soumises à RG-06/07/08. | sans objet |
| `m4-accouchements` | M4 | accouchements | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-comptes-rendus` | M4 | crMaternite | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-cpn` | M4 | grossesses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-cpon` | M4 | cpon | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-deces` | M4 | deces | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-dossier-bebe` | M4 | naissances | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-dossier-obstetrical` | M4 | dossiersObstetricaux | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-dossier-obstetrical-nouveau` | M4 | dossiersObstetricaux | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-maternite` | M4 | suiviMaternite | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-naissances` | M4 | naissances | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-planification` | M4 | planificationFamiliale | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-ptme` | M4 | ptme | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-soins-curatifs` | M4 | soinsCuratifsMaternite | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m4-sonu` | M4 | registreSONU | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Maternité : cahier de la parturiente, PTME et décès sont des données de santé ou d’état civil. | sans objet |
| `m5-catalogue` | M5 | analyses | catalogue | `analyses` existant (écrit une AUTRE collection) | **OUI, restreint** | L’écran lit/écrit `analyses` (tarif, tarifProvisoire) ; le jeu `analyses` écrit `examensLabo` (modèle de résultat). À réconcilier : Q2. | Biologiste, DAF, admin |
| `m5-demandes` | M5 | demandesAnalyses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Résultats et demandes d’analyses : deux verrous de validation, rectification numérotée. | sans objet |
| `m5-demandes-hospitalisation` | M5 | demandesAnalyses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Résultats et demandes d’analyses : deux verrous de validation, rectification numérotée. | sans objet |
| `m5-demandes-maternite` | M5 | demandesAnalyses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Résultats et demandes d’analyses : deux verrous de validation, rectification numérotée. | sans objet |
| `m5-impression-resultats` | M5 | demandesAnalyses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Résultats et demandes d’analyses : deux verrous de validation, rectification numérotée. | sans objet |
| `m5-prelevement` | M5 | demandesAnalyses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Résultats et demandes d’analyses : deux verrous de validation, rectification numérotée. | sans objet |
| `m5-reactifs` | M5 | produits | calculé / vue | `grand-stock` (catégorie réactif) | **sans objet** | Les réactifs entrent par le Grand Stock (catégorie `reactif`, lot et péremption obligatoires). | Stock, biologiste |
| `m5-resultats` | M5 | demandesAnalyses | donnée clinique (RG-13) | aucun | **NON (à REFUSER)** | Résultats et demandes d’analyses : deux verrous de validation, rectification numérotée. | sans objet |
| `m5-unites` | M5 | unitesLabo | référentiel | à créer `unites-labo` | **OUI** | Symboles d’unité du laboratoire, plat et court. | Biologiste, admin |
| `m5-valeurs-reference` | M5 | variablesLabo, plagesReactif | référentiel (valeurs de référence) | à créer `variables-labo` (différé) | **OUI, restreint** | Bornes validées par le biologiste, jamais prérenseignées ; plages par lot versionnées par date d’entrée en service. | Biologiste |
| `m6-alertes` | M6 | calculé | calculé | aucun | **sans objet** | Lecture calculée depuis les registres (alertes de seuil, points de stock et de ventes, recettes). | sans objet |
| `m6-dispensation` | M6 | dispensations | pièce certifiante (RG-03) | aucun | **NON** | Toute délivrance naît d’une ordonnance passée en caisse (vague 53). | sans objet |
| `m6-etiquetage` | M6 | emplacements | référentiel | à créer `emplacements` | **OUI** | Référentiel d’emplacements (code, zone, capacité, température) : liste fermée pour éviter « Rayon A2 » et « rayon a-2 » (CLAUDE.md, vague 36). | Stock, DAF, admin |
| `m6-import-grand-stock` | M6 | produits, lots, mouvements | existant | `grand-stock` | **existant** | Écran du jeu Grand Stock (nav.js:368). Reçoit déjà ses commandes ; il devient un simple hôte du bouton commun. | Stock, DAF, admin |
| `m6-inventaire` | M6 | inventaires | registre opérationnel | à créer `inventaire-comptage` (proposition) | **OUI, restreint** | Comptages d’UN magasin nommé (la feuille de 200 articles) : le jeu produit la feuille d’inventaire, la régularisation reste un geste humain avec écart nommé. | Stock, DAF, admin |
| `m6-inventaire-feuille` | M6 | inventaires | formulaire | porté par `inventaire-comptage` | **voir ci-dessus** | Même jeu : le bouton vit sur la feuille, qui est la page de saisie. | Stock |
| `m6-lots` | M6 | lots | registre opérationnel | couvert par `grand-stock` (une ligne par lot) | **NON recommandé seul** | Un lot sans mouvement d’entrée déséquilibre produits et lots (RG-03, RG-05). Les lots entrent avec leur stock (Grand Stock) ou par réception (M7). | sans objet |
| `m6-mouvements` | M6 | mouvements | journal append-only | aucun | **NON** | Journal de preuve RG-03 : un mouvement s’écrit par son geste (transfert, perte, dispensation, réception), jamais en masse. | sans objet |
| `m6-pertes` | M6 | mouvements, produits | registre opérationnel | aucun | **NON** | Une perte est un mouvement signé par celui qui la constate (CLAUDE.md, vague 28 : « une perte se déclare »). | sans objet |
| `m6-pharmacie-externe` | M6 | dispensations | registre opérationnel | aucun | **NON** | Même motif que la dispensation. | sans objet |
| `m6-pharmacie-interne` | M6 | dispensations | registre opérationnel | aucun | **NON** | Même motif que la dispensation. | sans objet |
| `m6-point-stock` | M6 | calculé | calculé | aucun | **sans objet** | Lecture calculée depuis les registres (alertes de seuil, points de stock et de ventes, recettes). | sans objet |
| `m6-point-ventes` | M6 | calculé | calculé | aucun | **sans objet** | Lecture calculée depuis les registres (alertes de seuil, points de stock et de ventes, recettes). | sans objet |
| `m6-produits` | M6 | produits | catalogue | à créer `produits-referentiel` (le jeu `grand-stock` écrit aussi des produits) | **OUI** | Référentiel des articles sans quantités : code, désignation, catégorie, unité, prix d’achat, seuil. Les quantités restent au Grand Stock. Famille R mère seule (pont_activite.dart:45). | Stock, DAF, admin |
| `m6-stock-detail` | M6 | produits (stockDetail) | registre opérationnel (compteurs) | à créer `stock-detail-initial` (proposition) | **OUI, restreint** | Situation initiale de la pharmacie d’urgence ; le détail naît d’ordinaire d’un transfert. Entrée au détail avec justificatif d’import, tant qu’aucun mouvement. À confirmer : Q6. | Stock, DAF, admin |
| `m6-stock-gros` | M6 | produits (stockGros), lots, mouvements | registre opérationnel (compteurs) | `grand-stock` existant | **OUI, restreint** | Situation INITIALE seulement (jeu `grand-stock`, import.js:124). Refusé pour un article qui a déjà un mouvement (dépendance, import.js:237) : un recomptage passe par l’inventaire, jamais par un import qui écraserait RG-03. | Stock, DAF, admin |
| `m6-transferts` | M6 | transferts, mouvements, produits | registre opérationnel (bon + mouvements) | à créer `transfert-lignes` | **OUI, restreint** | Importe les LIGNES d’UN bon neuf (une feuille = un bon) : le bon n’est écrit que si chaque ligne passe RG-03, et il écrit ses deux mouvements symétriques comme à l’écran (m6-stock.js:1018 à 1084). Jamais l’historique de bons passés : il déplacerait le stock sans le dire. | Stock, DAF, admin |
| `m7-besoins` | M7 | besoins | pièce de circuit (RG-04) | aucun | **NON** | Bon d’expression de besoins : circuit de validation DAF, quantité demandée ≠ accordée. | sans objet |
| `m7-commandes` | M7 | commandes | pièce de circuit (RG-04) | aucun | **NON** | Une commande est validée par la DAF avant transmission (RG-04). | sans objet |
| `m7-ecarts` | M7 | livraisons | vue | aucun | **sans objet** | Vue des écarts de livraison. | sans objet |
| `m7-factures-fournisseurs` | M7 | facturesFournisseurs, pvReceptions | pièce comptable | aucun | **NON recommandé** | Une facture fournisseur crée une dette (BFR) et une écriture. La reprise des dettes à l’ouverture passe par les soldes d’ouverture, compte 401 ligne à ligne par tiers. | sans objet |
| `m7-fournisseurs` | M7 | fournisseurs | référentiel | `fournisseurs` existant | **OUI** | Jeu existant (import.js:507) ; bouton à poser sur l’écran. | Stock, DAF, comptable, admin |
| `m7-livraisons` | M7 | livraisons | pièce | aucun | **NON** | Bon de livraison : geste du magasinier à la réception. | sans objet |
| `m7-pv-reception-consommables` | M7 | pvReceptions | pièce signée | aucun | **NON** | Trois signatures : pièce signée jamais importée. | sans objet |
| `m7-pv-reception-reactifs` | M7 | pvReceptions | pièce signée | aucun | **NON** | Idem, avec chaîne du froid. | sans objet |
| `m7-receptions` | M7 | commandes, livraisons | pièce | aucun | **NON** | Contrôle de réception : geste de terrain. | sans objet |
| `m8-caisse` | M8 | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-facturation` | M8 | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-facture-avoir` | M8 | avoirs | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-factures` | M8 | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-operations` | M8 | inventairesCaisse | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-paiements` | M8 | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-proforma` | M8 | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-recettes` | M8 | calculé | calculé | aucun | **sans objet** | Lecture calculée depuis les registres (alertes de seuil, points de stock et de ventes, recettes). | sans objet |
| `m8-reliquats` | M8 | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m8-remboursements` | M8 | remboursements | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `m9-assures` | M9 | patients (couverture) | donnée administrative datée | à créer `couvertures-assurance` | **OUI** | Couverture DATÉE (couverturesAssurance, vague 60) : motif et date d’effet obligatoires, jamais écraser. Ne passe pas par le jeu patients. | DAF, comptable, admin |
| `m9-compagnies` | M9 | assureurs | référentiel | `assureurs` existant | **OUI** | Jeu existant (import.js:549). | DAF, comptable, admin |
| `m9-conventions` | M9 | garanties | référentiel daté | à créer `garanties` | **OUI, restreint** | Grille de garanties par souscripteur (taux, plafond, catégorie) : jeu `souscripteurs` la déclare « ne s’importe pas » (import.js:589). À créer avec versionnement par date. | DAF, comptable, admin |
| `m9-creances` | M9 | factures | calculé | aucun | **sans objet** | Créances calculées depuis les factures. | sans objet |
| `m9-facture-mere` | M9 | factures | pièce | aucun | **NON** | Facture mère : trois totaux recoupés, correction par avoir. | sans objet |
| `m9-factures-assureur` | M9 | souscripteurs | calculé | aucun | **sans objet** | Deux vues du même mois, calculées. | sans objet |
| `m9-historique` | M9 | souscripteurs | calculé | aucun | **sans objet** | Vue calculée. | sans objet |
| `m9-prises-en-charge` | M9 | factures | pièce | aucun | **NON** | Accord de prise en charge : geste de la caisse/DAF avec carte valide (RG-09). | sans objet |
| `m9-relances` | M9 | relances | registre opérationnel | aucun | **NON** | Une relance est un acte daté et signé. | sans objet |
| `mecef-avoirs` | MECEF | avoirs | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `mecef-config` | MECEF | paramètres MECeF | configuration fiscale | aucun | **NON** | Paramètre fiscal : validation DAF/Direction, jamais en masse. | sans objet |
| `mecef-factures` | MECEF | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `mecef-journal` | MECEF | journal fiscal | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `mecef-transmission` | MECEF | factures | pièce certifiée (MECeF, numérotation) | aucun | **NON** | Pièce émise : elle ne se réécrit jamais (vague 42), le numéro fiscal vient du boîtier, et un import fabriquerait des recettes sans acte à l’origine. Les encours d’ouverture entrent par les soldes d’ouverture (comptes 411). | sans objet |
| `rapports-direction` | RAP | états | calculé | aucun | **sans objet** | États imprimés. | sans objet |
| `rapports-generateur` | RAP | états | calculé | aucun | **sans objet** | États imprimés. | sans objet |
| `rapports-historique` | RAP | états | calculé | aucun | **sans objet** | États imprimés. | sans objet |
| `m12-ouverture` | M12 | ecritures (journal AN) | pièce comptable | `soldes-ouverture` existant | **OUI, restreint** | Jeu existant (import.js:660) : une pièce AN en brouillon, équilibrée RG-10. Écran d’hôte à confirmer (`m12-ouverture` existe au manifeste, vague 57). | Comptable, DAF, admin |

### 3.3 Synthèse

Sur les 219 écrans classés : **26 OUI ou OUI restreint** (jeu existant ou à créer, écrans hôtes du bouton), **11 écrans de jeu existants** (les neuf `imp-*`, `imp-accueil` et `m6-import-grand-stock`), **141 NON** dont **68 marqués « à REFUSER »** (clinique, paie, sécurité), **8 NON recommandé**, **31 sans objet** (calculés, vues, outils), et 2 renvois à un jeu porté par un autre écran.

Les jeux d'import à constituer se comptent par **jeu**, non par écran :

* **10 jeux existants** (maquette et poste) : `grand-stock`, `personnel`, `patients`, `actes`, `analyses`, `fournisseurs`, `assureurs`, `souscripteurs`, `plan-comptable`, `soldes-ouverture` ;
* **17 jeux à créer** : `catalogue-tarifaire`, `tarifs-produits`, `produits-referentiel`, `stock-detail-initial`, `transfert-lignes`, `inventaire-comptage`, `emplacements`, `prestataires`, `couvertures-assurance`, `garanties`, `centres-couts`, `immobilisations`, `budgets`, `courriers`, `natures-facture`, `catalogue-imagerie`, `unites-labo` ;
* **1 jeu différé** : `variables-labo` (valeurs de référence : le biologiste les arrête, plages par lot par date).

Écrans **non recommandés** différés (motif au tableau) : lots seuls, factures fournisseurs, banques, contrats, fiches de poste, organisation, parc technique, pathologies.

---

## 4. Fiches de jeu : clé, colonnes, contrôles, doublon, effets, synchronisation

Légende des familles de fusion : **R** = référentiel écrit par la mère seule (un fileul le demande, voir 8.3) ; **A** = fiche descriptive (fusion par champ) ; **B** = journal append-only ; **D** = agrégat à invariant rejoué et vérifié par la mère. Pour un jeu à créer, les **colonnes** sont une **proposition à valider** : elles ne se déduisent que des champs réels de la collection (dictionnaire `docs/architecture/DICTIONNAIRE-DONNEES.md`) et sont à reconfirmer au lot qui construit le jeu. Aucune valeur par défaut n'est inventée : une colonne vide est écrite vide.

| Jeu | Clé naturelle (unicité) | Obligatoires | Jamais importés | Contrôles de vérification | Doublon | Effets de bord | Synchronisation |
|---|---|---|---|---|---|---|---|
| `grand-stock` (existant) | code + lot | code, désignation, catégorie, quantité | prix de vente par défaut inventé, mouvement postérieur | RG-03 quantité négative refusée ; RG-05 lot et péremption obligatoires pour médicament et réactif ; article incohérent ; périmé : avertissement ; prix absent : « à valoriser », jamais 0 inventé | refuser (article existant) | produits, lots, mouvements `entree` justifiés par le lot d'import (`import.js:213 à 229`) | produits : R mère seule ; compteurs par variations ; lots et mouvements : règle propre (D) |
| `produits-referentiel` | code article | code, désignation, catégorie, unité | quantités, lots (renvoi à `grand-stock`) | catégorie dans `D.CATEGORIES_PRODUIT` ; prix d'achat entier ≥ 0 ; RG-02 : pas de marge, pas de prix de vente libre pour un médicament ; seuil vide : article signalé « sans seuil », jamais 0 | refuser ; option `ignorer les existants` (6.4) | aucune écriture de stock ni de comptabilité | R, mère seule |
| `tarifs-produits` | code article + date d'effet | code, prix d'achat, date d'effet | quantités | article connu ; **nouvelle version datée** (ancien prix conservé, règle de paramétrage du 09/11) ; une pièce déjà émise sous l'ancien prix garde son prix ; prix absent : un tiret n'est pas un zéro (`manquant`) | nouvelle version datée, jamais écrasement | cump recalculé par le moteur à la réception, pas à l'import (**non vérifié** : le lien exact avec `S.valeurUnitaire`) | R, mère seule |
| `stock-detail-initial` | code + lot | code, quantité | tout article qui a déjà un mouvement | RG-03 ; article connu ; quantité ≥ 0 ; refusé si le magasin gros du même article ne peut pas être cohérent (somme gros + détail = stock) | refuser | `stockDetail` et un mouvement `entree` au détail justifié par l'import | compteurs par variations (A/D) |
| `transfert-lignes` | une feuille = un bon neuf ; clé de ligne : code article + lot | code, quantité | historique de bons passés | RG-03 **ligne par ligne** en nommant l'article ; disponible tenant compte des lignes déjà posées sur le bon (`m6-stock.js:856`) ; lot FEFO ; unité de destination | refuser une ligne dupliquée dans le fichier | un bon numéroté, deux mouvements symétriques par ligne, stocks gros et détail ; le bon est numéroté **après** la vérification | D : la mère rejoue (`mouvements`, `lots`) |
| `inventaire-comptage` | magasin nommé + code article | magasin, code, quantité comptée | régularisation (reste un geste humain) | magasin parmi gros et détail seulement ; article connu ; écart calculé depuis le stock théorique du magasin choisi | refuser | feuille d'inventaire créée ; stocks inchangés tant que non régularisée | D |
| `emplacements` | code | code, libellé | | doublon de code ; capacité ≥ 0 ; liste fermée | refuser | aucune | A |
| `fournisseurs` (existant) | code | code, raison sociale | habilitation (`habilite` écrit à faux) | IFU 13 chiffres ; IFU absent : avertissement | refuser | aucune | R |
| `catalogue-tarifaire` | code | code, désignation, famille, prix non assuré, prix assuré (montant, NC ou tiret) | | **un tiret n'est ni 0 ni NC** (`manquant` bloque la facturation) ; NC interdit en colonne non assuré ; famille dans `D.FAMILLES_TARIF` ; inversion de colonnes documentée (pansement 9 000 / 6 000, soin intraveineux 1 000 / 800) : le fichier fait foi et un écart d'orientation est un avertissement, jamais corrigé | nouvelle version datée (jamais écraser un tarif en vigueur) | aucune écriture comptable | R, mère seule |
| `actes` (existant) | code | code, libellé, secteur, deux prix | | idem ; secteur parmi les six arrêtés | refuser (le tarif en vigueur se modifie à l'écran, versionné) | aucune | R |
| `analyses` (existant) | code | code, désignation, section | variables, unités, bornes (le biologiste) | statut « proposition » : examen sans variables | refuser | aucune | R |
| `unites-labo` | symbole | symbole, libellé, domaine | | symbole tel que le laboratoire l'écrit (G/l, T/l, g/dl) | refuser | aucune | R |
| `catalogue-imagerie` | code examen | code, libellé, modalité | variables de compte rendu | modalité parmi les cinq ; examens créés `aValider` | refuser | aucune | R |
| `assureurs` (existant) | code | code, raison sociale | | e-mail ; convention vide : avertissement | refuser | aucune | R |
| `souscripteurs` (existant) | n° de police | nom, police, code compagnie | grille de garanties | compagnie connue ; période non inversée | refuser | aucune | R |
| `garanties` | souscripteur + catégorie + date d'effet | police, catégorie, taux, plafond | | souscripteur connu ; taux 0 à 100 ; plafond ≥ 0 ; **versionnement par date** (une facture émise garde son taux) | nouvelle version datée | aucune | R |
| `couvertures-assurance` | patient (code CNT) + date d'effet | code patient, compagnie, police, date d'effet, motif | modification d'un code patient (RG-01) | patient et compagnie connus ; motif et date obligatoires ; `debut: null` refusé (une date d'effet qu'on n'invente pas) | nouvelle couverture datée, l'ancienne se clôt | aucune écriture de facture | A |
| `patients` (existant) | code CNT, sinon identité | nom, prénom, sexe, naissance ou âge | dossier médical, antécédents, constantes ; **code existant jamais modifié (RG-01)** | doublon probable (nom, prénom, naissance ou téléphone) ; date future ; assuré sans police : avertissement ; code au format `CNT/n/AA` | refuser, **sans option « ignorer »** (un second dossier est une faute) | codes attribués dans l'ordre par année (`import.js:366 à 380`) | A (fusion par champ, `codeEnDoublon` marqué) |
| `personnel` (existant) | matricule ; identité | matricule, nom, prénom, sexe, fonction, poste, service | salaire hors droit paie, échelon (voir 5) | service au référentiel ; date d'embauche non future ; CNSS 9 chiffres | refuser | aucune ; `salaireBase` absent : « Non renseignée » à l'écran | R |
| `prestataires` | IFU ou nom | nom, spécialité | | IFU 13 chiffres ; tarif d'acte ≥ 0 | refuser | aucune | R |
| `plan-comptable` (existant) | n° de compte | numéro (4 à 8 chiffres), libellé | classe (déduite) | classe 1 à 9 ; journal connu | refuser | aucune | R |
| `soldes-ouverture` (existant) | une pièce AN par exercice | date, compte, débit ou crédit | classes 6 à 9 ; reports d'un exercice déjà ouvert | RG-10 : débit = crédit sur le lot (`import.js:697`) ; une seule date ; compte inconnu refusé ; `A_NOUVEAU_EXISTANT` ; exercice clos refusé par le moteur de l'exercice | refuser | une pièce **en brouillon**, journal AN ; validation humaine ensuite | D (écritures) : la mère refait RG-10 |
| `centres-couts` | code | code, libellé, type | | le code EST l'imputation portée par les écritures | refuser | aucune | R |
| `natures-facture` | code | code, libellé, secteur | | secteur parmi les six | refuser | aucune | R |
| `immobilisations` | référence | désignation, date d'acquisition, valeur, durée, compte | amortissements (calculés), cessions | compte SYSCOHADA connu ; valeur entière > 0 ; date non future ; bien déjà cédé : refusé | refuser | aucune écriture : l'amortissement se calcule | A |
| `budgets` | exercice + centre + nature | exercice, centre, nature, prévu | | exercice ouvert ; centre connu | refuser | aucune | A |
| `courriers` | référence ou (date, sens, objet) | date, sens, objet | pièce numérisée, traitement, accusé | sens parmi départ et arrivée ; **numéros jamais réécrits** | refuser | aucune | B (ajout seul) |
| `variables-labo` (différé) | examen + code variable | | bornes non validées | bornes jamais prérenseignées ; `aValider` | refuser | aucune | R |

Observations de méthode :

* **Clé d'unicité** : toujours **déclarée par le jeu** (`cle`, `existe`) et jamais devinée du fichier, comme l'existant (`import.js:782 à 789`).
* **Comportement en cas de doublon** : trois modes **déclarés par le jeu**, jamais choisis librement par l'agent : `refuser` (défaut, existant), `ignorer les existants` (avertissement nommé, ligne par ligne), `nouvelle version datée` (tarifs et garanties seulement : colonne `Date d'effet` obligatoire, aucune version ancienne retirée). `mettre à jour en place` n'existe pas : l'import ne modifie **jamais** une fiche tenue (`gesteExiste`, `import.js:156, 438`).
* **Archivage jamais suppression (RG-14)** : un lot s'annule par archivage de ce qu'il a écrit (`import.js:918`), jamais par suppression ; l'atomicité en cours de lot retire seulement ce qui vient d'être posé dans le même geste (`import.js:892`, fiches jamais vues d'un autre écran).

---

## 5. Données sensibles : refuser ou restreindre, même avec le droit d'import

Principe (RG-13) : **avoir le droit d'importer un jeu n'est pas avoir le droit de lire ce qu'il contient.** Le bouton n'ouvre donc jamais de porte clinique, de paie ou de sécurité. Trois niveaux de sensibilité, déclarés par jeu au manifeste (section 7) :

| Niveau | Jeux | Règle |
|---|---|---|
| **courante** | catalogues, référentiels de produits, tarifs, plan comptable, fournisseurs, compagnies, emplacements, natures, centres | Import ouvert aux détenteurs du droit ; historique des lots visible des détenteurs du jeu. |
| **restreinte** | `patients`, `personnel`, `couvertures-assurance`, `soldes-ouverture`, `immobilisations`, `budgets`, `stock-detail-initial`, `transfert-lignes`, `inventaire-comptage` | Import réservé aux profils nommés (7.5) ; **les valeurs de cellule ne sont pas recopiées dans l'historique** (masquées au constat, 5.3) ; lots visibles du seul auteur, de la DAF et de l'administrateur. |
| **refusée** | tout ce qui est clinique, de paie nominative, de pièce émise ou de sécurité | Aucun jeu, aucun bouton : les 68 écrans « à REFUSER » du tableau 3.2. |

### 5.1 Refusés

* **Clinique** (M1 antécédents, constantes, documents ; M2 consultations, dossiers, ordonnances, prescriptions, imagerie ; M3 ; M4 ; M5 demandes et résultats) : donnée de santé nominative, soumise aux deux verrous de validation du laboratoire, à la rectification numérotée, à l'habilitation par fonction (RG-13). Un fichier n'a ni signataire ni habilitation.
* **Paie nominative** (bulletins, avances, prêts, heures supplémentaires) : montants personnels et retenues sur bulletin ; la reprise se fait à la main, par la DAF, individu par individu (RG-13).
* **Pièces émises ou certifiées** (factures, avoirs, MECeF, certificats, PV signés, clôtures) : numérotation certifiée, une pièce émise ne se réécrit jamais ; un import créerait des recettes sans acte à l'origine.
* **Sécurité** (comptes, rôles, sessions, journal d'audit, sauvegardes) : RG-12 (aucune action anonyme) et RG-13. L'écran `m14-sauvegardes` offre déjà « Importer par module » en JSON (`m14-securite.js:2155`), non porté au poste (E608) ; il reste hors de ce chantier.

### 5.2 Restreints

* **`patients`** : identité administrative seulement (CDCT 4.3), jamais de dossier médical (`import.js:312`) ; reçu par accueil, agent administratif, DAF, administrateur. Le champ **groupe sanguin** est à arbitrer (Q9).
* **`personnel`** : la colonne **Salaire de base** est une donnée de paie. Elle n'est **dans le modèle téléchargé et acceptée au fichier que pour un profil qui détient la capacité paie** (DAF, administrateur). Pour un autre détenteur du jeu, la colonne est absente du modèle et un fichier qui la porte est refusé en la nommant.
* **`soldes-ouverture`** : une pièce engage l'exercice ; brouillon, validation humaine ensuite. Le comptable la prépare, la DAF ou l'administrateur la valide ; la Direction lit.
* **Jeux de stock en effet** (`transfert-lignes`, `stock-detail-initial`, `inventaire-comptage`) : ils écrivent des mouvements ; chaque effet est celui de l'écran correspondant, RG-03 contrôlé.

### 5.3 Correctif préalable : ne plus recopier les valeurs sensibles

`consigner` stocke jusqu'à 100 constats avec la valeur de la cellule (`import.js:861`) et `rapport` la reporte (`import.js:998`). Pour un jeu **restreint**, le constat porte la **colonne, le code et le geste, jamais la valeur**, et le rapport téléchargé est réservé à l'auteur du lot. Ce correctif est **un prérequis** de l'ouverture du module aux autres postes (lot L0).

---

## 6. Modèle d'interaction commun

### 6.1 Une fabrique unique, deux entrées

**`K.importer(jeuId, opts)`** (nom proposé) est la **seule** fabrique du bouton « Importer les données » et de sa fenêtre en trois temps. Elle vit au **kit** (`_kit.js`), comme `K.commande`, et se branche écran par écran sans copie :

* dans `K.crud` : une clé de configuration `importer: 'grand-stock'` ou `importer: ['actes', 'tarifs-produits']` ajoute la commande à la barre de l'écran (la liste `actions` du tableau est construite à `_kit.js:555`, absente sans droit d'écriture) ;
* dans un écran à la main ou une page `K.pageFormulaire` : `K.importer('transfert-lignes')` renvoie la commande, ou `null` ;
* dans `K.actionsLigne` : sans objet (l'import n'est pas un geste de ligne).

Le **bouton est ABSENT, jamais grisé**, sans le droit d'import du jeu : la commande est déclarée comme telle (`K.commande`, `_kit.js:176 à 193`) et résout son droit sur le **jeu**, pas sur l'écran (7.2). Deux jeux sur le même écran (`cfg-tarifs`) : un seul bouton « Importer les données » dont la première étape propose les jeux que le profil détient.

### 6.2 La fenêtre en trois temps

Le contenu de l'écran de jeu actuel (`ecranJeu`, `import.js:1081 à 1247`) devient une **modale large** produite par la même fabrique (et reste la page de l'écran `imp-<jeu>`) :

1. **Modèle** : « Télécharger le modèle (.xlsx) » et « Modèle CSV » (`import.js:1117 à 1124`), tableau des colonnes (type, obligatoire, valeurs permises, exemple). Le modèle est engendré **depuis la déclaration du jeu** (`modele(jeuId)`, `import.js:944`), jamais écrit à la main : une seule source.
2. **Vérification** : « Téléverser » ; analyse complète sans écriture ; compteurs valides, avertissements, refus ; points sur le fichier entier ; aperçu ligne par ligne filtrable ; « Rapport d'erreurs (.xlsx) » ; un fichier refusé est consigné au lot « refusé » (`import.js:1167`).
3. **Import** : « Confirmer l'importation (N lignes) » (commande déclarée) ; confirmation nommant l'auteur ; écriture d'un seul geste ; lot appliqué `IMP-AAAA-NNN` ; message qui survit à la navigation (`U.toastDiffere`) ; annulation du lot par archivage (RG-14) tant qu'aucun acte ne s'appuie dessus.

### 6.3 Ce qui est déjà au moteur, et ce qui est à construire

| Déjà au moteur (maquette ET poste) | À construire |
|---|---|
| Lecture `.xlsx` et `.csv`, modèle engendré, analyse en une passe, refus nommés, rejeu avant écriture, atomicité, lots, annulation par archivage, rapport `.xlsx`, journal RG-12 | `K.importer` (fabrique, fenêtre modale, branchement `K.crud`) |
| Types `tarif`, `liste`, `date`, bornes, `reglesLot` (RG-10) | Déclaration légère des jeux au manifeste (`N.IMPORTS`, 7.1) lisible **sans charger `import.js`** |
| 10 jeux | 17 jeux (section 4) et le jeu différé |
| Statut `supporte` ou `proposition` validé | Mode de doublon déclaré (`refuser`, `ignorer`, `nouvelle version datée`) |
| Écran de supervision `imp-accueil` | Droit d'import distinct (7), masquage des valeurs sensibles (5.3) |
| Rapport et historique | Chargement paresseux du moteur depuis un écran hôte (6.5) |

### 6.4 Modes de doublon

Déclarés par jeu (champ `doublon: 'refuser' | 'ignorer' | 'versionner'`), jamais choisis par l'agent à l'import : `patients` est **toujours** `refuser` ; `catalogue-tarifaire`, `tarifs-produits`, `garanties`, `couvertures-assurance` sont `versionner` (colonne `Date d'effet` obligatoire, ancienne version conservée) ; `produits-referentiel` peut être `ignorer`. Un `ignorer` écrit au rapport le **nombre et la liste** des lignes ignorées : un doublon ignoré en silence est une donnée perdue sans le dire.

### 6.5 Où vivent les jeux, et comment le moteur se charge

* **Déclaration de droit** (identifiant, écran hôte, module, sensibilité, collections cibles) : au **manifeste** `nav.js` (`N.IMPORTS`), parce que `extraire.js` (qui engendre `rbac.json`) ne charge que `nav.js` et que la matrice doit connaître chaque jeu sans exécuter le moteur.
* **Colonnes, contrôles, écriture** : `modules/import.js` pour les jeux existants et ceux que la section 4 classe « stock, tarifs, référentiels » (même fichier : un seul moteur, `JEUX` y est la table). Si `import.js` dépasse un seuil raisonnable (il fait déjà 93 Ko), les jeux **par module** vivent dans des fichiers `modules/import-<module>.js` qui s'enregistrent dans `SIGH.importer.JEUX` (proposition : ne pas scinder avant que le nombre de jeux dépasse 20).
* **Chargement** : le moteur et `vendor/xlsx-mini.js` pèsent 116 Ko (`wc -c`). Les poser sur toutes les pages (`SCRIPTS` de `gen-pages`) alourdit chaque écran ; les ajouter à la page hôte par `scripts` (`nav.js:370`) suffit pour une page chargée à froid. Pour l'application sans rechargement, un chargeur paresseux existe (`chargerScript`, `app.js:84`) mais **n'est pas exposé** (liste d'export `app.js:1549`) : l'exposer fait partie du lot L0. Aucun hôte ne doit supposer `import.js` chargé.
* **Garde de génération** (précédent : `servant` inexistant, `gen-pages`) : `gen-pages` échoue si un jeu de `JEUX` n'a pas sa déclaration `N.IMPORTS`, ou si une déclaration pointe un écran hôte inexistant.

---

## 7. Droit d'import et accès (RBAC créé pour l'import)

### 7.1 Un droit distinct, déclaré, non déduit

Aujourd'hui, importer = éditer l'écran `imp-<jeu>` (écart 2.2, point 1). Le droit d'import devient un **axe propre**, par **jeu** :

| Capacité | Sens |
|---|---|
| `voir` | voit le jeu : modèle, historique **de ses propres lots**, rangée IMP |
| `importer` | téléverse, vérifie, confirme |
| `annuler` | annule **un lot** (le sien ; ceux des autres relèvent de la supervision, 7.3) |

Forme : un **triplet par jeu** à côté du triplet `[voir, éditer, annuler]` des écrans, **sans le modifier** (rétrocompatible par construction, comme le passage de la grille à six colonnes : aucun appelant retouché).

* **Fiche RBAC** (collection `rbac`, une fiche par rôle) : nouveau champ `droitsImport: { '<jeu>': { voir, importer, annuler } }`, **parallèle à `droitsEcrans`** (`m14-securite.js:984 à 1034`). Même écran d'administration `m14-roles`, nouvelle section « Importation » sous les modules.
* **Manifeste** : `N.IMPORTS = [{ id, libelle, module hôte, écran hôte, sensibilite, collections, doublon }]` (`nav.js`). C'est lui qui engendre la ligne de la matrice par défaut et la liste de `m14-roles`.
* **`rbac.json`** (engendré, `prototype_html/build/extraire.js:114 à 138`) : nouvelle section `import: { jeux: [...], parRole: { <rôle>: { <jeu>: [voir, importer, annuler] } } }`. Le fichier engendré est la **source unique** pour la maquette, le poste, la mère et le panneau (en-tête `_doc` de `rbac.json`) ; le test `packages/rbac/test/rbac.test.js` gagne les décisions ci-dessous (« chaque ligne encode une décision de la Direction »).
* **Résolution** : `N.droitImport(roleId, jeuId)` (nouvelle, dans `nav.js`, à côté de `N.droits` `nav.js:1306` et `N.droitsEcran` `nav.js:1365`) lit : rôle archivé → fermé ; surcharge `droitsImport` de la fiche ; sinon défaut du manifeste ; module désactivé (`ecranActif`) → fermé pour tous, administrateur compris. Comme pour `droitsEcran`, **une surcharge accorde autant qu'elle restreint**, et un rôle créé en exploitation part de zéro (jeux fermés nommément).
* **Application** : `K.importer(jeuId)` appelle `N.droitImport` ; le moteur **refuse aussi** (`appliquer`, `annulerLot`) : masquer un bouton ne protège rien (précédent `S.garder`, CLAUDE.md vague 69). Les écrans `imp-<jeu>` **héritent leur visibilité du droit `voir` du jeu** (mécanisme `servant`, `nav.js:1466 à 1500`) : une seule vérité, pas deux. Le droit d'**éditer** l'écran hôte n'est **ni nécessaire ni suffisant** : le gestionnaire qui voit `m6-produits` en édition n'importe pas pour autant `tarifs-produits`, et l'inverse.

### 7.2 Qui détient quoi par défaut (proposition à valider)

Principe : on **part de l'existant** (rbac.json, mesuré le 10/11/2026) pour ne retirer le droit à personne, on **ajoute** ce que la Direction a demandé au gestionnaire de stock, et on **ne donne rien de plus** à un profil sans métier lié. `V` = voir, `I` = importer, `A` = annuler ses lots.

| Rôle | Jeux détenus par défaut | Existant (rbac.json) | Motif |
|---|---|---|---|
| Administrateur système | tous, `VIA` | `111` sur tous les `imp-*` | Poste d'exploitation, assumé (seul rôle sans fiche) |
| DAF (`da`) | tous les jeux, `VIA` ; supervision de tous les lots | `111` sur tous | Elle porte RH, paie, finances et validation |
| Direction | `V` sur tous ; `VIA` sur `actes`, `catalogue-tarifaire` | `111` sur `imp-accueil` et `imp-actes`, `100` sur Grand Stock | La Direction arrête les tarifs ; pour le reste, « signer n'est pas saisir » |
| Gestionnaire de stock | `VIA` sur `grand-stock`, `produits-referentiel`, `tarifs-produits`, `stock-detail-initial`, `transfert-lignes`, `inventaire-comptage`, `emplacements`, `fournisseurs` ; `V` sur `catalogue-tarifaire` | `111` sur `imp-accueil`, `imp-fournisseurs`, Grand Stock ; **rien** sur `cfg-tarifs`, `cfg-catalogue` (CFG fermé) | Demande du 10/11. Le prix de vente des **prestations** reste à la DAF et à la Direction (Q4) |
| Comptable | `VIA` sur `plan-comptable`, `soldes-ouverture`, `immobilisations`, `budgets`, `centres-couts`, `fournisseurs`, `assureurs`, `souscripteurs`, `garanties` ; `V` sur `grand-stock` | `111` sur ces cinq jeux ; `100` sur Grand Stock | C'est son poste (M12, M9 en écriture) |
| Assistant comptable (`aide_comptable`) | `V` sur ceux du comptable ; **aucun `I`** | aucun | M12 saisie sans clôture ; `soldes-ouverture` engage l'exercice (Q7) |
| Biologiste (`laborantin`) | `VIA` sur `analyses`, `unites-labo` ; `V` sur `variables-labo` | `111` sur `imp-analyses` | C'est son catalogue ; les bornes restent à sa validation écrite |
| Accueil (`reception`) | `VIA` sur `patients` | `111` sur `imp-patients` | Reprise du répertoire, identité seule |
| Agent administratif | `VIA` sur `patients`, `courriers` | `111` sur `imp-patients` | Secrétariat, registre du courrier |
| Médecin, infirmier, aide-soignant, caissier-dispensatrice, ambulancier, surveillant, chirurgien, anesthésiste, échographiste, assistant de direction, directeur médical | **aucun** | aucun (`IMP` fermé) | Aucun métier d'import ; le caissier a `m6-produits` en édition (`111`) mais ne reçoit **aucun** jeu : la dispensation est un geste de caisse (RG-03) |
| Pharmacien, RH | aucun | rôles archivés (RG-14) | |

Une ligne de la matrice par défaut n'est pas un plafond : l'administrateur ajuste depuis `m14-roles`, sauf pour les jeux **refusés** (aucun jeu à accorder) et les colonnes **restreintes** (la capacité paie reste celle de la fiche, 5.2).

### 7.3 La rangée IMP : point central, supervision

La rangée IMP reste le **point central** : modèles, historique, supervision. Elle ne s'ouvre plus par `roles` en dur (`nav.js:696`, liste de huit rôles) mais **à tout profil qui détient au moins un droit `voir` sur un jeu** (calculé depuis la matrice, pas écrit). Elle ne **montre que ses jeux** : `JEUX.filter(peutOuvrir)` filtre déjà les cartes et l'historique (`import.js:1263, 1279`) ; le filtre passe de `N.can` à `N.droitImport`.

* **Historique** : chaque détenteur voit **ses propres lots** (auteur de l'import) ; la **DAF et l'administrateur** voient tous les lots (supervision, annulation pour autrui, consultation du rapport). Jeu restreint : les valeurs ne sont jamais recopiées (5.3).
* L'ouverture à la souris d'une carte « Ouvrir » (`K.lien`, `import.js:1270`) mène à l'écran du jeu, qui est aussi la fenêtre du bouton.

### 7.4 Visibilité dans le ruban (hypothèse Q1)

`treeRuban` filtre le domaine « Système » sur `RUBAN_SYSTEME_ROLES` (`nav.js:1570 à 1577`). Changement minimal proposé : un domaine « Système » **est conservé pour un profil hors liste si, après filtrage par les droits, il lui reste au moins un module de la liste `RUBAN_SYSTEME_MODULES_OUVERTS = ['IMP']`**, et dans ce cas **seul ce module y figure**. Les autres rangées de « Système » (CFG, M14, MERE, SMTP, SMS…) restent invisibles hors administrateur et DAF. Le gestionnaire de stock voit alors un onglet « Système » à une rangée « Importation de données » ne montrant que ses huit jeux. Variante écartée : **déplacer** la rangée IMP dans un domaine propre (renommage de domaine, deux hubs, parité N1 du libellé) : plus de dégâts pour le même service (Q1).

Le hub `hub-imp`, le fil d'Ariane et la recherche globale suivent déjà `tree(role)` (`nav.js:1541`) : aucune retouche. « Masquer n'est pas fermer » (`nav.js:1567` : commentaire de la décision du 05/11) : les droits de chaque écran restent ceux de la matrice.

### 7.5 La décision du 05/11/2026 : ce qui est remplacé, ce qui ne l'est pas

* **Remplacé** (décision du 10/11/2026) : l'onglet « Système » n'est plus réservé à l'administrateur et à la DAF **pour la seule rangée IMP**.
* **Non touché** : le reste de l'onglet, `RUBAN_HORS = ['Relais en ligne']`, les cartes de `parametres-hub`, tous les droits d'écran. La question de savoir s'il faut ouvrir d'autres rangées « Système » est **ouverte** (Q1), pas tranchée ici.

### 7.6 Matrice administrable : procédure complète

| Étape | Où | Détail |
|---|---|---|
| Déclarer le jeu | `nav.js` `N.IMPORTS` | identifiant, hôte, module, sensibilité, collections, mode de doublon ; garde `gen-pages` |
| Écrire les défauts | `N.IMPORTS` (champ `rolesDefaut`) ou fiche RBAC semée | fiches RBAC **semées** : voir 7.7 |
| Résoudre | `N.droitImport(role, jeu)` | surcharge d'abord, défaut ensuite, archive et module désactivé en tête |
| Appliquer à l'écran | `K.droits(code)` reste le droit **de l'écran** (`_kit.js:151`, `app.droits`, `app.js:1537`) ; `K.importer` appelle `N.droitImport` | un hôte peut être en lecture seule et offrir l'import, ou l'inverse |
| Administrer | `m14-roles` | section « Importation » : une ligne par jeu, trois cases ; jeux `refusés` absents ; rôle créé : tout fermé |
| Auditer | `npm run audit-rbac` (`prototype_html/build/audit-rbac.js`) | **sonde nouvelle** : pour chaque rôle et chaque écran hôte, la commande « Importer les données » est présente **si et seulement si** `droitImport.importer` est vrai (deux fautes : **promettre** un bouton sans droit, **cacher** un bouton accordé) ; sondée aussi sur les écrans `imp-*` |
| Inventorier | `npm run inventaire-rbac` | une section « Importations par rôle » |
| Engendrer | `node prototype_html/build/extraire.js rbac` | régénère `packages/rbac/data/rbac.json` avec la section `import` |

Les cinq consommateurs qui fabriquent une entrée synthétique pour interroger `can()` (ruban, cartes de hub, accès rapides, recherche, matrice : `nav.js:1466 à 1500`) **ne doivent rien recopier** : pour le droit d'import, l'appelant nomme le jeu et la fonction relit ses propriétés à la source, la leçon payée trois fois.

### 7.7 Incrément de VERSION

Les fiches RBAC et la matrice par défaut sont **semées** : sans incrément, un poste garde l'ancienne matrice. La mise en service passe `VERSION` de **77 à 78** dans `store.js:115` (la constante est la **seule** source, CLAUDE.md, vague 66). Les collections nouvelles (aucune pour la maquette : les jeux écrivent dans des collections existantes ; `lotsImportation` existe) n'ajoutent pas d'incrément propre. Les jeux **créant des collections ou des formes** (`couverturesAssurance` existe ; `garanties`, `budgets`, `prestataires` existent) sont à contrôler au lot qui les branche : tout nouveau champ de fiche écrit demande l'incrément aussi (**non vérifié** jeu par jeu).

---

## 8. Poste Flutter

### 8.1 Ce qui est déjà porté

Moteur et dix jeux (`packages/domaine/lib/src/import/`), écran et fenêtre (`apps/poste/lib/modules/imp/imp_ecrans.dart`), classeur `.xlsx` (paquets `archive` et `xml`, E2005), sélecteurs natifs injectables, vecteurs de la maquette (`import.json`), relecture indépendante des classeurs (E2004).

### 8.2 Ce qu'il faut porter, par lot

* **Droit d'import** : `rbac.json` est la **source unique** : le poste l'engendre en `MatriceDroits` (`apps/poste/lib/modules/m14/roles.dart:17`) et la superpose à chaud aux fiches `rbac` (`apps/poste/lib/shell/coque.dart:100`). La section `import` entre dans cette génération ; `c.droit.editer` et `c.droit.annuler` de `imp_ecrans.dart:150, 367, 464` sont **remplacés** par `droitImport(jeu).importer` et `.annuler`. Test d'acceptation : pour chaque rôle, la matrice Dart répond comme `N.droitImport` de la maquette sur la même fiche (même méthode que la parité N1). Le **nom exact du générateur** de `MatriceDroits` est **non vérifié**.
* **Fabrique commune** : un composant Dart unique (`BoutonImporter(jeu)`) posé dans le kit du poste (`apps/poste/lib/kit/`), ouvrant la **même** fenêtre que `EcranImportJeu` ; branché dans les écrans hôtes portés. Statut « porté » refusé par `parite_ecrans_test.dart` tant que N1 < 100 % : chaque écran hôte ajoute sa ligne de vecteur (bouton présent/absent par rôle).
* **Vecteurs** : tirés de l'écran réel de la maquette piloté dans Chrome (`vecteurs-import.js`), jamais de la lecture du code (méthode éprouvée, CLAUDE.md). Chaque jeu nouveau ajoute ses cas (nominal, doublon, tiret, RG-03, RG-10, refus nommé).
* **SQLite chiffré, hors ligne** : l'import écrit dans le magasin du poste (AES-256-GCM, E2127 à E2135) ; il fonctionne **hors ligne** par nature. Le lot reste local jusqu'au pont.
* **Famille de fusion et rôle du poste** (8.3) : un fileul ne peut pas écrire un référentiel R ; la fenêtre le **dit** et propose la demande (8.3) au lieu d'écrire.

### 8.3 Un import au poste fileul, comment il voyage

| Jeu | Au poste mère | Au poste fileul |
|---|---|---|
| Référentiels R (catalogues, tarifs, produits sans quantités, assureurs, fournisseurs, plan comptable, centres, natures…) | écrit, voyage par le journal en famille R | **refusé par la règle existante** (écrans de configuration en lecture seule, le moteur refuse) : proposer la **demande d'import** : la vérification s'exécute au fileul sans rien écrire, puis un lot **vérifié** est déposé en ajout seul (collection `demandesImport`, famille B, à créer) pour que la mère l'applique ; ou bien l'import se fait à la mère |
| Stock initial, mouvements, transferts, inventaire | écrit | écrit en **PART** (E2149 : hors ligne, un poste ne sort que sa part de stock) ; compteurs par variations ; la mère rejoue et refuse en nommant (famille D) |
| Patients | écrit | écrit ; code attribué depuis la **plage allouée par la mère** (`CNT/n/AA`, E2127 à E2135) ; un code en double est marqué, jamais corrigé |
| Écritures (soldes d'ouverture) | écrit en brouillon | écrit en brouillon ; la mère refait RG-10 et refuse un à-nouveau déjà existant |
| Mobiles | **jamais** d'import au mobile (RG-13 : le mobile ne reçoit déjà pas la configuration de la mère, sauf les hachés) | sans objet |

Où est le poste du gestionnaire de stock (mère ou fileul), c'est ce qui commande la solution : **non vérifié** dans le dépôt. Q5 pose la question à la Direction.

**Mise à jour du lot IMP-D (12/11/2026, décision N de la Direction, option (c)) : un fileul importe AUSSI directement chez lui.** La ligne « Référentiels R » du tableau ci-dessus n'est plus « refusé » : pour un jeu dont toutes les cibles sont de configuration (analyses (modèle), fournisseurs, compagnies, souscripteurs, plan comptable, natures de facture, centres de coûts, unités du laboratoire, emplacements), le fileul **écrit chez lui tout de suite** (même chemin que la mère, sous la garde qui ne laisse passer que ce geste) **ET une demande part automatiquement** à la mère, qui reste l'autorité : elle rejoue sous le rôle de l'auteur et ne confirme que le MÊME résultat, avec les mêmes identifiants de fiche ; sinon elle refuse en nommant et le fileul restitue (archivage, RG-14). La mère injoignable, la demande attend dans la file du fileul et ses fiches portent « En attente de la mère ». En cas de conflit, la mère gagne. Le jeu restreint de configuration (le personnel) reste réservé à la mère (le Grand Stock, d'abord laissé par demande seule, est repris par la mise à jour du lot IMP-E ci-dessous). Voir `ECARTS-MAQUETTE.md` E2500 à E2508 et `DECISIONS-A-VALIDER.md` section P.

**Mise à jour du lot IMP-E (13/11/2026, décision de la Direction) : le Grand Stock s'écrit AUSSI chez le gestionnaire de stock.** « L'argument du double comptage n'est pas prouvé » : il a été mesuré (il existait : 300 unités en lot pour 150 importées, `ECARTS-MAQUETTE.md` E2520) puis levé. Le Grand Stock (produits, lots, mouvements) suit la voie « écriture directe chez le fileul ET demande automatique à la mère » comme les autres référentiels, avec quatre garanties d'idempotence : (1) les fiches d'une demande portent la MÊME identité sur tous les postes (identifiant `<COL>-<demande>-<rang>`, `serieDemande`) ; (2) la quantité d'un lot et le stock d'un article sont une valeur de DÉPART commune (`departCompteurs`), jamais une variation publiée ; seules les sorties et entrées postérieures voyagent ; (3) un stock en attente de la mère est PROPRE au poste (rien au journal, donc rien aux autres postes ni aux téléphones) ; (4) un rejeu (demande reçue deux fois, redémarrage, reprise du journal) est un NO-OP prouvé. Refus de la mère : chaque entrée est contre-passée par un mouvement inverse nommé, les lots et articles sont archivés (RG-14) ; un article déjà sorti ne se restitue pas, il reste marqué et la demande dit « restitution partielle » (jamais de stock négatif, RG-03). Voir `DECISIONS-A-VALIDER.md` section R.

---

### 8.4 Lot 8 (14/11/2026) : ce que le poste porte maintenant, et comment un jeu réservé se refuse

* **Droit d'import par jeu, écrit au poste** : « Rôles & permissions » règle, par rôle, voir / importer / annuler pour chaque jeu (fiche `rbac`, `droitsImport`), importer et annuler supposant voir ; une surcharge accorde autant qu'elle restreint ; effet immédiat dans le moteur ; commande absente sans le droit d'éditer l'écran. Aucun second mécanisme : le même `droitsImport` que la maquette et `rbac.json`.
* **Jeu réservé à la mère** : sur un fileul rattaché, un jeu RESTREINT qui écrit la configuration de la mère (le personnel, le stock détail initial, le bon de transfert) ne s'écrit pas : la commande est absente ET le moteur refuse (`JEU_RESERVE_A_LA_MERE`, motif, geste), le fichier pouvant toujours être vérifié. Le comptage d'inventaire n'écrit que `inventaires` : écriture directe.
* **Jeux portés au poste** : 17 sur 26 (les 14 d'IMP-C à IDEM plus le stock détail initial, le bon de transfert et le comptage d'inventaire) ; les neuf autres restent fermés et se disent « Non porté au poste » (E2614).
* **Vue unifiée du dossier** (EF-DOC) : « Pièces produites par le logiciel » liste aussi les comptes rendus de maternité et les fiches de consultation, en renvois, la zone médicale fermant la vue entière.

### 8.5 Lot 8b (14/11/2026) : prix, garanties et couvertures, comptabilité

* **Jeux portés au poste** : 27 sur 29. Ajoutés : `tarifs`, `catalogue-imagerie`, `garanties`, `couvertures-assurance`, `immobilisations`, `budgets`, `courriers`. Restent fermés « Non porté au poste » : `tarifs-produits` et `produits-referentiel` (lot TFIN, prix d'achat versionné).
* **Prix** : un fileul rattaché ne pose jamais une version de prix (elle est immuable, la mère seule l'écrit) ; il dépose une demande d'import vérifiée, la mère refait les contrôles sous le rôle et le nom de l'auteur, et le Oui d'un fileul vaut proposition (la décision d'un prix revient à la mère).
* **Versions datées** : une garantie et une couverture sont des VERSIONS ; la prise en charge lit la version en vigueur à la date de la pièce (RG-09), une pièce émise garde son taux et un lot ne s'annule plus sous elle.
* **Comptabilité** : un budget ne s'écrit jamais sur un exercice clos, d'où que l'écriture vienne (garde au moteur du magasin) ; les numéros de série se prennent à la suite, archivés compris ; aucune écriture comptable n'est écrite (RG-10). Écriture directe, même chez un fileul.
* Voir `ECARTS-MAQUETTE.md` E2627 à E2637 et la section AD des décisions.

## 9. Lots proposés

Ordre fondé sur les dépendances : le droit et la fabrique avant tout jeu ; les jeux demandés par la Direction avant les autres ; le poste Flutter lot par lot derrière la maquette (la maquette d'abord, vague 1 du 31/10).

| Lot | Contenu | Dépend de | Vérifications |
|---|---|---|---|
| **L0 socle** | `N.IMPORTS` et garde `gen-pages` ; `N.droitImport` ; section « Importation » de `m14-roles` ; `rbac.json` régénéré ; `K.importer` (fabrique, fenêtre modale) ; chargeur paresseux exposé ; masquage des valeurs sensibles (5.3) ; modes de doublon ; ruban : rangée IMP visible (7.4) ; `VERSION` 78 | décision Q1 | **Scénario au geste** : le bouton est présent pour un rôle qui détient le jeu et **absent** pour un autre, sur chaque hôte ; **audit-rbac** étendu (sonde 7.6) à 0 promesse et 0 lecture non dite ; **test `packages/rbac`** (décisions 7.2) ; **mutation** : retirer le contrôle d'`appliquer` (garde moteur) doit faire échouer la sonde ; **un scénario par défaut de masquage** : un lot de patients refusé ne laisse aucune valeur dans la collection `lotsImportation` |
| **L1 jeux existants sur leurs écrans** | bouton posé sur `m6-stock-gros` / `m6-import-grand-stock`, `m7-fournisseurs`, `m9-compagnies`, `m12-plan-comptable`, `m12-ouverture`, `m1-patients`, `m10-personnel`, `cfg-tarifs` (actes), `m5-catalogue` (jeu `analyses`, après Q3) ; `imp-*` devient page de supervision | L0 | Scénario par hôte : modèle relu par le lecteur du poste, refus nommé, atomicité, annulation ; non-régression des 10 jeux existants (`test-import.js`, `vecteurs-import.js` régénérés) |
| **L2 stock (demande directe)** | `produits-referentiel`, `tarifs-produits`, `emplacements`, `transfert-lignes`, `stock-detail-initial`, `inventaire-comptage` ; boutons sur `m6-produits`, `m6-etiquetage`, `m6-transferts`, `m6-stock-detail`, `m6-inventaire-feuille` | L0, Q4, Q6 | RG-03 : un stock négatif est impossible ; un transfert importé = même effets que le geste (stocks, mouvements, bon numéroté) ; tarif : une facture émise avant garde son prix ; **mutation** : désactiver la vérification RG-03 d'une ligne doit faire échouer la sonde |
| **L3 catalogue tarifaire** | `catalogue-tarifaire` (collection `catalogueTarifs`) ; réconciliation avec `actes` (Q2) ; réconciliation `analyses` et `examensLabo` (Q3) | L0, Q2, Q3 | Un tiret n'est jamais un zéro (sonde au geste sur le fichier) ; un prix versionné ne change pas une pièce émise |
| **L4 autres référentiels** | `natures-facture`, `centres-couts`, `catalogue-imagerie`, `unites-labo`, `prestataires`, `garanties`, `couvertures-assurance`, `immobilisations`, `budgets`, `courriers` | L0 | Un scénario par jeu ; audit RBAC |
| **L5 poste Flutter** | un sous-lot par lot de maquette : section `import` de `rbac.json`, `BoutonImporter`, jeux portés dans `packages/domaine`, vecteurs | chaque lot | `parite_ecrans_test.dart` N1 = 100 % ; parité de la matrice Dart et de `N.droitImport` ; relecture des classeurs par l'autre implémentation |
| **L6 demande d'import (fileul → mère)** | collection `demandesImport` (famille B), écran « demandes à appliquer » à la mère | L5, Q5 | Banc de synchronisation à deux processus (`npm run banc:sync`) ; un lot appliqué deux fois est refusé |

**Règle des bancs pour toute vérification** (piège payé le 06/11/2026, E2263) : un banc isolé se lance avec `SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> SIGH_PORT_TEST=<port libre>` et se contrôle par `ps aux | grep "php -S"` ; sinon deux bancs partagent un serveur, un arbre et une base. Le service `postgresql` se démarre avant tout banc.

---

## 10. Risques

| Risque | Gravité | Réponse |
|---|---|---|
| Ouvrir le module à d'autres postes fait fuir des valeurs nominatives par l'historique des lots | **haute** | Masquage des valeurs pour les jeux restreints, historique limité à l'auteur et aux superviseurs, **avant** l'ouverture (L0) |
| Un jeu écrit la mauvaise collection (écarts 2 et 3 : `actes` contre `catalogueTarifs`, `examensLabo` contre `analyses`) : l'agent importe un catalogue que rien ne lit | **haute** | Q2 et Q3 tranchées avant L3 ; sonde : après import, la facturation et l'écran hôte voient la même fiche |
| Un import de stock contourne RG-03 ou RG-05 | haute | Contrôles du moteur (`import.js:136, 157`), refus si mouvement postérieur, sonde par mutation |
| Un import de tarifs écrase un prix déjà facturé | haute | Versionnement par date obligatoire ; jamais de mise à jour en place |
| Un fileul importe un référentiel qui ne remonte jamais | moyenne | Refus nommé au fileul, demande d'import (L6) |
| Performance sur plusieurs milliers de lignes (18 000 patients) : **non vérifiée**, aucune borne de taille au moteur | moyenne | Mesure au lot L1 sur un fichier de 20 000 lignes avant d'annoncer la reprise des patients ; borne et découpage en lots si nécessaire |
| Le droit d'import déduit de l'édition de l'écran hôte | haute | Droit distinct (7.1) ; sonde d'audit dans les deux sens |
| La liste `roles` des jeux, décorative, divergente du manifeste, finit par tromper un relecteur | faible | La retirer ou la dériver de `N.IMPORTS` (L0) |
| Le moteur est chargé sur chaque page hôte (116 Ko) | faible | Chargement paresseux (6.5) |
| Le texte `CLAUDE.md` est en retard sur le code (version 68, PRD d'import absent) | faible | Mise à jour au lot L0 |

---

## 11. Questions ouvertes pour la Direction (avec recommandation)

**Q1. La rangée IMP seule, ou tout l'onglet « Système » ?** La décision du 10/11/2026 vise la rangée « Importation de données ». *Recommandation : la rangée seule* (hypothèse retenue, 7.4) ; le profil voit un onglet « Système » réduit à cette rangée. Alternative : une entrée de ruban distincte ; *déconseillée* (renommage de domaine, parité N1 des libellés).

**Q2. Le « Catalogue tarifaire (deux prix) » (`catalogueTarifs`) alimente-t-il la facturation ?** Aujourd'hui seule `actes` est lue par la facturation (`parcours.js:154`). *Recommandation : un jeu `catalogue-tarifaire` qui écrit `catalogueTarifs` ET propose, à la validation de la DAF, le report vers `actes` (le jeu `actes` existant reste la voie de la facturation).* À défaut de décision, importer `catalogueTarifs` seul n'a **aucun effet sur les factures** : c'est ce qu'il faut dire à la Direction avant le lot L3.

**Q3. Le catalogue des analyses : prix (`analyses`) ou modèle de résultat (`examensLabo`) ?** Le jeu existant écrit `examensLabo` ; l'écran `m5-catalogue` lit `analyses`. *Recommandation : deux jeux distincts nommés pour ce qu'ils écrivent* (`analyses-catalogue` et `analyses-modele`), jamais un seul ambigu.

**Q4. Le gestionnaire de stock importe-t-il aussi le prix de vente des prestations ?** Il n'a ni CFG ni `cfg-tarifs` (rbac.json). *Recommandation : non.* Il importe les **prix d'achat des produits** (`tarifs-produits`, RG-02 : pas de marge) ; le catalogue des actes et le catalogue tarifaire restent à la DAF, à la Direction et à l'administrateur. Si la Direction veut le contraire, le droit s'accorde fiche par fiche, sans toucher au code.

**Q5. Le poste du gestionnaire est-il la mère ou un fileul ?** Non vérifiable dans le dépôt. *Recommandation :* si c'est un fileul, offrir la **demande d'import** (8.3, lot L6) ; sinon un référentiel importé à ce poste serait refusé par la règle de la famille R.

**Q6. Un stock détail initial est-il légitime ?** Le détail naît d'ordinaire d'un transfert. *Recommandation : oui, une seule fois, tant qu'aucun mouvement n'existe*, comme le Grand Stock ; sinon, pas de jeu `stock-detail-initial` et le détail se constitue par un premier transfert importé.

**Q7. L'assistant comptable importe-t-il quelque chose ?** *Recommandation : lecture seule* sur tous les jeux comptables ; les soldes d'ouverture engagent l'exercice et sa clôture lui est fermée (`m12-cloture`).

**Q8. Mode « ignorer les existants » sur les référentiels.** *Recommandation : l'autoriser sur `produits-referentiel`, `fournisseurs`, `emplacements`, `courriers` seulement, avec la liste des lignes ignorées au rapport ; jamais sur `patients`, comptes ni pièces.*

**Q9. Le groupe sanguin dans l'import des patients.** C'est une donnée de santé d'identification. *Recommandation : le retirer du modèle à l'accueil* (il se saisit à la première consultation, par un soignant) ; ou le réserver au profil médical.

**Q10. Le salaire de base à l'import du personnel.** *Recommandation : colonne présente seulement pour le profil qui détient la capacité paie* (DAF, administrateur), absente et refusée pour un autre.

**Q11. L'historique d'un lot sensible visible de qui ?** *Recommandation : de son auteur, de la DAF et de l'administrateur ; jamais les valeurs de cellule* (5.3).

**Q12. Quelle taille maximale d'un fichier ?** Aucune borne au moteur ; la reprise des 18 000 dossiers est le cas extrême. *Recommandation : mesurer d'abord (L1) puis fixer une borne par jeu, paramétrable et enregistrée en base (règle de paramétrage du 09/11), jamais une constante du code.*

**Q13. Le jeu `inventaire-comptage` et la feuille d'inventaire.** Hors demande explicite. *Recommandation : l'inclure au lot L2* car la feuille de deux cents articles est précisément le cas d'import en masse du gestionnaire ; la régularisation reste un geste humain.

---

## 12. Les dix décisions qui comptent le plus

1. **Une fabrique unique** (`K.importer`) et une seule fenêtre en trois temps, jamais dix copies ; le bouton est absent sans le droit.
2. **Un droit d'import distinct** (`voir`, `importer`, `annuler` par jeu), déclaré au manifeste, porté par la fiche RBAC et `rbac.json`, **jamais déduit du droit d'édition** de l'écran.
3. **La rangée IMP visible** de tout détenteur d'un droit d'import, **montrant ses seuls jeux** ; le reste de l'onglet « Système » reste réservé (Q1).
4. **Le gestionnaire de stock importe stock, produits, emplacements, transferts, inventaire et prix d'achat des produits** depuis son poste ; le prix de vente des prestations reste à la DAF et à la Direction (Q4).
5. **Deux écrans de catalogue lisent une autre collection que celle du jeu existant** (`catalogueTarifs` contre `actes`, `analyses` contre `examensLabo`) : à trancher avant tout import de catalogue (Q2, Q3).
6. **Jamais de donnée clinique, de paie nominative, de pièce émise ni de sécurité à l'import** : 68 écrans classés « à REFUSER ».
7. **Un import ne modifie jamais une fiche tenue** ; trois modes de doublon déclarés par jeu, tarifs et garanties **versionnés par date** (règle du 09/11).
8. **Les valeurs sensibles ne sont plus recopiées dans l'historique des lots** : correctif préalable à l'ouverture du module.
9. **Un référentiel importé à un poste fileul est refusé par la règle existante** ; solution proposée : la demande d'import vérifiée, appliquée par la mère (Q5).
10. **Montée de `VERSION` 77 à 78** avec la matrice semée, un test `packages/rbac` et une sonde `audit-rbac` dans les deux sens (promettre, cacher), poste Flutter derrière la maquette lot par lot.
