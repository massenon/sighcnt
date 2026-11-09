# Audit du calendrier fiscal et social (lot A3)

Date : 09/11/2026. Lecture seule : aucun fichier de code ni de donnée n'a été modifié. Plan : `docs/plans/PLAN-M12-bareme-aib-calendrier-attente.md` (lot A3). PRD : `docs/prd/PRD-M12-bareme-AIB-calendrier-fiscal-et-valeurs-d-attente-du-personnel.md` (EF-CAL-01).

Décisions de la Direction du 09/11/2026 prises comme cadre : la CNSS reste au 10 (déclaration unique, calendrier confirmé le 25/08/2026) et le jour de dépôt de chaque obligation doit être modifiable dans les paramètres pour l'avenir.

## Méthode et limites

- Mesures faites au navigateur (Chrome piloté par Puppeteer) sur un banc isolé : serveur PHP sur le port 8911, base `sigh_banc_l10` (jetable, créée par le banc), relais statique sur 8912. Aucune autre base touchée. Les scripts de sonde sont dans le scratchpad de la session (`cal3/audit.js`, `cal3/audit2.js`), pas dans le dépôt.
- **L'horloge du banc est décalée au 16/08/2026** (`HORLOGE_BANC`), pas au 09/11/2026 : « aujourd'hui », les échéances réputées payées et les « prochaines échéances » se lisent à cette date.
- Session `admin` du banc uniquement : l'ouverture des deux écrans n'a pas été éprouvée sous les autres rôles (droits RBAC de `cfg-comptabilite` et `m12-echeances` non sondés ici).
- L'arbre de travail portait des modifications d'un autre agent (`data.js`, `nav.js`, `store.js` modifiés, non commités) pendant l'audit. Les numéros de ligne ci-dessous sont ceux de l'arbre de travail au moment de la lecture et peuvent glisser. Je n'ai pas isolé HEAD.
- Geste UI réellement exécuté : modification de la CNSS (jour) par la modale de `cfg-comptabilite`. Non exécutés au geste : modification du **mois** et de la **part** (lus dans le code seulement : `champsObligation` les propose, `controleValeursObligation` les valide), création et retrait d'une obligation, modification ORTB.
- Non vérifié : comportement sous une vraie horloge au 09/11/2026, rôles autres qu'admin, poste fileul (`posteFileul`), tâche `api/cron.php` exécutée (lue seulement), impression, synchronisation.

## Résultats par point demandé

### (1) Les deux écrans existent au manifeste et s'ouvrent

- `cfg-comptabilite` : `assets/js/nav.js:673` (« Paramètres comptables & obligations »). Ouvert sur le banc : contenu peint, 0 erreur JS relevée (`pageerror`) sur toute la session de sonde.
- `m12-echeances` : `assets/js/nav.js:483` (« Échéances fiscales & paiements »). Ouvert sur le banc : contenu peint, 0 erreur JS.
- Écran supplémentaire qui montre aussi le calendrier : `cfg-fiscalite` (« Paramètres fiscaux (IFU / RCCM) », `nav.js:672`, table « Calendrier fiscal et social », `configuration.js:1740` et suivantes). Trois écrans lisent donc le calendrier, pas deux. Il calcule SA propre « prochaine échéance » (`prochaineEcheance`, `configuration.js:1820`), séparément du moteur du suivi.

### (2) Semis à l'ouverture (piège de l'amorçage, vague 31)

Mesuré après remise à neuf de la base du banc, une base neuve par cas, session ouverte :

| Première page ouverte | `echeancesFiscales` | `obligationsFiscales` |
|---|---|---|
| `dash-direction` (ni référence ni suivi) | 63 | 20 |
| `m12-echeances` en premier | 63 (dont 44 réputées payées) | 20 |
| `cfg-comptabilite` en premier | 63 (dont 44 payées) | 20 |

Verdict : le calendrier se sème au socle, indépendamment de l'écran ouvert. Un suivi ouvert sans être passé par la référence ne lit pas zéro. Conforme à `store.js` (semis `echeancesFiscales: genEcheances(2026, ...)`, ligne 1927).

