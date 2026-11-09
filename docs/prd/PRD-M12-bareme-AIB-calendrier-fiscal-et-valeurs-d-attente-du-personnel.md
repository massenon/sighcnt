# PRD : Barème AIB daté, vérification du calendrier fiscal et valeurs d'attente de la fiche de poste

Statut : **brouillon du 09/11/2026**, à arrêter par la Direction (questions de la section 10).
Sources : message de la Direction du 09/11/2026 (texte remis, décrivant trois chantiers) ; CLAUDE.md (vague 13 « un moteur daté, une correction ajoute une version », vague 19 grille des primes datée, vague 33 « diagnostic, pas gommage », calendrier fiscal confirmé le 25/08/2026, vague 49 tarifs d'attente) ; `docs/prd/PRD-MECEF-facturation-normalisee-deux-modes.md` (Q4 : taux d'AIB par défaut).

**Ce que ce PRD constate avant d'écrire (inventaire du dépôt, mesuré le 09/11/2026)** :
- Il n'existe **aucun barème AIB versionné** dans la maquette : `data.js` ne porte qu'un paramètre fixe `aib: { taux: 1, code: 'AIB2' }` et une échéance mensuelle. Le texte remis parle d'un formulaire « porté depuis l'écran de la maquette » : cet écran n'existe pas ici, il est donc à **créer**, maquette d'abord.
- Les valeurs de départ du texte remis (5 % arrêté, généralisé à compter du 07/09/2026 ; 1 % et 3 % non arrêtés) ne figurent dans **aucun document du dépôt**. Elles sont reprises comme **proposition à valider**, avec pour source le message de la Direction, jusqu'à la production du texte réglementaire.
- Le calendrier fiscal du dépôt (`D.CALENDRIER_FISCAL`) place la **CNSS au 10** et ce calendrier a été **confirmé par la Direction le 25/08/2026**. Le texte remis dit « la CNSS est bien au 15 » : les deux se contredisent (question Q2).
- Aucune notion de **salaire d'attente** n'existe sur les fiches de M10 : pas de marquage « provisoire » sur le salaire, la date d'embauche, la CNSS ou le tarif de vacation. À créer ou à constater (question Q4).

## Recherches du 09/11/2026 (sources publiques, à confirmer auprès de la DGI)

Recherche faite à la demande de la Direction. **Aucune source officielle primaire n'a pu être ouverte** (les sites `impots.finances.gouv.bj` et `beninwebtv.bj` sont hors du réseau autorisé de la session) ; ce qui suit vient d'extraits de presse béninoise et de pages de la CNSS vues par moteur de recherche. À confirmer avant tout arrêt.

- **AIB à 5 %, généralisé au 07/09/2026** : un communiqué de la DGI (daté du 3 ou 4 septembre 2026 selon les articles) généralise le prélèvement de l'AIB à **5 %**, **à l'émission des factures normalisées**, pour les contribuables **non conformes ou non immatriculés** (IFU désactivé, personnes morales comprises, entreprises individuelles et professions libérales). Il s'appuie sur les articles 132 d) et 135 du Code général des impôts. Il cesse à la régularisation (réactivation de l'IFU) ; une entreprise connue qui l'a subi par non-conformité passagère peut demander une **compensation**. L'AIB est **imputable sur l'impôt sur les bénéfices**, ce n'est pas un impôt supplémentaire. **Ce n'est donc pas un taux unique pour tous les acheteurs** : le 5 % vise la situation de l'acheteur.
- **1 %, 3 %** (source de 2022, à reconfirmer pour 2026) : ventes en gros et demi-gros par importateurs, producteurs et revendeurs : **1 %** si le client est immatriculé à l'IFU, **5 %** sinon ; prestations de services : **3 %**, fournitures de travaux : 1 %, retenu par l'organisme payeur sur le prix hors taxe de la facture au paiement.
- **CNSS** : la page « Déclaration et paiement » de la CNSS dit que les cotisations se versent « dans les quinze jours qui suivent la période » (mensuel pour 20 salariés et plus, trimestriel en dessous) ; la **déclaration unique** des impôts sur salaires et des cotisations sociales est, selon la DGI, due **au plus tard le 10 du mois suivant**. Les deux dates coexistent donc pour deux obligations proches : notre calendrier (10, confirmé le 25/08) suit la déclaration unique. Des guides secondaires citent tantôt le 10, tantôt le 15 : ils ne font pas foi.
- **Loi n° 2026-10** modifiant la loi de finances 2026 (publiée le 31 juillet 2026) : non lue, son effet sur l'AIB n'est pas vérifié.

