# SPEC : configuration fiscale validée (identité légale et obligations fiscales)

PRD : `docs/prd/PRD-POSTE-premiere-installation.md` (étape « Configurer la clinique ») · Module : CFG (écrans `cfg-branding`, `cfg-fiscalite`, `cfg-comptabilite`, `cfg-entetes` ; lecteurs : `print.js`, M8, M11, M12, M13) · Domaine du ruban : Système, « Configuration Clinique » · Statut : **décidée par la Direction le 06/11/2026, à mettre en œuvre (scénario « Vague 81 »)**.

**Ce que la Direction a tranché le 06/11/2026** : l'identité légale et les obligations fiscales se VÉRIFIENT et se VALIDENT à la première configuration, sous forme d'un formulaire modifiable, puis restent modifiables ensuite par versions datées avec historique. Le coffre de récupération garde UNE seule adresse (déjà fait, hors de cette spec). Le secteur ADMINISTRATION des demandes semées (E2262) n'est pas touché.

**Ce que la spec corrige** : `cfg-branding` « enregistre » sans rien persister (un `S.log` et un toast, `C.BRAND` reste une constante de `core.js`) ; `cfg-fiscalite` et `cfg-comptabilite` lisent `C.BRAND` et `D.CALENDRIER_FISCAL` en dur ; `calculOrtb(brut, mois)` lit `D.PARAM_PAIE.ortb` sans date ; la détection d'installation du poste tient une configuration pour « faite » dès qu'une écriture la concerne. Rien n'y est validé par personne.

## 1. Rôle des écrans

| Écran | On y fait | On n'y fait PAS (renvoi) |
|---|---|---|
| `cfg-branding` | Saisir et enregistrer la part VISIBLE de l'identité : nom, sigle, slogan, logo, adresse géographique, téléphones (dont la ligne rendez-vous), courriel. Options d'impression. | Les mentions FISCALES (IFU, RCCM, forme, autorisation, adresse fiscale, devise, TVA) : `cfg-fiscalite`. La validation. |
| `cfg-fiscalite` | Saisir la part FISCALE de l'identité (la MÊME fiche que `cfg-branding`, ses champs à lui) et **Valider** l'identité légale. Bandeau d'état. Numérotation et calendrier en lecture. | Modifier la numérotation des documents (hors périmètre). Le MECeF (`mecef-config`). |
| `cfg-comptabilite` | Lire la référence documentaire des obligations, **modifier une obligation ou les paramètres ORTB à une date d'effet**, **Valider** les obligations. Bandeau d'état. | Payer ou suivre une échéance : `m12-echeances`. Modifier CNSS, VPS, ITS (lecture seule, CDCT). |
| `cfg-entetes` | Lire l'en-tête RÉSULTANT (identité en force aujourd'hui) et son état de validation. | Écrire quoi que ce soit. |
| `adm-validations` | Orienter : deux lignes « à valider » dans la famille des arbitrages de la Direction. | Valider en masse. |

## 2. Droits

CFG est ouvert au manifeste à `admin`, `da`, `direction` ; la fiche RBAC21 (`direction`) porte `CFG: { editer: true, annuler: false }` ; `da` et `admin` n'ont aucune surcharge sur CFG. Un écran l'emporte sur son module ; une surcharge accorde autant qu'elle restreint. Les commandes passent par `K.commande` (ABSENTE sans droit, jamais grisée) et le moteur refait le contrôle (un refus se nomme : `code`, `motif`, `geste`).

| Rôle | voir | Enregistrer (éditer) | Valider | Archiver une obligation (annuler) | Ce que le rôle restreint voit |
|---|---|---|---|---|---|
| `admin` | oui | oui | oui | oui | tout |
| `da` | oui | oui | oui | oui | tout |
| `direction` | oui | oui | oui | non | « Retirer » absent ; le bandeau dit que le retrait appartient à la DAF ou à l'administrateur |
| `comptable`, `aide_comptable`, `assistant_comptable` | non (CFG fermé) | non | non | non | lisent les échéances à `m12-echeances` et l'ORTB sur le bulletin ; le bouton « Obligations & règles » de M12 mène au 403 nommé, comme aujourd'hui |
| `reception` | non (`cfg-tarifs` seul, lecture) | non | non | non | rien de ce chantier |
| tout rôle sur un **fileul** | oui (si CFG ouvert) | non | non | non | bandeau « Configuration tenue par la mère : lecture seule », commandes absentes |