Point de méthode (piège du banc, pas du produit) : une première série de mesures a donné 0 échéance partout parce que le jeton de session du banc avait été invalidé par la remise à neuf (`load()` ne sème pas sans session : « pas de session, pas de semence »). Toute sonde doit se connecter APRÈS la remise à neuf.

### (4) Le suivi s'ouvre peuplé

- **63 échéances mesurées**, égal au chiffre de CLAUDE.md. Détail : 4 mensuelles x 12 = 48, plus 15 annuelles (IS 5, PATENTE 3, CCIB 3, ORTB 2, TVM 1, ETATS-FIN 1). 19 codes, 10 familles.
- Une seule année d'exercice : `[2026]`. Au 16/08/2026 : 44 payées, 1 en retard (CNSS du 10/08/2026, 7 jours de retard, l'alarme voulue du jeu), 4 déclarations attendues, 0 à payer sous 10 jours.
- Le tableau n'affiche que 20 lignes par page (pagination), le compte exact vient du magasin et du bandeau « 63 échéances au total ».

### (3) Jour de dépôt, obligation par obligation

Colonnes : **attendu** = semence `D.CALENDRIER_FISCAL` (`data.js:1541`, confirmé 25/08/2026) ; **référence** = ce que dit `cfg-comptabilite` (libellé `le N du mois suivant` ou `le N mois`, produit par `libelleEcheanceObligation`, `configuration.js:3374`, à partir du jour en magasin ; le jour en magasin a été lu et égale la semence pour les 19 codes) ; **cfg-fiscalite** = prochaine échéance affichée (DOM) ; **suivi** = `echeanceTheorique` des échéances de `m12-echeances` (jour calendaire avant report de week-end). Les jours de la colonne référence sont lus dans le magasin et dans le code de rendu ; le texte DOM de `cfg-comptabilite` n'a été relevé en entier que pour ITS, AIB, VPS, CNSS, IS-SOLDE, ETATS-FIN (les autres lignes passent par la même fonction).

| Code | Jour attendu | Jour référence | cfg-fiscalite (prochaine) | Jour suivi | Écart suivi contre référence |
|---|---|---|---|---|---|
| ITS | 10, mensuelle | 10 | 10/09/2026 | 10 (12 mois) | 0 |
| AIB | 10, mensuelle | 10 | 10/09/2026 | 10 (12 mois) | 0 |
| VPS | 10, mensuelle | 10 | 10/09/2026 | 10 (12 mois) | 0 |
| **CNSS** | **10, mensuelle** | **10** | 10/09/2026 | **10 (12 mois)** | **0 : conforme au 10 confirmé** |
| IS-1 | 10 mars | 10 mars | 10/03/2027 | 10/03 | 0 |
| IS-2 | 10 juin | 10 juin | 10/06/2027 | 10/06 | 0 |
| IS-3 | 10 septembre | 10 septembre | 10/09/2026 | 10/09 | 0 |
| IS-4 | 10 décembre | 10 décembre | 10/12/2026 | 10/12 | 0 |
| IS-SOLDE | 30 avril | 30 avril | 30/04/2027 | **28/04** | **moins 2 jours** |
| ETATS-FIN | 30 avril | 30 avril | 30/04/2027 | **28/04** | **moins 2 jours** |
| PATENTE-DECL | 31 janvier | 31 janvier | 01/02/2027 (31/01 reporté, dimanche) | **28/01** | **moins 3 jours** |
| PATENTE-1 | 10 février | 10 février | 10/02/2027 | 10/02 | 0 |
| PATENTE-2 | 30 avril | 30 avril | 30/04/2027 | **28/04** | **moins 2 jours** |
| CCIB-DECL | 28 février | 28 février | 01/03/2027 (28/02 reporté, dimanche) | 28/02 (reporté au 02/03/2026) | 0 |
| CCIB-1 | 10 mars | 10 mars | 10/03/2027 | 10/03 | 0 |
| CCIB-2 | 10 juin | 10 juin | 10/06/2027 | 10/06 | 0 |
| TVM | 30 avril | 30 avril | 30/04/2027 | **28/04** | **moins 2 jours** |
| ORTB-RADIO | 30 mars | 30 mars | 30/03/2027 | **28/03** (reporté au 30/03/2026) | **moins 2 jours** |
| ORTB-TELE | 30 juin | 30 juin | 30/06/2027 | **28/06** (reporté au 29/06/2026) | **moins 2 jours** |

