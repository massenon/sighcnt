# Audit des marquages « à valider » de la maquette (07/11/2026)

Demande de la Direction : tout marquage « à valider » doit s'accompagner d'un bouton Valider qui change le statut (le marquage tombe, la validation est enregistrée). Défaut constaté sur les modèles d'enquête.

## 1. Périmètre examiné

Grep des motifs `aValider|tarifProvisoire|valorisationProvisoire|aCompleter|à valider|à confirmer|à arbitrer` sur `prototype_html/assets/js/*.js` et `modules/*.js` : **298 lignes**, 29 fichiers (les plus chargés : `data-labo.js` 53, `configuration.js` 31, `m5-laboratoire.js` 27, `data.js` 24, `m13-administration.js` 23, `data-imagerie.js` 22). Lus : `m13-administration.js:1780-2150` (`adm-validations`), `parcours.js:3756-4107` (modèle `PR.validerIdentite`), `configuration.js:28-82`, `store.js:1630-1680` et `2940-2985`. Poste Flutter : seulement repéré (`qual_validations.dart`, `cs_pathologies.dart`, `cr_commun.dart`), non lu.

**Constat central.** Un seul geste « Valider » enregistre `valideLe` et `validePar`, journalise et fait tomber le marquage : celui de la configuration fiscale (`parcours.js:3889-3896` et `4056-4063`, refus `VALIDATION_RESERVEE` à `parcours.js:3799`, rôles `direction, da, admin` à `parcours.js:3756`). Preuve de l'absence ailleurs : `grep -nE "valideLe *[:=]|validePar *[:=]"` ne trouve, hors fiscalité, que des **valeurs écrites par la semence ou par la migration** (`store.js:2956-2972`, `data-seed.js:3205`, `m13-administration.js:1320`) et les gestes propres à d'autres objets (clôture, paie, imagerie rendue). Aucun bouton ne pose `aValider = false` : les seules écritures de `false` sont `store.js:1608,1640,1671,2957,2970`, `data-tarifs.js:561`, `dashboards.js:5018` et `m13-administration.js:1320`, toutes des graines ou une édition.

## 2. Tableaux par famille

Légende : (a) geste simple, (b) professionnel nommé, (c) tombe par la saisie. Colonne « geste » : Non = aucun bouton.