Sources : [La Nouvelle Tribune, AIB de 5 %](https://lanouvelletribune.info/2026/09/benin-aib-de-5-ce-qui-change-selon-le-dgi-maxime-mensah-akakpo-djihountry/) ; [BeninWebTV, recouvrement de l'AIB au 7 septembre](https://beninwebtv.bj/recouvrement-de-laib-au-benin-ce-qui-change-a-partir-de-ce-lundi-7-septembre/) ; [BeninWebTV, généralisation du prélèvement de 5 %](https://beninwebtv.bj/dgi-generalisation-du-prelevement-de-5-daib-pour-les-contribuables-non-conformes-ou-non-immatricules-a-compter-du-7-septembre-2026/) ; [La Nouvelle Tribune, modalités AIB 2022](https://lanouvelletribune.info/2022/03/benin-le-dgi-yenoussi-devoile-les-modalites-dapplication-des-dispositions-fiscales-de-laib/) ; [CNSS, déclaration et paiement](https://cnss.bj/declaration-et-paiement/) ; [CNSS, déclaration unique](https://cnss.bj/communique/declaration-unique-des-impots-sur-salaires-et-des-cotisations-sociales/) ; [Bloomberg Tax, loi 2026-10](https://news.bloombergtax.com/daily-tax-report-international/benin-tax-agency-posts-law-amending-2026-finance-law).

### Complément du 09/11/2026 (texte remis par la Direction, à confirmer avec l'expert-comptable)

Le texte remis confirme et précise, sans source officielle ouverte non plus :
- **Base de calcul de l'AIB : le montant hors taxes** de la facture normalisée. Le moteur de la maquette calcule déjà sur le hors taxes (`ht = base / (1 + TVA)`, soit la base elle-même tant que la TVA vaut 0 pour les produits de santé exonérés) ; un champ « hors taxes » explicite sur les lignes de facture reste à ajouter si la TVA devient applicable à certaines prestations.
- **3 % pour les prestataires** : confirmé par un seul extrait de rescrit de 2026 ; **1 %** : source de 2022 ; tous deux restent **non arrêtés**.
- **CNSS : deux obligations distinctes** : la **déclaration unique** des impôts sur salaires et cotisations est due le **10** ; le **versement** des cotisations CNSS se fait **dans les quinze jours**, soit le **15**. L'ancienne table déclarative de `cfg-fiscalite` disait « CNSS le 15 » et le calendrier « le 10 » : E2273 les a alignées sur le 10 ; ces deux dates ne se contredisent donc pas, elles visent deux gestes (question Q6).
- **Resté ouvert** : les sources ne disent pas **qui supporte** le prélèvement de 5 % (le client qui est prélevé ou la clinique) : il faut le texte du communiqué (question Q7).
- **Taux de TVA de 18 % sur tout** : toujours à confirmer par écrit ; le dépôt applique l'exonération des produits de santé (facture certifiée de référence).
- Les autres échéances relevées dans le document remis sont jugées peu fiables : à ne pas reprendre sans texte.

## 1. Problème

1. L'AIB (acompte sur impôt assis sur les bénéfices) est un paramètre figé à 1 % dans le code : un changement de taux (le texte remis annonce 5 % généralisé au 07/09/2026) écraserait le taux sous lequel des factures ont été émises, alors que `docs/prd` MECeF fait déjà dire à la fenêtre acheteur « 5 % par défaut, 1 %, aucun ». Sans barème daté, la maquette ne sait pas répondre à « quel taux ce jour-là ».
2. Le calendrier fiscal existe en deux écrans (`cfg-comptabilite` référence, `m12-echeances` suivi) ; la Direction demande de **vérifier** leur cohérence écran par écran, sans en changer les règles confirmées.
3. Les valeurs d'attente (salaire, date d'embauche, CNSS, tarif de vacation) d'une fiche de personnel ne se distinguent pas des valeurs validées : un salaire saisi par défaut se lit comme un salaire arrêté (doctrine tarifs d'attente, vague 49).

## 2. Objectifs et non-objectifs