Verdict : **7 obligations annuelles sur 19 divergent entre la référence et le suivi** (toutes celles dont le jour est 29, 30 ou 31). Les 12 autres concordent. La CNSS est au 10 partout.

Cause mesurée et lue : `store.js:882` plafonne tout jour d'une obligation annuelle à 28 (`Math.min(o.jour, 28)`), alors que `cfg-fiscalite` et `cfg-comptabilite` n'appliquent aucun plafond. Conséquence : le suivi, la cloche (`notifications.js` source `echeance_fiscale`), le tableau de bord et `api/cron.php` jugent « en retard » une échéance du 30 avril le 29 avril, et la référence dit « 30 avril » à côté.

### (5) Modifiabilité en paramètres, au geste

Ce qui existe et fonctionne (exécuté) :

- Moteur : `SIGH.configurationFiscale.modifierObligation` (`parcours.js:3989`), `creerObligation`, `retirerObligation`, versionnés par date d'effet, historique dans `historiqueObligations`, motif obligatoire, régénération par `S.regenererEcheances` (`store.js`, fonction `regenererEcheances`).
- Écran : `cfg-comptabilite`, bouton crayon « Modifier (version datée) » par ligne (`configuration.js:3544`), formulaire (code non modifiable, intitulé, périodicité, jour 1 à 31, mois, part 1 à 100, déclaration, note), puis modale « Portée de la modification » (date d'effet, motif, note d'impact).

Essais sur la base du banc (puis base jetable, aucune restauration nécessaire en production) :