| Artefact | Marqué (fichier:ligne) | Qui valide | Geste Valider | Où le poser, quel droit | adm-validations |
|---|---|---|---|---|---|
| Modèles d'enquête (b) | `m13-administration.js:1830` (création `aValider: true`), badge `1609-1610`, KPI `1580`, note `1906` | Direction (a) | **Non** : le badge « Proposition à valider » n'a aucune commande | `rowActions` de `tableModeles` (`m13:1604+`) et `editerModele` ; droit direction, da, admin | Non cité (le questionnaire figure en « validées » en texte fixe, `m13:2072`) |
| Variables de résultat labo, ~50 (b) | `data-labo.js:311-545` (`aValider: true`), badge `m5-laboratoire.js:1735`, filtre `1651` | Biologiste médical | **Non**. Les 61 validées le sont par migration, nom et date écrits en dur (`store.js:2967-2972`) | Bouton « Valider la borne » dans `m5-valeurs-reference` (drawer `m5:1917`) ; droit laboratoire en écriture, rôle biologiste | Non (ligne « Bornes suppléées » en texte fixe `m13:2073`) |
| Unités de labo, 9 (b) | `data-labo.js:101-109`, badge `m5-laboratoire.js:1562-1566`, KPI `1586` | Biologiste médical | **Non** | Onglet unités de `m5-valeurs-reference` | Non |
| Plages par lot de réactif (b) | `m13:2014-2018` | Biologiste | Structurel, sans marquage | n/a | Cité, mais le compte est `c('plagesReactif').length` : il compte toutes les plages, pas celles en attente |
| Pathologies, 54 (b) | `data.js:433`, badge `m2-consultations.js:2603`, création `2615` | Médecins, Directeur Médical (rôle `dm`) | **Non** (graine à `store.js:2956-2959`) | `m2-pathologies` : action de ligne « Arrêter » ; droit `dm`, médecin | Non (texte fixe `m13:2074`) |
| Examens et variables d'imagerie, 5 modalités (b) | `data-imagerie.js:65-159` (22 lignes), badge `configuration.js:4467-4471`, note `m2-consultations.js:4617` | Échographiste (et Directeur Médical) | **Non** | `cfg-imagerie-catalogue` (`configuration.js:4455+`) et variables | Non |
| Tarifs d'attente imagerie, 16 (a) | `tarifProvisoire` posé `data.js:1462`, `IMAGERIES_ATTENTE` | Direction | **Non** | Voir actes | Non |
| Check-listes bloc, ASA, Mallampati (b) | `data-clinique.js:177`, arrêtée en dur `292`, note `m3-hospitalisation.js:2075` | Praticiens du bloc | **Non** : `arreteLe` écrit en constante | `m3` écran des check-listes ; droit chirurgien ou anesthésiste | Non (texte fixe `m13:2075`) |
| Actes, tarif d'attente (a) | `data-tarifs.js:373,561`, `store.js:1639-1642` (levé par migration), colonne `configuration.js:979-981`, KPI `866` | Direction | **Non** : « Confirmé » ne peut pas être posé à la main. La création d'un acte neuf n'est même pas marquée | `cfg-tarifs`, action « Arrêter le tarif » ; droit direction, da | Non |
| Analyses, tarif (a) | `configuration.js:957` (`tarifProvisoire = true` à la création), badge `980`, `m5-laboratoire.js:1215,1238` | Direction | **Non** | Idem, même gabarit | Non |
| Valorisation SAGE (a) | `store.js:714`, surcouche `1599-1610`, import sans prix `import.js:212`, icône `m6-stock.js:2933` | Direction, avec gestionnaire de stock | **Non** pour les nouvelles. Les 34 de départ sont confirmées par la semence | `m6` écran de valorisation ; droit direction | Cité en « validées » (texte fixe `m13:2070`) |
| Objectifs de pilotage, 8 (a) | `data.js:1944-1984`, `dashboards.js:4842-5036` | Direction | **Implicite** : l'édition d'une cible pose `aValider:false` (`dashboards.js:5018`). Pas de bouton « Arrêter », et nul besoin de changer la valeur pour l'arrêter. Droit non restreint à la Direction (non vérifié) | Action « Arrêter cette cible » séparée de « Modifier » | Non |
| Répartition fixe/variable des charges (b) | `data.js:1855` (`NATURE_CHARGE.aValider = true`) | Comptable | **Non** | `m12-seuil-rentabilite`, onglet de la répartition ; droit comptable | Non |
| Modèles de badge (a) | `m10-rh.js:5969`, `6394-6395`, création `6416` | Direction | **Non** | `m10-badges-modeles`, droit direction ou da | Non (4 arbitrages badge en texte fixe, `m13:2052-2065`) |
| Jeux d'import « proposition » (a) | `import.js:495,1070,1095` | Direction, gestionnaire de stock | **Non** | `m6-import-grand-stock` | Non |
| Parc technique `aCompleter` (c) | `m13-administration.js:1137`, levé par la saisie `1211` | Ingénierie | **Cas (c), correct** : ne se lève pas par un geste | n/a | Cité (`m13:2009`), motif exact |
| Répertoire ambulances `aCompleter` (c) | `m13-administration.js:848,909` | Accueil | Cas (c) : tombe par la saisie du numéro | n/a | **Non cité** |
| Politique mots de passe, historique (b) | `m14-securite.js:1488,1694` | Direction, administrateur | Texte seul, aucun état | `m14` écran de politique | Non |
| Régime TVA, montants fiscaux, barème ITS (a) | `data.js:723,920,1599`, `mecef.js:768`, `configuration.js:3642,3797` | Direction, DAF, comptable | **Partiel** : identité (dont régime TVA) et obligations ont leur geste ; barème ITS (`data.js:920`) : non vérifié | `cfg-fiscalite`, `cfg-comptabilite` | Oui (deux lignes, `m13:2040-2049`) |
| Modèles de messages (a) | `configuration.js:4165` (texte dans `source`, sans drapeau) | Direction | **Non**, et pas même de drapeau à lever | `cfg-notifications` | Non |
| Groupes d'articles dans les rapports | `rapports.js:449` « proposé, à valider » | Direction | Non. Les quatre groupes sont dits confirmés (`m13:2071`), ce libellé est donc périmé | `rapports.js:449` | n/a |
| Maternité, bornes d'affichage | `data-maternite.js:12` (commentaire seul) | Praticiens de la maternité | **Non vérifié** : aucune entrée portant `aValider` trouvée | n/a | Non |

## 3. Défauts réels