Refus du moteur (défense en profondeur, même si l'écran a masqué la commande) : `VALIDATION_RESERVEE` (« La validation de la configuration fiscale est réservée à la Direction, à la DAF et à l'administrateur système. Profil : X. ») ; `FILEUL_LECTURE_SEULE` (« Cette configuration est tenue par la mère ; modifiez-la sur le poste mère. ») ; `EXERCICE_CLOS` (« La date d'effet tombe dans un exercice clos ; choisissez une date de l'exercice ouvert. »).

## 3. Données

Trois collections nouvelles, toutes **semées au socle** (`store.seed()`) : elles sont lues par CFG, `print.js`, M8, M11, M12 et M13 (piège de l'amorçage par écran). `VERSION` passe de **68 à 69, une seule fois** pour tout le chantier : le schéma complet (les trois collections) est posé dès la phase 1. Les trois sont ajoutées à `LIBELLES` (corbeille) et à `COLLECTIONS_ESSENTIELLES` (section « Règles datées ») ; elles survivent au vidage des jeux de test. Archivage RG-14 partout ; une version n'est jamais réécrite ni supprimée.

### 3.1 `identiteLegale` : les versions datées de l'identité (UNE source, `C.BRAND` devient un miroir)

Une fiche par VERSION. Champs : `id` (attribué par le magasin ; UUID v7 au poste), `version` (entier croissant), `debut` (ISO ou **`null` = depuis l'ouverture du dossier**), `fin` (ISO ou `null` = en force), `creeLe`, `creePar`, `motif` (obligatoire dès la version 2), `valideLe`, `validePar` (null tant que non validée), puis les champs de `C.BRAND`, mêmes noms : `sigle`, `nom`, `slogan`, `forme`, `adresse`, `bp`, `pays`, `telephones` (tableau), `telephoneRdv`, `email`, `ifu`, `rccm`, `autorisation`, `autorisationExercice` (null), `autorisationExerciceMotif`, `devise`, `codeDevise`, `logo`, `formuleArrete`, `formulePolitesse`, et le nouveau `regimeTva` (texte, défaut « Taux normal 18 % », celui que `cfg-fiscalite` affiche aujourd'hui).

- **Semis** : version 1, `debut: null`, copie de `C.BRAND` d'origine, `source: 'core.js, arbitrage du 31/08/2026'`, `valideLe: null`.
- **Qui écrit quoi** : `cfg-branding` écrit `nom`, `sigle`, `slogan`, `logo`, `adresse`, `pays`, `telephones`, `telephoneRdv`, `email` ; `cfg-fiscalite` écrit `forme`, `ifu`, `rccm`, `autorisation`, `bp` (adresse fiscale), `devise`, `codeDevise`, `regimeTva`. `autorisationExercice`, `formuleArrete`, `formulePolitesse` restent hors formulaire (copiés tels quels de version en version).
- **Enregistrer** : AVANT la première validation, « Enregistrer » MODIFIE la version en force (c'est la première configuration : on corrige un brouillon). APRÈS une validation, « Enregistrer » ouvre la modale **« Portée de la modification »** : date d'effet (défaut : aujourd'hui ; jamais antérieure à `debut` de la version en force) et motif obligatoires ; la version en force reçoit `fin = date d'effet - 1 jour`, une nouvelle version naît avec `debut = date d'effet`, `valideLe: null`. L'ancienne reste.
- **`S.appliquerIdentite()`** : au chargement du magasin, après toute écriture dans `identiteLegale` et à chaque relecture de la collection par le sondage inter-postes, la version en force AUJOURD'HUI est écrasée **dans l'objet `C.BRAND` en place** (`Object.assign(C.BRAND, version)`, jamais une réaffectation : `print.js:15` et `core.js:182` ont capturé la référence). Sans magasin (`file:`, premier amorçage), `C.BRAND` garde ses valeurs d'origine.
- **`C.identiteALaDate(date)`** : la version dont `debut <= date` (ou `debut null`) et (`fin null` ou `date <= fin`) ; aucune version couvrante (date antérieure à toute version) : la version 1. Lit le magasin à l'appel, repli `C.BRAND` d'origine (le modèle de `D.NS132.montant`).
- Options d'impression de `cfg-branding` : hors fiche. `doubleLogo` et `filigrane` deviennent des réglages d'exploitation (`S.setReglage('impression.doubleLogo')`, `'impression.filigrane'`) LUS par `print.js` ; la case « Pied de page normalisé » est RETIRÉE (le pied est obligatoire : date, utilisateur, identifiant, RG-12). Un réglage que rien ne lit est un mensonge.

### 3.2 `obligationsFiscales` : la version en vigueur de chaque obligation, plus les paramètres ORTB

Une fiche par obligation (`type: 'obligation'`), semée depuis `D.CALENDRIER_FISCAL` : `id`, `code` (ITS, AIB, VPS, CNSS, IS-1..IS-4, IS-SOLDE, ETATS-FIN, PATENTE-DECL/1/2, CCIB-DECL/1/2, TVM, ORTB-RADIO, ORTB-TELE), `libelle`, `famille` (préfixe du code), `periodicite` (`'mensuelle'` | `'annuelle'`), `jour`, `mois` (0 à 11, null si mensuelle), `part` (% ou null), `declaration` (texte ou null), `note`, `source`, `dateEffet` (null au semis = depuis l'ouverture), `modifieLe`, `modifiePar`, `motif`, `valideLe`, `validePar`, `statut`.

Une fiche de paramètres (`type: 'parametres'`, `code: 'ORTB-PARAMETRES'`), semée depuis `D.PARAM_PAIE.ortb` : `seuilTele` (60000), `redevances` (tableau de deux : `id`, `code`, `categorie`, `libelle`, `montant`, `mois`, `moisLabel`, `seuilMin`, `seuilMax`, `assiette`), `cumulMaximum`, `source`, et les mêmes champs de version et de validation. **Les deux redevances se CUMULENT** (4 000 F au-dessus du seuil) : la fiche porte deux lignes, jamais deux tranches.

Hors de la fiche et **hors du formulaire** : les taux CNSS 16,4 % / 3,6 %, la VPS 4 % et le barème ITS restent `D.PARAM_PAIE` et sont AFFICHÉS « arrêtés par le CDCT §10.10, lecture seule » sur `cfg-comptabilite`. Les rendre datés est un P2 nommé en §9.

### 3.3 `historiqueObligations` : les versions antérieures (le modèle `grillePrimes` / `historiquePrimes`)

Vide au semis. À chaque modification d'une fiche de `obligationsFiscales` : copie de la fiche AVANT modification, plus `obligationId`, `dateEffet` (le `dateEffet` qu'elle portait), `dateFin` (date d'effet de la nouvelle version moins un jour), `remplaceeLe`, `remplaceePar`, `motif`. Une obligation RETIRÉE (archivée, `annuler`) laisse sa dernière version dans l'historique avec `dateFin` = date d'effet du retrait moins un jour et `retiree: true`.

- **`D.obligationsALaDate(date)`** : pour chaque `code`, la fiche courante si `dateEffet null` ou `date >= dateEffet` ; sinon la version de l'historique qui couvre `date` ; un code sans version couvrante est ABSENT à cette date (obligation créée plus tard, ou retirée). Repli sans magasin : `D.CALENDRIER_FISCAL`.
- **`D.ortbALaDate(date)`** : même règle sur la fiche `ORTB-PARAMETRES` ; repli `D.PARAM_PAIE.ortb`.
- **Modale « Portée de la modification »** (reprise de `m10-rh.js:946`) sur toute modification ou retrait : **date d'effet** (défaut : aujourd'hui ; refusée dans un exercice clos, `EXERCICE_CLOS` ; refusée avant le `dateEffet` de la version courante) et **motif** obligatoires. Elle annonce, pour l'exercice courant, « N échéance(s) payée(s) CONSERVÉE(S), M échéance(s) non payée(s) RÉGÉNÉRÉE(S) ». **L'option rétroactive « y compris les échéances payées » N'EXISTE PAS ici** : une échéance payée ne bouge jamais.

### 3.4 Ce qui change sur `echeancesFiscales` (collection DÉRIVÉE, inchangée de statut)

Chaque échéance gagne `versionObligation` (le `dateEffet` de la version qui l'a engendrée, null pour la version d'origine), `regenereeLe`, `regenereePar`. `genEcheances(exercice)` (store.js) et `amorcerEcheances()` (m12-comptabilite.js:3275) lisent, pour CHAQUE date théorique d'échéance, `D.obligationsALaDate(dateTheorique)` : une version qui change en cours d'exercice ne touche que les échéances postérieures à sa date d'effet. `S.regenererEcheances({ code, dateEffet, auteur })` archive (RG-14) les échéances du code non payées dont l'échéance théorique est `>= dateEffet` et les recrée depuis la nouvelle version ; les payées sont intouchées ; le geste est journalisé (`S.log('Régénération des échéances', 'M12', 'EcheancesFiscales', code, { avant }, { apres })`) et annoncé par toast avec les deux comptes.

### 3.5 ORTB daté

`calculOrtb(brut, mois, date)` (m11-paie.js:87) lit `D.ortbALaDate(date)` ; `date` est la date du bulletin (premier jour de la période de paie) ; sans `date`, aujourd'hui (compatibilité). Un bulletin déjà calculé n'est jamais recalculé : il garde ses lignes ORTB. `m11-paie` passe la date du bulletin aux deux appels (calcul et lignes de retenue).

## 4. Règles

- **Une pièce émise ne se réécrit jamais ; une donnée de référence qui change se versionne par date.** Aucune écriture n'écrase une version validée.
- **Contrôles AVANT écriture, refus nommés** : champs obligatoires de l'identité (`nom`, `ifu`, `rccm`) ; IFU à 13 chiffres (format relevé sur les pièces, refus « L'IFU compte 13 chiffres ») ; au moins un téléphone ; motif obligatoire sur toute version 2 et suivantes ; date d'effet hors exercice clos ; `jour` entre 1 et 31, `mois` entre 0 et 11 pour une annuelle, `part` entre 1 et 100 ou null ; une obligation nouvelle exige un `code` unique en majuscules (refus « Le code X existe déjà »).
- **Validation** : `PR.validerIdentite()` et `PR.validerObligations()` (parcours.js, exposés `SIGH.configurationFiscale` pour être SONDÉS) : contrôle du rôle (`direction`, `da`, `admin`), puis `valideLe = C.iso(aujourd'hui)`, `validePar = S.currentUser()` sur la version en force ET sur les versions à venir (identité), sur toutes les fiches actives (obligations) ; `S.log('Validation', 'CFG', 'IdentiteLegale' | 'ObligationsFiscales', id, null, { valideLe, validePar })`. Valider ne modifie aucun autre champ.
- **État affiché** (fonction unique `PR.etatConfigurationFiscale(nom)` → `{ etat, valideLe, validePar, modifieLe }`) : `a_valider` (aucune fiche active ne porte `valideLe` et aucune validation antérieure n'existe) ; `valide` (toutes les fiches actives portent `valideLe`) ; `modifie_depuis` (au moins une fiche active sans `valideLe` et une validation antérieure existe : le bandeau dit « Modifié le D par P depuis la validation du D0 par P0 », RG-12). Le bandeau est posé sur `cfg-fiscalite`, `cfg-comptabilite`, `cfg-entetes` ET `cfg-branding` (il écrit la même fiche que `cfg-fiscalite` : une modification y remet l'état à `modifie_depuis`).
- **`adm-validations`** : deux lignes dans la famille `arbitrages` (« Identité légale à valider (première configuration) », écran `cfg-fiscalite` ; « Obligations fiscales à valider », écran `cfg-comptabilite`), affichées tant que l'état n'est pas `valide`, avec l'état en `attente`. Elles disparaissent une fois validé ; elles reviennent sur `modifie_depuis`.
- **Le formulaire de `cfg-branding` cesse de mentir** : « Enregistrer » écrit la fiche ; le toast nomme la version et dit si une validation est à refaire. Un rechargement relit la valeur saisie.
- **La table « Obligations déclaratives » de `cfg-fiscalite`** cesse d'être écrite en dur : elle se dérive des obligations mensuelles en vigueur (CNSS le 10, et non « 15 du mois suivant » comme la table actuelle l'affirme contre le calendrier), plus les deux lignes MECeF et états financiers.
- **Totaux** : aucun montant totalisé ici ; les montants (CCIB 300 000, ORTB) sont des paramètres, jamais sommés.

## 5. Parcours et événements

Émis : journal RG-12 pour chaque enregistrement, version, validation, régénération ; tâche de poste « Échéances régénérées : code, N » adressée au poste Comptable (`PR.notifier`, collection `notifications`) ; rien n'écrit au journal comptable. Consommé : `echeancesFiscales` (m12-echeances, dash-direction), bulletins de paie (`calculOrtb`), tout état imprimé (`entete()`), `adm-validations`, l'assistant d'installation du poste.

## 6. Hors ligne et synchronisation

Les trois collections sont de la **configuration de la clinique** : famille **R**, publiées par la MÈRE SEULE (`POST /admin/referentiel`, via `cfbEssentielles` régénérée) ; un fileul les reçoit par la synchronisation et les applique à son magasin ; ses écrans sont en lecture seule nommée (`cfaLectureSeule`) et le moteur refuse l'écriture (`FILEUL_LECTURE_SEULE`). Les mobiles reçoivent l'identité (ils impriment un en-tête) ; aucun haché n'y voyage (RG-13, inchangé). Sans relais, la mère écrit localement et publie à la reconnexion ; un fileul coupé garde la dernière configuration reçue et l'en-tête qu'il imprime est celui de sa dernière version connue. Aucune tranche de numéros n'est nécessaire (les versions sont des entiers locaux à la mère, qui seule écrit). Dans la maquette (PostgreSQL partagé), la projection relationnelle suit : `psql -At -c "select json_object_agg(nom, donnees) from collections" > magasin.json && node build/gen-schema-pg.js magasin.json`, puis `php api/projection.php` (tables `cfg.identite_legale`, `cfg.obligations_fiscales`, `cfg.historique_obligations`, module lu dans `collection('x', { module: 'CFG' })`).

## 7. Impression

`P.etat(o)` et `P.ticket(o)` acceptent **`date`** (ISO) : l'en-tête et le pied s'impriment avec `C.identiteALaDate(o.date)` ; sans `date`, l'identité en force aujourd'hui (le `C.BRAND` écrasé en place). Appelants qui passent LEUR date : la **facture normalisée et pro-forma** (m8-facturation.js, `P.etat` « Facture normalisée », `date: f.date`), le **ticket de caisse** (`P.ticket`, `date: f.date`), les deux **reçus de paiement** (« Reçu de paiement », date du versement), la **facture d'avoir** (écran `m8-facture-avoir`, « FACTURE D'AVOIR », `date: avoir.date`), la **facture MECeF** (mecef.js, « Facture de vente, normalisée », `date: f.date`). Tous les autres états portent l'identité du jour. Le gabarit CR80 des badges ne porte ni IFU ni RCCM (inchangé). `filtres: false` reste sur les pièces. Le logo d'une version est un chemin de ressource, pas un fichier dans la fiche.