1. **Refus sans motif** : `MOTIF_REQUIS` (« Le motif de la modification est obligatoire. », avec geste). **Jour 32** : `JOUR_INVALIDE`. Mesurés.
2. **CNSS au 15, date d'effet future (01/12/2026), par la modale** : 12 échéances actives avant, 12 après ; 7 payées conservées (janvier à juillet, jour 10) ; 1 archivée (celle du 10/12) recréée au 15/12 ; août à novembre inchangées au 10. L'obligation en magasin passe à `jour 15, dateEffet 2026-12-01, valideLe null` (donc à revalider) ; l'ancienne version va en historique avec `dateFin 2026-11-30`, motif conservé. Le journal porte « Modification d'obligation fiscale » et « Régénération des échéances ». Mesuré.
3. **CNSS au 12, date d'effet passée (01/05/2026), sur base neuve, par la modale** : annonce « 3 échéance(s) payée(s) conservée(s), 5 non payée(s) régénérée(s), 5 recréée(s) depuis la version en vigueur au 01/05/2026 ». Les payées de mai, juin et juillet gardent leur jour 10 ; janvier à avril (4) restent antérieures ; août à décembre passent au 12. Mesuré.
4. **Rétablissement** (CNSS remise au 10, même date d'effet 01/05/2026) : accepté, août à décembre repassent au 10, 7 payées conservées, 10 échéances archivées au total. Mesuré.

Écarts relevés pendant ces essais :

- **E-A3-02, version à venir invisible.** Après l'essai 2, `cfg-comptabilite` continue d'afficher « le 10 du mois suivant, d'origine » pour la CNSS tant que le 01/12/2026 n'est pas atteint (la table lit `D.obligationsALaDate(AUJ)`), et la carte « Versions antérieures » ne liste que les versions remplacées. Rien à l'écran ne dit qu'un jour 15 est programmé. À mesurer : ce que voit la Direction qui a programmé la modification. Mesuré sur le texte de la ligne CNSS après le geste.
- **E-A3-03, date d'effet bloquée par la version à venir.** Avec une version programmée le 01/12/2026, un second changement daté avant cette date est refusé (`DATE_EFFET_ANTERIEURE`, car `minimum` = date d'effet de la fiche courante). Il n'y a pas de moyen d'annuler une version à venir ni d'en intercaler une. Mesuré (le geste « CNSS au 12 depuis le 01/05/2026 » est resté sans effet, 12 actives, jours inchangés). Le message de refus n'a pas été relevé (sélecteur de toast sans résultat).
- **E-A3-04, intervalle d'historique inversé.** Rétablir à la MÊME date d'effet écrit une ligne d'historique `jour 12, dateEffet 2026-05-01, dateFin 2026-04-30` (fin avant début). Cosmétique, mais ça se lit comme une erreur. Mesuré sur `historiqueObligations`.
- **E-A3-05, le jour 29 à 31 d'une obligation MENSUELLE déborde.** Essai moteur : ITS au jour 31 depuis 01/09/2026. Résultat : septembre donne le 01/10 (déborde), octobre le 31/10 (reporté au 02/11), novembre le 01/12, décembre le 31/12. Donc deux échéances ITS tombent le même mois d'octobre et aucune ne tombe en novembre. `new Date(annee, m, o.jour)` (`store.js`, genEcheances, branche mensuelle) n'a ni plafond au dernier jour du mois ni règle. Le formulaire accepte 31. Mesuré.
- **E-A3-06, jour 31 annuel donne le 28.** Essai moteur : TVM au jour 31 depuis 01/01/2026 produit 2026-04-28. Même cause que l'écart du tableau.
- **E-A3-07, période libellée à tort.** `store.js:904` : `C.MOIS[Math.max(0, d.getMonth() - 1)]`. L'échéance du 10 janvier porte « janvier 2026 » (devrait être décembre 2025) et celle du 10 février aussi « janvier 2026 ». Mesuré : les deux premières lignes ITS du suivi affichent « janvier 2026 ».
- **E-A3-08, textes qui dupliquent le jour.** La `note` de chaque obligation reste « Le 10 du mois suivant. » après un changement de jour (seul le champ jour change), et `configuration.js` écrit en dur « dépôt au 30 avril » (1730), « les 10 mars, 10 juin, 10 septembre et 10 décembre » (1903 à 1913), « Le 30 avril de l'année suivante » (3655). Après modification d'un jour, ces textes mentent. Lu dans le code ; non rendu à l'écran après modification (seul le texte de la ligne CNSS a été relevé : « le 10 du mois suivant » reste vrai tant que la version à venir n'est pas en force).
- **E-A3-09, une seule année d'exercice.** `echeancesFiscales` ne contient que l'exercice 2026 (semis figé sur 2026 à `store.js:1927` ; `m12-comptabilite.js:3296` ne génère que si la collection est vide). Aucune échéance 2027 n'existe, sauf si une modification a une date d'effet en 2027 (le moteur génère alors cette année). Mesuré (`exercices: [2026]`). Au 09/11/2026 le suivi ne montre rien après décembre 2026.

### (5 bis) Valeurs encore codées en dur qui devraient être en paramètres

Chemins relatifs à `prototype_html/`. Lignes de l'arbre de travail au 09/11/2026.