Objectifs (un critère de recette chacun) :
- O1. **Barème AIB daté** : collection versionnée par date d'effet, CRUD complet (une correction ajoute une version, rien n'est écrasé), moteur `tauxAibALaDate(date)`. Critère : trois dates donnent trois taux attendus, l'historique reste lisible.
- O2. Droits : écriture au **comptable**, lecture à la **Direction** ; commande absente sinon (jamais grisée). Critère : audit RBAC, 0 promesse.
- O3. Marquage **« non arrêté »** des taux sans texte réglementaire, affiché à l'écran, comme `tarifProvisoire`. Critère : 1 % et 3 % portent le marquage, 5 % porte sa date d'arrêt.
- O4. **Vérification du calendrier fiscal** : rapport écran par écran (existence, semis à l'ouverture, jours de dépôt, suivi peuplé), sans modifier une règle confirmée. Critère : rapport d'écarts chiffré.
- O5. **Valeurs d'attente du personnel** : salaire, date d'embauche, CNSS, tarif de vacation modifiables sur les fiches de M10 ; modifier une valeur d'attente retire son marquage et est journalisé (RG-12). Critère : sonde au geste.

Non-objectifs :
- Ne **pas brancher** l'AIB sur les écritures d'achat : le moteur **liste** ce qu'il faudrait y brancher (écrans, comptes, pièces), la décision comptable est à la Direction.
- Ne pas modifier le calendrier fiscal confirmé sans réponse à Q2.
- Ne pas inventer un taux, une date d'effet ni un texte légal.

## 3. Utilisateurs et rôles

| Rôle | Voit | Fait | Ne voit pas |
|---|---|---|---|
| Comptable | le barème et son historique | crée, corrige (nouvelle version), retire (archive) | rien de plus |
| Direction, DA | le barème et l'historique | lit | commandes d'écriture (absentes) |
| Réception, caissier, stock, soignants | rien du barème | rien | l'écran entier (RG-13) |
| RH / DAF (valeurs d'attente) | fiches de personnel | modifie les valeurs d'attente | paie hors de leur rôle |

## 4. Parcours

1. Le comptable ouvre « Barème AIB », ajoute une version (taux, date d'effet, source, arrêté oui/non).
2. Le moteur rend le taux en vigueur à une date ; la fenêtre acheteur MECeF et les états s'y réfèrent (décision Q3).
3. L'agent de suivi vérifie le calendrier et produit le rapport d'écarts.
4. Le RH modifie un salaire d'attente : le marquage « provisoire » tombe, ligne de journal.

## 5. Exigences fonctionnelles

- **EF-AIB-01** : collection `baremeAib`, une fiche par version ET par **situation de l'acheteur** (`situation` : `ifu_actif`, `ifu_inactif_ou_absent`, `prestation_service`) : `taux` (entier ou décimal défini), `dateEffet`, `arrete` (booléen), `source`, `motif`, `cree*`/`modifie*` ; jamais d'écrasement : une correction crée une version et ferme la précédente à `dateEffet - 1`. Source : vagues 13 et 19.
- **EF-AIB-02** : moteur `PR.tauxAibALaDate(date)` : rend `{taux, arrete, dateEffet, version}` ; refus nommé `AIB_SANS_BAREME` si aucune version ne couvre la date (un tiret n'est pas un zéro). Critère : sondé sur trois dates et sur une date antérieure à la première version.
- **EF-AIB-03** : valeurs de départ **proposées d'après la recherche du 09/11/2026**, toutes marquées « proposition à valider » : `ifu_inactif_ou_absent` 5 % à compter du 07/09/2026 (communiqué DGI rapporté par la presse) ; `ifu_actif` 1 % (régime de la facture certifiée de référence et source de 2022) ; `prestation_service` 3 % (source de 2022, retenue par le payeur). Aucune n'est présentée comme reprise d'un texte officiel tant que le texte n'est pas produit.
- **EF-AIB-04** : écran `m12-bareme-aib` (domaine Financier, rangée de la fiscalité), CRUD complet par `K.crud`, droits écriture comptable et lecture Direction par fiche RBAC, corbeille (RG-14), journal (RG-12).
- **EF-AIB-05** : le moteur expose la liste de ce qu'il faudrait y brancher (achats, retenues, fenêtre acheteur MECeF) sans le brancher ; elle s'affiche à l'écran en lecture.
- **EF-CAL-01** : rapport de vérification du calendrier : pour chaque obligation, jour de dépôt et jour affiché par `cfg-comptabilite` et `m12-echeances` ; le calendrier se sème à l'ouverture des deux écrans (piège de l'amorçage, vague 31) ; le suivi s'ouvre peuplé. Une vue mensuelle est ajoutée **seulement si elle n'existe pas**.
- **EF-ATT-01** : valeurs d'attente du personnel : marquage `valeurAttente` par champ (salaire, date d'embauche, CNSS, tarif de vacation) ; modifier retire le marquage de **ce champ** seulement et journalise avant/après.
- **EF-ATT-02** : un agent sans salaire validé ne se calcule pas en paie (« Non calculable », jamais zéro), comme E1950.

## 6. Données

- Nouvelle collection `baremeAib` (+ éventuellement `historiqueBaremeAib`) : incrément de `VERSION`, `LIBELLES`, schéma relationnel régénéré (vague 70).
- Champs ajoutés sur `personnel` : marquages d'attente par champ, optionnels.
- Distinction : barème = règle configurée par l'administrateur ; calendrier = référentiel dérivé d'un document ; valeurs d'attente = valeurs non validées.

## 7. Hors ligne et synchronisation

`baremeAib` : famille **R (configuration)**, voyage mère vers fileuls par le journal, jamais aux mobiles (RG-13) ; un fileul le lit, ne l'écrit pas ; la version la plus récente par date d'effet fait foi, jamais d'écrasement. Valeurs d'attente : fiche descriptive, dernier écrivain gagne par champ, la validation d'un champ n'est jamais perdue par une modification concurrente d'un autre champ.

## 8. Impression et états

États qui citent l'AIB (facture normalisée, état fiscal) : taux et version en vigueur à la date de la pièce, mention « non arrêté » si applicable. Aucun nouveau gabarit.

## 9. Ce qui n'est pas documenté

Taux 5 %, 1 %, 3 %, date du 07/09/2026 : aucun texte réglementaire dans le dépôt ; marquage « proposition à valider ». Jour de dépôt de la CNSS : le dépôt dit 10 (confirmé 25/08), le texte remis dit 15. Marquage d'attente du personnel : n'existe pas dans le dépôt.

## 10. Questions ouvertes pour la Direction (après recherche)

| N° | Question | Réponse recommandée, d'après la recherche |
|---|---|---|
| Q1 | Peut-on produire le **texte réglementaire** (communiqué DGI du 3 ou 4 septembre 2026, articles 132 d) et 135 du CGI, loi 2026-10) ? | Oui, à demander à l'expert-comptable ou au centre des impôts de Natitingou ; en attendant tout reste « proposition à valider ». |
| Q2 | **CNSS au 10 ou au 15** ? | **Garder le 10** : la DGI fixe la déclaration unique (ITS et cotisations) au 10 du mois suivant, et c'est le calendrier confirmé le 25/08. Le « quinze jours » de la CNSS vise le versement des cotisations : à faire confirmer par la CNSS pour un employeur de plus de 20 salariés. |
| Q3 | Le **taux d'AIB par défaut** de la fenêtre MECeF devient-il 5 % ? | **Non, pas un défaut unique** : 5 % quand l'acheteur n'a pas d'IFU actif, **1 % quand il a un IFU actif** (défaut de la fenêtre), 3 % pour une prestation de service retenue par le payeur. La fenêtre lit le moteur daté selon la situation de l'acheteur. À confirmer avec le texte (Q1). |
| Q4 | Créer le marquage « valeur d'attente » du personnel ? | **Oui**, par champ, sans valeur inventée. |
| Q5 | Brancher l'AIB sur les **écritures d'achat** ? | **Différer** : l'AIB est imputable sur l'impôt sur les bénéfices (compte d'acompte à définir par le comptable) ; le moteur liste d'abord ce qu'il faudrait brancher, sans l'écrire. |
| Q6 | La CNSS se compose de **deux obligations** (déclaration unique le 10, versement des cotisations le 15). Ajoute-t-on une obligation « CNSS, versement des cotisations » au 15, marquée non arrêtée, à côté de la déclaration unique au 10 (modifiable dans les paramètres) ? | **Oui**, une obligation distincte : le 10 reste inchangé (décision du 09/11), et le 15 s'ajoute sans la remplacer, avec son marquage « à confirmer par la CNSS ». À décider. |
| Q7 | **Qui supporte** le prélèvement de 5 % : l'acheteur ou la clinique ? | À trancher avec le texte du communiqué ; en attendant, l'AIB reste affiché comme un acompte sur l'impôt sur les bénéfices imputable, sans écriture. |

## Lots et agents (détail dans `docs/plans/PLAN-M12-bareme-aib-calendrier-attente.md`)

| Lot | Contenu | Agent |
|---|---|---|
| A1 | Moteur et collection `baremeAib`, sonde, mutations | agent maquette-AIB |
| A2 | Écran, droits, journal, corbeille, liste « à brancher » | agent maquette-AIB (suite) |
| A3 | Rapport de vérification du calendrier fiscal | agent audit-calendrier |
| A4 | Valeurs d'attente du personnel | agent maquette-RH |
| A5 | Vecteurs, domaine, poste | agent portage |
| S | Suivi de l'avancement de tous les lots | agent de suivi |
