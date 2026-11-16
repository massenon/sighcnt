# Tableaux : couverture de l'export, des cases à cocher et de l'impression (lot EXP, étape 0)

Mesure du 16/11/2026, faite dans le code de l'arbre `lot/exp` (base 05ab56d) AVANT tout changement. PRD : `docs/prd/PRD-TABLEAUX-export-xlsx-et-impression-de-la-selection.md` ; décisions : `DECISIONS-A-VALIDER.md` section AH, points 38 à 42 (« OUI à tout », 15/11/2026). Rien n'a été codé avant ce tableau.

Méthode : comptage par motif dans le code (`grep`), puis lecture de chaque tableau construit à la main. Ce n'est pas une revue écran par écran dans Chrome : la garde de génération (`build/garde-tableaux.js`, étape 1) refait ce comptage à chaque `npm run lint`, et le scénario « Vague 190 » éprouve le composant sur des écrans réels.

## 1. Maquette (`prototype_html/assets/js`)

### 1.1 Le composant commun `U.dataTable` (`ui.js`)

| Mesure | Avant le lot |
|---|---|
| Appels de `U.dataTable` (tous modules) | **219** (dont 3 dans `_kit.js`, celui de `K.crud` compris) |
| Écrans `K.crud` (gabarit qui passe par `U.dataTable`) | **46** appels |
| Sélection par cases (`selectable`) | défaut **`false`** dans le composant ; **`true` par défaut dans `K.crud`** (46 écrans, tableau des actifs seulement, jamais celui des archives) ; `true` déclaré sur 2 autres tableaux (badges à imprimer M10, `_kit.js:446`) ; `false` déclaré sur 1 (GED) |
| Bouton « Exporter » | présent sur les 219 (posé par le composant) ; il propose « CSV / Excel » (un **.csv**, jamais un .xlsx) et « PDF / Impression » des lignes **filtrées** |
| Export ou impression des seules lignes cochées | **aucun** dans le composant. `K.crud` a une action de groupe « Imprimer la sélection » (46 écrans) qui imprime TOUTES les colonnes déclarées (y compris celles que l'agent a masquées), sans journal |
| Actions de groupe (`bulkActions`) | 6 déclarations |
| Sélection d'une page à l'autre | conservée (clé `r.id`), mais le compteur compte les cases cochées hors filtre alors que l'action de groupe ne les prend pas (`selectedRows` relit le filtre) : écart dit en silence |
| Ligne sans `id` | toutes les lignes sans `id` partagent la clé `undefined` : cocher l'une coche toutes les autres |
| Journal RG-12 d'un export ou d'une impression | **aucun** |
| Limite de lignes | **aucune** |
| Droit d'exporter | **aucun** (tout profil qui ouvre l'écran exporte) |

### 1.2 Les tableaux d'encart `K.miniTable` (`_kit.js`)

**186** appels (tableaux de bord, tiroirs de détail, encarts de configuration) : ni case, ni export, ni impression. Répartition : `m10-rh` 23, `dashboards` 21, `m1-patients` 21, `configuration` 19, `m12-comptabilite` 18, `m2-consultations` 15, `m4-maternite` 14, `m9-assurances` 10, `m8-facturation` 8, `m6-stock` 7, `m7-achats` 7, `m11-paie` 7, `m3-hospitalisation` 5, `m13-administration` 4, `import` 2, `m14-securite` 2, `mere` 1, `relais` 1, `support` 1.

### 1.3 Les tableaux construits à la main (`el('table')` hors composant)

Le PRD comptait 29 tableaux ; la mesure en trouve **31** hors `ui.js` (30 dans les modules et `_kit.js`, 1 dans `print.js`). Chacun a été lu. Trois natures :