1. **Gravité haute : aucun geste Valider hors fiscalité.** Quinze familles du tableau portent un marquage sans bouton. Un marquage ne peut tomber que par migration de version.
2. **Haute : la validation « écrite » est une constante, pas un geste.** `store.js:2956-2972` écrit `valideLe: '2026-09-01'` et un nom de profil pour toute la liste, à chaque amorçage. Aucune personne n'est nommée, et rien n'est journalisé (RG-12).
3. **Haute : `adm-validations` mentionne tout en texte fixe.** Les neuf lignes « Validées » (`m13:2069-2077`) sont des littéraux, pas un état lu. Les deux familles « professionnels » n'en contiennent que deux, dont l'une compte toutes les plages (`m13:2015`).
4. **Haute : les professionnels ne peuvent pas ouvrir le centre.** `nav.js:585` : `roles: ['da','admin','direction','dm','comptable','surveillant','agentadmin']`. Ni le biologiste ni l'échographiste n'y figurent, alors que la doctrine veut la validation à leur poste.
5. **Moyenne : modifier une borne validée ne la remet pas « à valider »**, contrairement à ce que dit `m5-laboratoire.js:1609`. Le code d'édition (`m5:1946-1952`) ne change que `source`, jamais `aValider`.
6. **Moyenne : la création d'un acte neuf n'est pas marquée** (`configuration.js:1100-1106` demande de laisser le prix vide, mais un prix saisi n'est jamais marqué provisoire). À l'inverse, une analyse créée est marquée (`configuration.js:957`) et ne peut plus être confirmée.
7. **Moyenne : la règle « jamais en masse » est tenue par `adm-validations`** (aucune commande d'écriture, `m13:1954-2149`), mais pas par le reste. `m5-laboratoire.js:672` (« Valider la sélection », confirmation nominative, réservé au biologiste) est un geste humain acceptable. `ged.js:277` valide et signe des documents en lot sans confirmation : à resserrer, cas distinct des marquages.
8. **Faible : textes périmés** : `rapports.js:449`, `data.js:2144-2145` (« tarifs à confirmer »).
9. **Faible : état des objectifs.** Valider = corriger : une cible arrêtée sans changement de valeur est impossible (`dashboards.js:5018`).

## 4. Plan de correction en lots (maquette d'abord)

**Lot 1, moteur commun** (`parcours.js`, à côté de `validerIdentite`) : `PR.validerReferentiel(collection, id, {role})` pose `aValider:false`, `valideLe`, `validePar`, `S.log('Validation', …)` (RG-12), refuse `VALIDATION_RESERVEE` en nommant le rôle attendu. Une table `ROLES_VALIDATION_PAR_FAMILLE` (biologiste pour labo, `dm` et médecin pour pathologies, échographiste et `dm` pour imagerie, chirurgien et anesthésiste pour le bloc, direction, da, admin pour le reste). `PR.referentielsAValider()` compte les fiches en attente par famille, lu par l'écran 3. Un acte de validation par fiche, pas de variante « tout valider ».
**Lot 2, gestes par écran**, un bouton `K.commande` (absent sans droit) : enquêtes (`m13:1604`), variables et unités (`m5:1917, 1562`), pathologies (`m2:2603`), catalogue imagerie (`configuration.js:4467`), actes et analyses (`configuration.js:979, 1175`), objectifs (action « Arrêter » séparée), modèles de badge (`m10:6394`), valorisation SAGE, jeux d'import, répartition des charges. Réparer le défaut 5 (modification d'une borne validée : `aValider:true`, `valideLe:null`, état « modifiée depuis la validation » comme `etatConfigurationFiscale`) et le défaut 6.
**Lot 3, `adm-validations`** : supprimer les littéraux (`m13:2069-2077`), lire `PR.referentielsAValider()`, une ligne par famille avec compte, profil nommé, bouton « Ouvrir ». Ajouter `laborantin` (biologiste), `echographiste`, `chirurgien`, `anesthesiste` aux rôles de `nav.js:585`, en lecture seule. Citer le répertoire des ambulances (cas (c), dit comme le parc technique). Aucun bouton de validation sur cet écran.
**Lot 4, migration** : retirer le bloc de `store.js:2956-2972` ; conserver les validations passées sous la forme de fiches de validation lues par le geste (profil et date réels, ou « validation écrite du 01/09/2026 » comme `source`), incrément de `VERSION` (les fiches sont semées).
**Lot 5, poste Flutter** : reporter `PR.validerReferentiel` dans `packages/domaine`, boutons dans `qual_validations.dart`, `cs_pathologies.dart`, `cr_commun.dart`, parité N1.

**Sondes (un scénario, au clic, sur un jeu où l'on remet les marquages)** :
- S1 enquête : créer un modèle, constater le badge, se connecter en direction, cliquer Valider, badge « Validé », `valideLe` et `validePar` écrits, entrée de journal ; le caissier ne voit aucun bouton ; l'appel moteur renvoie `VALIDATION_RESERVEE`.
- S2 labo : modifier une borne validée, elle repart « à valider » ; le biologiste la valide, le médecin ne le peut pas.
- S3 pathologies, imagerie, bloc, actes, analyses, objectifs, badges : même triplet (geste, refus nommé, journal).
- S4 centre : le compte de chaque famille égale le recompte du magasin avant et après un geste ; aucune commande d'écriture n'existe sur l'écran ; le biologiste y accède.
- S5 cas (c) : saisir marque, série et mise en service lève `aCompleter` sans bouton.

## 5. Questions pour la Direction

1. Qui valide les modèles d'enquête et les modèles de badge : la Direction seule, ou aussi la DAF ?
2. Une validation donnée le 01/09/2026 sans nom : la reconduit-on avec la mention « validation écrite du 01/09 », ou chacun revalide-t-il à son poste ?
3. Modifier une borne ou un tarif déjà validé doit-il les remettre « à valider », comme pour la fiscalité ?
4. Le biologiste, l'échographiste et les praticiens du bloc doivent-ils voir le centre des validations ?
5. Le barème ITS (`data.js:920`) doit-il rejoindre le geste de `cfg-comptabilite` ?

Audit lu seulement, aucun code modifié
