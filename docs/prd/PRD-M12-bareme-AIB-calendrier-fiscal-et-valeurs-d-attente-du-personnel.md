# PRD : Barème AIB daté, vérification du calendrier fiscal et valeurs d'attente de la fiche de poste

Statut : **brouillon du 09/11/2026**, à arrêter par la Direction (questions de la section 10).
Sources : message de la Direction du 09/11/2026 (texte remis, décrivant trois chantiers) ; CLAUDE.md (vague 13 « un moteur daté, une correction ajoute une version », vague 19 grille des primes datée, vague 33 « diagnostic, pas gommage », calendrier fiscal confirmé le 25/08/2026, vague 49 tarifs d'attente) ; `docs/prd/PRD-MECEF-facturation-normalisee-deux-modes.md` (Q4 : taux d'AIB par défaut).

**Ce que ce PRD constate avant d'écrire (inventaire du dépôt, mesuré le 09/11/2026)** :
- Il n'existe **aucun barème AIB versionné** dans la maquette : `data.js` ne porte qu'un paramètre fixe `aib: { taux: 1, code: 'AIB2' }` et une échéance mensuelle. Le texte remis parle d'un formulaire « porté depuis l'écran de la maquette » : cet écran n'existe pas ici, il est donc à **créer**, maquette d'abord.
- Les valeurs de départ du texte remis (5 % arrêté, généralisé à compter du 07/09/2026 ; 1 % et 3 % non arrêtés) ne figurent dans **aucun document du dépôt**. Elles sont reprises comme **proposition à valider**, avec pour source le message de la Direction, jusqu'à la production du texte réglementaire.
- Le calendrier fiscal du dépôt (`D.CALENDRIER_FISCAL`) place la **CNSS au 10** et ce calendrier a été **confirmé par la Direction le 25/08/2026**. Le texte remis dit « la CNSS est bien au 15 » : les deux se contredisent (question Q2).
- Aucune notion de **salaire d'attente** n'existe sur les fiches de M10 : pas de marquage « provisoire » sur le salaire, la date d'embauche, la CNSS ou le tarif de vacation. À créer ou à constater (question Q4).

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

- **EF-AIB-01** : collection `baremeAib`, une fiche par version : `taux` (entier ou décimal défini), `dateEffet`, `arrete` (booléen), `source`, `motif`, `cree*`/`modifie*` ; jamais d'écrasement : une correction crée une version et ferme la précédente à `dateEffet - 1`. Source : vagues 13 et 19.
- **EF-AIB-02** : moteur `PR.tauxAibALaDate(date)` : rend `{taux, arrete, dateEffet, version}` ; refus nommé `AIB_SANS_BAREME` si aucune version ne couvre la date (un tiret n'est pas un zéro). Critère : sondé sur trois dates et sur une date antérieure à la première version.
- **EF-AIB-03** : valeurs de départ **proposées** : 5 % arrêté, généralisé à compter du 07/09/2026 ; 1 % et 3 % non arrêtés. Marquées « proposition à valider » (source : message du 09/11/2026), jamais présentées comme reprises d'un document.
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

## 10. Questions ouvertes pour la Direction

| N° | Question | Option recommandée |
|---|---|---|
| Q1 | Peut-on produire le **texte réglementaire** du 5 % généralisé au 07/09/2026 (et des 1 % et 3 %) ? | Oui : tant qu'il manque, tout reste « non arrêté » sauf mention contraire de la Direction. |
| Q2 | **CNSS au 10 ou au 15** ? Le calendrier confirmé le 25/08/2026 dit 10. | Garder le 10 tant qu'une réponse écrite ne change pas la confirmation du 25/08. |
| Q3 | Le **taux d'AIB par défaut** de la fenêtre acheteur MECeF (PRD MECeF, Q4 recommandé 1 %) devient-il 5 % à compter du 07/09/2026 ? | Oui si Q1 est confirmé : la fenêtre lit le moteur daté au lieu d'un défaut figé. |
| Q4 | Faut-il **créer** le marquage « valeur d'attente » sur les fiches de personnel (il n'existe pas) ? | Oui, par champ, sans valeur inventée. |
| Q5 | L'AIB doit-il être branché sur les **écritures d'achat** dans un second temps ? | Décision différée : le moteur liste d'abord ce qu'il faudrait brancher. |

## Lots et agents (détail dans `docs/plans/PLAN-M12-bareme-aib-calendrier-attente.md`)

| Lot | Contenu | Agent |
|---|---|---|
| A1 | Moteur et collection `baremeAib`, sonde, mutations | agent maquette-AIB |
| A2 | Écran, droits, journal, corbeille, liste « à brancher » | agent maquette-AIB (suite) |
| A3 | Rapport de vérification du calendrier fiscal | agent audit-calendrier |
| A4 | Valeurs d'attente du personnel | agent maquette-RH |
| A5 | Vecteurs, domaine, poste | agent portage |
| S | Suivi de l'avancement de tous les lots | agent de suivi |