- **saisie** : grille d'un formulaire en cours (champs, cases d'un droit en train d'être réglé). Ce n'est pas une liste de fiches : rien à exporter tant que la pièce n'est pas enregistrée ; une fois enregistrée, elle sort par le tableau de sa collection.
- **document** : le tableau EST la pièce imprimée (ou sa vue écran à l'identique) ; il s'imprime déjà par son gabarit.
- **consultation** : une liste lue à l'écran, sans composant commun : il lui manque cases, export et impression.

| # | Fichier : ligne | Contexte | Nature | Traitement proposé (étape 1) |
|---|---|---|---|---|
| 1 | `m6-stock.js:1211` | lignes d'un bon de mouvement, au tiroir | consultation (document unitaire) | équipé (cases, export, impression des lignes cochées) |
| 2 | `m6-stock.js:1955` | comptage d'inventaire (stock compté saisi) | saisie | exempté, motif écrit dans la garde |
| 3 | `m6-stock.js:2532` | panier d'une dispensation | saisie | exempté |
| 4 | `m14-securite.js:526` | matrice rôles × modules (lecture) | consultation (matrice) | équipé |
| 5 | `m14-securite.js:821` | réglage des modules d'un rôle (modale) | saisie | exempté |
| 6 | `m14-securite.js:975` | réglage écran par écran (modale) | saisie | exempté |
| 7 | `m14-securite.js:1069` | droits d'import d'un rôle (modale) | saisie | exempté |
| 8 | `m14-securite.js:1145` | gestes réservés d'un rôle (modale) | saisie | exempté |
| 9 | `m8-facturation.js:721` | prestations d'une facture en composition | saisie | exempté |
| 10 | `m8-facturation.js:2249` | prestations à encaisser (cases déjà présentes) | saisie | exempté |
| 11 | `m13-administration.js:518` | diagramme du plan d'action par trimestre | consultation (matrice) | équipé |
| 12 | `m7-achats.js:583` | lignes d'une demande en cours | saisie | exempté |
| 13 | `m7-achats.js:850` | lignes d'une commande en cours | saisie | exempté |
| 14 | `m7-achats.js:1186` | quantités reçues d'une réception | saisie | exempté |
| 15 | `m10-rh.js:887` | grille du planning (cellules actives) | saisie (grille) | exempté : ses données sortent par le registre du planning, tableau commun placé dessous |
| 16 | `m10-rh.js:3258` | grille des primes NS 132 | consultation | équipé |
| 17 | `m10-rh.js:5063` | grille du planning entretien et sécurité | saisie (grille) | exempté : même motif que 15 (registre des agents dessous) |
| 18 | `_kit.js:1341` | `K.miniTable` (186 encarts) | consultation | équipé dans le gabarit (un seul changement pour les 186) |
| 19 | `m12-comptabilite.js:621` | lignes d'une écriture en saisie | saisie | exempté |
| 20 | `m12-comptabilite.js:2035` | liasse : tableau d'un état (vue écran) | document | exempté (la liasse a ses impressions et son classeur propres) |
| 21 | `m12-comptabilite.js:4226` | lignes d'une pièce en saisie | saisie | exempté |
| 22 | `m12-comptabilite.js:5138` | feuillet de liasse (écran et impression) | document | exempté |
| 23 | `configuration.js:2280` | matrice des notifications (cases éditables) | saisie | exempté |
| 24 | `m5-laboratoire.js:970` | résultats d'une demande, au tiroir | consultation (document unitaire) | équipé |
| 25 | `m5-laboratoire.js:1362` | en-tête du compte rendu imprimé | document | exempté |
| 26 | `m5-laboratoire.js:1393` | corps du compte rendu imprimé | document | exempté |
| 27 | `m5-laboratoire.js:2184` | historique des versions d'un seuil | consultation | équipé |
| 28 | `m5-laboratoire.js:3547` | valeurs d'une tendance | consultation | équipé |
| 29 | `m5-laboratoire.js:3710` | comparatif des antériorités | consultation (matrice) | équipé |
| 30 | `print.js:135` | `P.tableau`, tableau des états imprimés | document | exempté (c'est la sortie de l'impression) |
| 31 | `parcours.js:4482` | balance d'une archive légale (chaîne HTML écrite dans le fichier d'archive) | document | exempté |