| Valeur | Où | Remarque |
|---|---|---|
| Plafond du jour annuel à 28 | `assets/js/store.js:882` | Défaut à corriger (écart principal). |
| Débordement mensuel non géré (jour 29 à 31) | `assets/js/store.js:881` | Voir E-A3-05. |
| Libellé de période (mois précédent) | `assets/js/store.js:904` | Voir E-A3-07. |
| Seuil « réputée payée » : plus de 25 jours après l'échéance | `assets/js/store.js:910` | Règle de semis du jeu de démonstration seulement. Aucune incidence en exploitation réelle (vidage et `sansReglement`), à ne pas rendre paramétrable. |
| Date de référence du semis : 16/08/2026 | `assets/js/store.js:875` (défaut `aujourdhui`), `:1927` (exercice 2026) | Jeu daté, assumé par la doctrine ; l'exercice 2026 fixe est le point E-A3-09. |
| Seuils d'état : à payer sous 10 jours, déclaration attendue sous 30 jours | `assets/js/modules/m12-comptabilite.js:3305`, `:3306` | À mettre en paramètres (« délai d'alerte avant échéance »). |
| Même seuil de 10 et 30 jours pour l'affichage de `cfg-fiscalite` | `assets/js/modules/configuration.js:1842` (30), `:1893` (10 et 30) | Dupliquent les précédents : une seule source à créer. |
| Alerte serveur : à moins de 7 jours | `api/cron.php:121` (`$ecart > 7`), libellé `:108` | Troisième valeur différente (7) pour la même notion de « proche ». |
| Montant de la CCIB (300 000 F, deux tranches) | `assets/js/data.js:1632` (`MONTANTS_FISCAUX`) | Hors versionnement par date. L'écran dit « montant à confirmer par le cabinet ». |
| Taux CNSS (16,4 % et 3,6 %), VPS 4 %, barème ITS | `D.PARAM_PAIE` (`data.js`) | L'écran `cfg-comptabilite` le dit lui-même : « ces taux ne se modifient pas ici ». Le barème ITS est validable mais pas daté. |
| Textes d'interface contenant des jours | `assets/js/modules/configuration.js:1730`, `:1903` à `:1913`, `:3655` | Voir E-A3-08. |
| Cartes KPI « Mensuelles : ITS, AIB, VPS, CNSS » | `configuration.js` (`hint` de la carte, cfg-fiscalite) | Libellé en dur des codes, ne suit pas une obligation créée. |

Ce qui est bien en paramètres et ne l'était pas dans mon relevé : `jour`, `mois`, `part`, `periodicite`, `declaration`, `note` de chaque obligation (formulaire et moteur, versionnés), paramètres ORTB (seuil, montants, mois : `modifierOrtb`). `notifications.js` ne porte aucun jour ni seuil de calendrier (il lit « non payé et échéance avant aujourd'hui »). Recherche de `jour:` dans `parcours.js`, `notifications.js`, `api/cron.php` : aucune obligation en dur ; `data.js` ne porte que la semence.

### (6) Vue calendrier mensuelle

**Non : aucune vue calendrier mensuelle des échéances n'existe.** Recherche faite dans `nav.js`, `m12-comptabilite.js`, `configuration.js`, `dashboards.js`, `m13-administration.js` (aucune grille de mois ni libellé « calendrier » d'écran fiscal). Les trois présentations existantes sont des tableaux : `m12-echeances` (liste filtrable, 20 par page), `cfg-fiscalite` (liste triée par délai) et `cfg-comptabilite` (tableaux par famille). `m2-agenda` est l'agenda des rendez-vous, il ne lit pas `echeancesFiscales` (aucune référence trouvée dans `modules/m2-*.js`).

## Synthèse des écarts et correction recommandée (NON appliquée)