## 8. Sondes

Scénario **« Vague 81 »** (`build/test-fonctionnel.js`, `node build/test-fonctionnel.js --seul=Vague_81`), au geste :

1. `cfg-branding` : saisir un slogan et un téléphone, Enregistrer, RECHARGER la page : les valeurs saisies sont relues ; `C.BRAND.slogan` vaut la saisie ; l'en-tête d'un état imprimé (`P.etat` sans date) porte le nouveau slogan.
2. Validation refusée à la `reception` (commande ABSENTE à l'écran ET `SIGH.configurationFiscale.validerIdentite()` rend `VALIDATION_RESERVEE`), acceptée à la `da` : bandeau « Validé le … par … » sur `cfg-fiscalite`, `cfg-entetes`, `cfg-branding` ; `adm-validations` ne porte plus la ligne « Identité légale à valider ».
3. Nouvelle version de l'identité à une date d'effet FUTURE (IFU inchangé, RCCM modifié) : `C.BRAND.rccm` reste l'ancien ; une facture datée d'hier imprime l'ancien RCCM, un état daté après la date d'effet imprime le nouveau ; `cfg-fiscalite` passe à « Modifié depuis la validation du … » et `adm-validations` reporte la ligne.
4. Obligations : modifier `CCIB-2` (jour 10 → 15) à une date d'effet du 1er du mois courant : l'échéance CCIB-1 PAYÉE garde sa date et sa quittance ; l'échéance CCIB-2 non payée est archivée et recréée au 15 (reportée au jour ouvrable si besoin), `versionObligation` posé ; une entrée de journal « Régénération des échéances » existe ; `historiqueObligations` porte la version d'origine avec `dateFin`. La date d'effet dans un exercice clos est refusée (`EXERCICE_CLOS`).
5. ORTB : passer `seuilTele` à 80 000 à une date d'effet du mois courant ; `calculOrtb(70000, 5, dateAncienne)` rend la télé due, `calculOrtb(70000, 5, dateNouvelle)` ne la rend pas ; la radio reste due dans les deux cas ; un bulletin de juin déjà émis garde ses 3 000 F.
6. Parité N1 : `node build/extraire-ecrans.js` puis `flutter test test/parite_ecrans_test.dart` restent à 100 % pour les quatre écrans.
7. Le scénario RESTAURE l'état : versions créées archivées, rôle de session rendu, validation d'origine rétablie (un scénario qui mute la configuration la restaure, sans la recopier).

Vecteurs : `build/vecteurs-cfg-b.js` capture quatre cas nouveaux dans `packages/domaine/test/vecteurs/cfb.json` (`identiteALaDate` sur deux versions et trois dates ; `obligationsALaDate` sur une modification datée et trois dates ; `echeancesVersion` : exercice avec changement en cours d'année, payée conservée, non payée régénérée ; `calculOrtbDate` : seuil changé, bulletin ancien inchangé), rejoués par `test/cfb_regles_test.dart` et `test/paie_test.dart` (`cfbIdentiteALaDate`, `cfbObligationsALaDate`, `cfbOrtbALaDate`, `paiCalculOrtb(brut, mois, date, parametres)`). Tests Flutter : `cfg_identite_test.dart` (formulaire persiste, rechargement), `cfg_fiscal_test.dart` (champs fiscaux, Valider, refus nommé, bandeau), `installation_service_test.dart` (détection par VALIDATION : une écriture seule ne suffit plus, « vérifié » non plus), `pai_ortb` et `cpc_echeances` lisant le magasin.

**Mutations à prouver** (chaque sonde doit passer au rouge quand on les applique, puis au vert) : retirer l'`Object.assign` de `S.appliquerIdentite()` (sonde 1 et 3) ; rendre la validation libre (retirer le contrôle de rôle du moteur : sonde 2) ; ignorer `date` dans `calculOrtb` (sonde 5 et vecteur `calculOrtbDate`) ; régénérer aussi les échéances payées (sonde 4) ; lire `D.CALENDRIER_FISCAL` au lieu de `D.obligationsALaDate` dans `genEcheances` (vecteur `echeancesVersion`) ; faire passer la détection d'installation sur une écriture sans validation (test Flutter).

## 9. Phases, écarts et périmètre

| Phase | Contenu | Écarts (E2270 à E2279, réservés) |
|---|---|---|
| 1 Maquette, identité | Trois collections semées, `VERSION` 69, `LIBELLES`, `COLLECTIONS_ESSENTIELLES`, `S.appliquerIdentite`, `C.identiteALaDate`, `cfg-branding` qui persiste, `cfg-fiscalite` en formulaire, `P.etat`/`P.ticket` datés sur les cinq pièces | E2270 (`cfg-branding` mentait : constat et correction), E2271 (options d'impression : `doubleLogo`/`filigrane` persistés et lus, `piedPage` retiré), E2272 (`regimeTva` « Taux normal 18 % » porté tel qu'affiché, en divergence avec `mecef-config` qui applique l'exonération : SIGNALÉ, non arbitré) |
| 2 Maquette, obligations et ORTB | `obligationsFiscales` en formulaire, modale de portée, `historiqueObligations`, `D.obligationsALaDate`, `D.ortbALaDate`, `genEcheances`/`amorcerEcheances` datés, `S.regenererEcheances`, `calculOrtb(brut, mois, date)`, table déclarative dérivée | E2273 (obligations datées et régénération ; la table de `cfg-fiscalite` disait CNSS « le 15 » contre le calendrier), E2274 (ORTB daté) |
| 3 Maquette, validation | `SIGH.configurationFiscale`, bandeaux, `adm-validations`, scénario « Vague 81 », vecteurs étendus, `node build/check.js --pages=cfg-,adm-,m12-`, `node build/audit-rbac.js --roles=admin,da,comptable,reception`, `docs/architecture/parite-statuts.json` | E2275 |
| 4 Domaine Dart | `cfb_donnees.dart` régénéré (`gen-cfb-donnees.js` : `cfbEssentielles` suit), `cfbIdentiteALaDate`, `cfbObligationsALaDate`, `cfbOrtbALaDate`, `paiCalculOrtb` daté, `IdentiteClinique` devient la SEMENCE et l'impression lit la version en force, `dart test` | E2276 |
| 5 Poste Flutter | `cfa_identite.dart` et `cfb_fiscal.dart` en formulaire, Valider, bandeaux, `pai_ortb.dart` et `cpc_echeances.dart` lisent le magasin, `ins_modale.dart` ajoute (`'cfg-fiscalite'`, `'Paramètres fiscaux (IFU / RCCM)'`), `service_installation.dart` : `collectionsDesConfigurations` → `'cfg-fiscalite': {'identiteLegale'}`, `'cfg-comptabilite': {'obligationsFiscales'}` et, pour ces deux lignes SEULES, « faite » = toutes les fiches actives portent `valideLe` (ni une écriture, ni `lignesVerifiees` ne comptent) ; jeu `apps/poste/assets/donnees/jeu/{identiteLegale,obligationsFiscales,historiqueObligations}.json` via `build/gen-poste-jeu.js` ; `flutter test` complet UNE fois | E2277 (poste), E2278 (fileul lecture seule nommée et famille R des trois collections) |
| Clôture | Ce qui n'a PAS été vérifié (projection PostgreSQL rejouée, Windows, DPAPI, charge) | E2279 |

**Hors périmètre, dit** : taux CNSS 16,4/3,6, VPS 4 % et barème ITS datés (P2 : même modèle, fiche `type: 'parametres'` supplémentaire) ; la numérotation des documents (table de `cfg-fiscalite`, lecture) ; le MECeF (`mecef-config`, boîtier, régime de TVA appliqué) ; les variantes d'en-tête (retirées le 31/08/2026, ne reviennent pas) ; les rôles et leurs fiches ; le secteur ADMINISTRATION des demandes semées (E2262).

**Ce qui reste à valider, et par qui** : la Direction valide l'identité et les obligations À L'ÉCRAN (c'est l'objet de la spec) ; le cabinet comptable confirme les montants CCIB et ORTB (`MONTANTS_FISCAUX` reste marqué « à confirmer ») ; le régime de TVA affiché attend l'arbitrage Direction / comptable (E2272). En attendant, les bandeaux disent « À valider » et `adm-validations` porte les deux lignes.