Bilan : **12 tableaux de consultation** à équiper (dont `K.miniTable`, qui en couvre 186), **15 grilles de saisie** et **6 documents** exemptés avec motif. Les exemptions sont une **proposition à valider** (section AK) : le PRD dit « tous les tableaux », mais une grille en cours de saisie n'a pas encore de lignes à sortir.

### 1.4 Colonnes et lignes sensibles par profil

Le composant ne décide d'aucun droit : CHAQUE écran construit ses colonnes et ses lignes pour le profil courant. Mécanismes relevés dans le code :

| Mécanisme | Ce qu'il retire | Où |
|---|---|---|
| Rôle (matrice des écrans, RG-13) | l'écran entier (médical, financier, RH) | `nav.js`, `N.droitsEcran` |
| Zone du dossier (1 administratif, 2 médical) | les pièces et colonnes médicales pour un profil non clinique | `data.js` (ZONES), `PR.peutVoirDocument` |
| Secteur (périmètre) | les lignes d'un autre secteur | `N.secteur…`, filtres d'écran |
| Capacité PAIE (`N.capacitePaie`) | la colonne « Salaire de base » (jeu du personnel) | `import.js` |
| Colonnes masquées par l'agent (« Colonnes ») | les colonnes décochées | `ui.js` (`state.hidden`) |
| Rendu qui transforme la valeur (`render`) | ce que la cellule montre peut différer de la valeur brute (`r[key]`) : un export qui lit la valeur brute peut sortir PLUS que l'écran | 219 tableaux ; exemple lu : `numeroMasque` (M13) |

Conséquence pour l'étape 1 : la sortie prend EXACTEMENT les lignes que l'écran a reçues (`rows`) et les colonnes visibles ; une cellule rendue autrement que sa valeur brute sort sous le TEXTE que l'écran montre, jamais sous la valeur brute, sauf quand le texte montré est la même valeur (un nombre formaté, une date formatée), qui sort alors typée.

## 2. Poste (`apps/poste/lib`)

| Mesure | Avant le lot |
|---|---|
| `TableauSigh` (kit `kit/tableau.dart`) | **348** appels dans **180** fichiers |
| Sélection (`selectionnable: true`) | **8** appels (défaut `false`) |
| Actions de groupe (`actionsGroupe`) | 10 |
| Export : rappel `alExporter` branché | **3** appels (`mrb_journal`, `mrb_commun`, `mra_commun`). Sur les **345** autres, le bouton « Exporter » est présent et sa fenêtre propose « CSV / Excel », mais le bouton **ne fait rien** (le rappel est nul) : un défaut en silence |
| Format | CSV seulement ; pas de .xlsx alors que le poste a déjà un écrivain (`lib/import/classeur_xlsx.dart`, port de `xlsx-mini.js`) et `file_selector` |
| Impression depuis le tableau | aucune |
| Journal, limite, droit d'exporter | aucun |
| `MiniTableauSigh` (`kit/tableau_de_bord.dart`) | **139** appels, ni case ni export |
| `Table` construits à la main | **18** hors kit, mêmes natures qu'à la maquette (saisie : `roles.dart` ×4, `facturation.dart`, `besoins_commun.dart`, `besoins_receptions.dart`, `cfb_notifications.dart` ; grilles : `rhb_planning.dart`, `rhc_securite_entretien.dart` ; documents : `cpb_feuillets.dart`, `impression/feuilles.dart`, `mvt_transferts.dart` ×2 ; consultation : `adm_vues.dart`, `res_comparatif.dart`, `res_resultats.dart`, `mrc_commun.dart`) |

## 3. Ce que l'étape 1 et l'étape 2 font de cette mesure

Voir `docs/architecture/ECARTS-MAQUETTE.md` (E2690 et suivants) et la section AK de `DECISIONS-A-VALIDER.md` pour ce qui a été fait, mesuré et laissé.