| Réf. | Écart | Gravité | Correction recommandée |
|---|---|---|---|
| E-A3-01 | 7 obligations annuelles au 28 dans le suivi au lieu du 29, 30 ou 31 de la référence (IS-SOLDE, ETATS-FIN, PATENTE-DECL, PATENTE-2, TVM, ORTB-RADIO, ORTB-TELE) : retards annoncés 2 à 3 jours trop tôt, cloche et cron concernés | Haute (fausse alerte, rien d'autre ne change) | Remplacer `Math.min(o.jour, 28)` par « le plus petit de `jour` et du dernier jour du mois » (règle unique, partagée avec la branche mensuelle), et l'utiliser aussi dans `cfg-fiscalite` (`prochaineEcheance`) pour qu'il n'y ait qu'un calcul. Vecteur de test : les 19 codes, jour du suivi = jour de la référence, y compris février. Régénérer les échéances non payées de 2026 ou s'appuyer sur le vidage (sans toucher aux payées : une quittance ne se réécrit pas). Incrémenter `VERSION` si le semis change. |
| E-A3-05 / 06 | Jour 29 à 31 mal géré en mensuel (débordement) et en annuel (28) | Moyenne (se déclenche dès qu'une Direction saisit 31) | Même fonction « jour effectif du mois » que ci-dessus ; refuser ou normaliser dans `controleValeursObligation` ; message du formulaire : « au dernier jour du mois si le mois est plus court ». |
| E-A3-02 | Une version programmée n'est visible nulle part | Moyenne (sécurité de la modification future) | Afficher sur la ligne « à partir du 01/12/2026 : le 15 » (lecture de la version dont `dateEffet` est dans le futur), et la lister dans le bloc d'historique. |
| E-A3-03 | Version à venir non annulable et non intercalable | Moyenne | Soit autoriser l'annulation d'une version à venir (archivage RG-14 avec motif), soit expliquer le refus (« une version prend effet le … ; l'annuler d'abord »). Décision de la Direction. |
| E-A3-04 | `dateFin` avant `dateEffet` à même date | Basse | Refuser la même date d'effet (message nommé) ou fermer la version sur sa propre date. |
| E-A3-07 | Période « janvier 2026 » pour janvier et février | Basse | Calculer le mois de période sur `d.getMonth() - 1` avec report sur l'exercice précédent (« décembre 2025 »). |
| E-A3-08 | Textes et notes qui répètent le jour | Moyenne (lisible comme faux après changement) | Dériver les phrases du jour en magasin (comme `tableObligationsDeclaratives` le fait déjà pour les obligations mensuelles) ; ne pas répéter le jour dans `note` ; réserver `note` au commentaire libre. |
| E-A3-09 | Une seule année d'exercice dans le suivi | Moyenne (au 09/11/2026 rien après décembre) | Générer l'exercice suivant à l'ouverture (ou à une date) à partir des obligations en vigueur, comme `S.genEcheances(annee, ...)`, sans quittance inventée. Brancher sur le sélecteur d'exercice de M12. |
| Seuils | 10 et 30 jours (suivi, `cfg-fiscalite`), 7 jours (cron), 25 jours (semis) | Moyenne | Créer UN paramètre daté « délais d'alerte du calendrier » (délai de pré-alerte, délai de déclaration) lu par `calculerEtat`, `cfg-fiscalite` et `api/cron.php` ; laisser les 25 jours au semis seulement. Respecter la doctrine « le moteur d'alerte ne décide pas du seuil » (vague 64). |
| Vue mensuelle | Absente | À décider | PRD EF-CAL-01 : à créer SEULEMENT si elle n'existe pas. Elle n'existe pas. Vue du mois sur la collection existante (pas de seconde collection), échéances par jour, état coloré, lien vers le suivi ; droits de `m12-echeances`. |
| CNSS | Aucun écart : 10 partout | Sans objet | Le 15 du texte remis reste **signalé, non tranché** ; le geste « modifier le jour de la CNSS, date d'effet future » existe et a été essayé (essai 2), il permettra le passage au 15 si la CNSS le confirme. |

## Ce qui n'a pas pu être vérifié

- Comportement sous l'horloge réelle du 09/11/2026 (le banc date au 16/08/2026).
- Droits RBAC des deux écrans sous les rôles autres qu'admin (comptable, direction, da, caissier) : non sondés.
- Modification du mois ou de la part d'une obligation, création, retrait, paramètres ORTB : non exécutés au geste.
- `api/cron.php` : lu, non exécuté ; sa lecture des échéances suppose `echeance` en `AAAA-MM-JJ`.
- Poste fileul (`posteFileul`) : les commandes d'édition y sont remplacées par « tenue par la mère », non éprouvé.
- Impression de la quittance et validation d'un règlement : hors périmètre de A3.
- Rendu de `cfg-comptabilite` pour les 19 lignes : les jours viennent du magasin et de `libelleEcheanceObligation` (lus), le texte DOM n'est relevé en entier que pour six codes.
