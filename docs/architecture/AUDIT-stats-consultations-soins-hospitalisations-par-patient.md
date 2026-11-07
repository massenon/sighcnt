# Audit : statistiques des consultations, soins et hospitalisations par patient

Date : 07/11/2026. Lecture seule. Aucun banc lancé : les volumes du jeu sont « non vérifiés ».
Les chemins `prototype_html/assets/js` sont abrégés en `js/`, `modules/dashboards.js` en `dash.js`.

## 1. Périmètre examiné

- Catalogue : `docs/annexes/CATALOGUE-stats-consultations-soins-hospitalisations-par-patient.txt` (6 familles, filtres croisés, exports).
- Écrans PIL (`js/nav.js:806-830`) : `m2-stats-consultations` (`dash.js:3949`), `m3-stats-hospitalisations` (`dash.js:4379`), `m3-stats-bloc` (`dash.js:4029`), `m5-stats-examens` (`dash.js:3806`), `m4-stats-maternite` (`dash.js:1872`), `dash-croise` (`dash.js:2777`, sources `dash.js:2492`), `dash-da`, `m2-pathologies` (`modules/m2-consultations.js:2452`), fiche patient `modules/m1-patients.js:269-301`.
- Poste : `apps/poste/lib/modules/pil/pil_clinique.dart` (consultations :164, hospitalisations :276), `registre_pil.dart:20-22`, `modules/m2/cs_pathologies.dart`.
- Données source : `js/store.js:768-790` (consultations), `js/data-seed.js:702-870` (dossiers et fiches), `:490-520` (admissions du RAP), `modules/m3-hospitalisation.js:820-900`.

## 2. Tableau indicateur par indicateur

| Fonction demandée | Existe (maquette) | Existe (poste) | Manque / donnée | Preuve |
|---|---|---|---|---|
| 1.1 Top pathologies (consultation) | Oui, sur `consultations.pathologies`, sans filtre ni période | Partiel (`cs_pathologies.dart`, non relu en détail) | Aucun filtre (période, sexe, âge, service) | `m2-consultations.js:2474-2481`, `:2541` |
| 1.1 Top pathologies (hospitalisation) | Non : `diagnosticEntree` en texte libre, sans code | Idem | Pas de code pathologie sur l'admission | `dash.js:4452`, `m3-hospitalisation.js:826` |
| 1.2 Répartition CIM-10/CIM-11 | Non calculable : référentiel propre en chapitres inspirés de la CIM-10, sans codification | Idem | Choix de la Direction (voir Q1) | CLAUDE.md vague 29, `D.PATHOLOGIES` |
| 1.3 Comorbidité | Non : `pathologies` est un tableau mais aucun écran ne compte les consultations à 2 pathologies ou plus | Non | Calcul faisable depuis `consultations.pathologies` | grep `comorbid` : 0 résultat |
| 1.4 Maladie par âge, sexe, origine | Non : `dash-croise` source consultations n'a que mois, médecin, service, motif | Non | Jointure `patientCode` vers patients (sexe, `dateNaissance`, `quartier`) | `dash.js:2517-2523` |
| 1.5 Saisonnalité | Non pour les pathologies. Consultations par mois : oui (6 derniers mois) | Oui (équivalent) | Courbe par pathologie, plus de 6 mois | `dash.js:3996-4004` |
| 2.1 Volume (jour/sem./mois/an) | Partiel : total, mois courant, par mois. Pas de pas jour/semaine/année | Idem | `C.PERIODES`/`C.bornes` existent au socle, non branchés | `dash.js:3969-3985` |
| 2.2 RDV honorés / annulés / no-show | Statuts `terminee`, `non_honore`, `reporte` existent, aucune statistique | Non | Écran de taux à créer. Aucun statut « annulé » | `m2-consultations.js:175-180`, `:962-988` |
| 2.3 Délai d'obtention d'un RDV | Non calculable : pas de date de prise de RDV | Non | Saisir `priseLe` à la création du rendez-vous | grep `prisLe\|creeLe` : 0 dans `m2-consultations.js` |
| 2.3 Attente en salle | Non calculable : ticket de file sans heure d'appel ni de début | Non | Horodater appel et début de consultation | `fileAttente` `m2-consultations.js:5360`, grep `heureAppel` : 0 |
| 2.3 Durée de consultation | Non calculable : ni début ni fin | Non | Idem | grep `dureeConsultation` : 0 |
| 2.4 Première vs suivi | Donnée présente sur le dossier (`typeVenue` : première, contrôle, suivi, urgence), non exploitée. L'écran regroupe par `type` (Consultation/Contrôle/Urgence/Domicile) | Idem | Comptage sur `dossiersConsultation.typeVenue` | `m2-consultations.js:2040`, `dash.js:3989` |
| 2.5 Par médecin / service | Médecin : oui. Service : celui de l'organigramme, l'écran le dit | Oui | Pas de filtre praticien | `dash.js:3982` |
| 3.1 Actes par nature | Soins prescrits, actes, analyses, imagerie : oui via `dash-croise`. Pas de vue par patient | Non vérifié | Pas de filtre pathologie | `dash.js:2527-2700` |
| 3.2 Consommation par soin | Non : sortie de stock rattachée à l'ordonnance, jamais au soin | Non | Lier `mouvements.justificatif` aux soins (maintien de RG-03) | `m6-stock`, `dash-croise` source mouvements |
| 3.3 Soins complexes (dialyse, chimio) | Hors périmètre clinique : aucun acte au catalogue | Non | Demander à la Direction (Q4) | grep `dialyse` dans `data-tarifs.js` : non vérifié |
| 3.4 Complications, infections nosocomiales | Non : aucun champ | Non | Événement indésirable à créer (collection) | grep `nosocom` : 0 |
| 4.1 DMS global / par type de chambre | Oui, séjours terminés seulement, durée minimale 1 jour | Oui, même règle | Pas de DMS par service ni par pathologie | `dash.js:4423-4429`, `:4437-4455` |
| 4.1 DMS par diagnostic | Oui, sur texte libre `diagnosticEntree` | Oui | Dépend de la saisie libre | `dash.js:4467-4475` |
| 4.2 Taux d'occupation | Oui, à la date, parc `D.CHAMBRES` | Oui | Pas d'historique (série dans le temps) | `dash.js:4433-4436` |
| 4.3 Réhospitalisation 30 jours | Non | Non | Calculable (même `patientId`, `dateEntree` à moins de 30 j de `dateSortie`). « Même pathologie » non calculable | grep `readmi` : 0 |
| 4.4 Mode d'entrée | Non : seul `priseEnCharge` (moins/plus de 8 h) | Non | Saisir mode d'entrée (urgence, programmée, transfert, issue d'observation) | `m3-hospitalisation.js:881` |
| 4.4 Mode de sortie, mortalité | Non : `deces` (M4) sans lien admission. Sortie contre avis dans `sortiesAvisMedical` séparée. Aucun champ issue sur l'admission | Non | Champ `issueSejour` à la finalisation (domicile, transfert, décès, contre avis) | `m4-maternite.js:500-530`, `m3-hospitalisation.js:1393` |
| 4.5 Rotation des lits | Non | Non | Calculable depuis lit, `dateEntree`, `dateSortie` | grep `rotation` : 0 |
| 5.1 Tiers-payant (assureur, sans assurance) | `dash-croise` factures par assureur, sans croisement pathologie ou service | Non vérifié | Couverture datée (`couvertureALaDate`) non utilisée en statistique | `dash.js:2597-2604`, `parcours.js:1992` |
| 5.1 CMU, aide médicale | Sans objet au Bénin (non documenté) | | Ne rien inventer | |
| 5.2 Coût moyen par patient / pathologie | Non. Facturé par patient possible. Coût de revient non calculable (RH non imputable, `m12-cout-activite`) | Non | Marge sur consommables seulement | CLAUDE.md vague 64 |
| 5.3 Recouvrement | Oui ailleurs (M9, BFR) | Oui ailleurs | Hors module, lien à ajouter | `m9-assurances`, `m12-bfr` |
| 5.4 Délai de paiement assureurs | Non : pas de date de règlement par facture mère | Non | À confirmer (Q5) | non vérifié |
| 6.1 Fréquence de recours par patient | Non en agrégé. Fiche patient liste les 12 collections | Idem | Calcul visites par patient et par an | `m1-patients.js:269-301` |
| 6.2 Fidélité | Non calculable : on ne sait pas si le patient va ailleurs. Seul le retour (2 venues ou plus) se calcule | Non | Définir « fidèle » (Q3) | |
| 6.3 Chroniques / ALD | ALD inexistant au Bénin. Aucune liste de chroniques | Non | Pathologies marquées « chronique » sur `D.PATHOLOGIES` | `store.js:2954` |
| Filtres croisés dynamiques | Seul `dash-croise` croise 2 axes, par source, sans filtre. Les écrans stats n'ont que du/au | Plage seule | Voir défaut D3 | `dash.js:3955-3960`, `pil_clinique.dart:182` |
| Comparaison de période | Absente des écrans stats (existe dans `dash-da`) | Non | À porter | `dash.js:3002-3003` |
| Export CSV | `m2-pathologies`, `m5-stats-examens` : oui. `m2-stats-consultations` : aucun tableau | Non vérifié | CSV des agrégats | `ui.js:1031`, `m2-consultations.js:2579` |
| PDF avec filtres relevés | Hospitalisations : `P.etat` oui. Consultations : non. Filtres relevés sur la page par `print.js` | Hospitalisations : oui. Consultations : non | Bouton « Éditer l'état » | `dash.js:4491`, `print.js:330-345` |
| Vue par patient (historique, parcours) | Fiche patient, 12 collections, onglets | Non vérifié | Pas de chronologie unique ni de compteurs de recours | `m1-patients.js:269` |
| Droits agrégé vs nominatif | Statistiques par rôle au manifeste. Aucune ligne nominative dans les stats | Idem | Séparer explicitement (Q2) | `nav.js:820-829` |

## 3. Défauts réels

1. **Haute.** `m2-stats-consultations` compte tout le registre `consultations`, rendez-vous planifiés et en cours compris : le jeu semé porte `statut` parmi terminee/en_cours/planifiee (`store.js:787`) et l'écran ne filtre pas le statut (`dash.js:3978`). Le volume de consultations est surévalué (rendez-vous non honorés comptés comme consultations).
2. **Haute.** `dash-croise`, source consultations : la mesure « Montant facturé » lit `r.montant` (`dash.js:2523`) alors que la consultation porte `tarif` (`store.js:784`, `m2-consultations.js:2057`). Il n'y a pas de `montant` : mesure à zéro (non vérifié à l'exécution). L'axe « Service » retombe sur `type` (`dash.js:2520`) : la consultation n'a pas de champ `service`.
3. **Moyenne.** Aucun filtre croisé sur les écrans de statistiques : seule la plage du/au (`dash.js:3955-3960`). Pas de service, praticien, pathologie, assurance, sexe, âge, quartier ; pas de comparaison de période.
4. **Moyenne.** Les 260 consultations semées (`store.js:768-790`) ne portent aucune pathologie ; seules les fiches issues des dossiers (une sur deux, `data-seed.js:841`) en portent. Le tableau de morbidité repose donc sur un échantillon que l'écran ne dit pas (il dit seulement « avant la mise en place du référentiel », `m2-consultations.js:2531`).
5. **Moyenne.** `m2-stats-consultations` n'a ni export CSV ni état imprimable ; `m3-stats-hospitalisations` n'a pas de CSV (`dash.js:4491` seulement).
6. **Moyenne.** Hospitalisation sans code pathologie ni issue : mortalité, réhospitalisation par pathologie et DMS par pathologie sont impossibles. La DMS par diagnostic dépend d'un texte libre (`dash.js:4452`), donc d'orthographes multiples.
7. **Basse.** `D.PATHOLOGIES` est validée par les médecins (`store.js:2950`), mais la maquette ne propose aucune notion de pathologie chronique ni de classement par chapitre dans les statistiques d'hospitalisation.
8. **Basse.** Taux d'occupation : à la date seulement (`dash.js:4433`), annoncé, sans série historique.

## 4. Plan de correction en lots (maquette d'abord, puis poste)

- **Lot 1, correction des chiffres faux (D1, D2).** `dash.js:3978` : retenir `statut === 'terminee'` et libeller « Consultations réalisées » ; ajouter un KPI « Rendez-vous planifiés ou non honorés » à part. `dash.js:2523` : `r.tarif`. `dash.js:2520` : retirer l'axe « Service » ou le dériver du service du praticien (comme l'écran des consultations). Sondes : nouveau scénario compte affiché = recompte du magasin avec statuts mélangés ; mesure « Montant facturé » non nulle.
- **Lot 2, socle de calcul.** Créer dans `js/parcours.js` (fabrique unique, exposée `SIGH.statsPatient`) : jointure consultation et admission vers patient (sexe, âge, quartier, couverture à la date), comorbidité, réhospitalisation 30 j, rotation des lits, première/suivi, fréquence de recours. Ne rien écrire en base. Sondes : réhospitalisation sur deux admissions fabriquées ; comorbidité sur fiche à deux codes.
- **Lot 3, écran « Statistiques par patient et par pathologie » (PIL).** Une barre de filtres commune (période avec comparaison à l'unité précédente, service, praticien, pathologie, prise en charge, tranche d'âge, sexe, quartier, nature d'acte) ; blocs consultations, soins, hospitalisations ; export CSV de chaque tableau (`U.dataTable` + `exportName`) ; état imprimable (`P.etat`, filtres relevés par `print.js`). Fichiers : `js/nav.js` (entrée + rôles medecin, dm, da, direction, admin), `modules/dashboards.js` ou nouveau module PIL, `build/gen-pages.js` si nouveau module. Version : `VERSION` seulement si une collection ou un champ semé change.
- **Lot 4, saisies manquantes (après arbitrage).** `m3-hospitalisation.js` : champs mode d'entrée et issue du séjour (RG-06/07 inchangées) ; `m2-consultations.js` : `priseLe` du rendez-vous, heures d'appel et de début de consultation ; événement indésirable ; `D.PATHOLOGIES` : drapeau `chronique`. Incrément `VERSION`. Sondes : saisie, puis recalcul des délais.
- **Lot 5, vue par patient.** Chronologie unique triée (consultations, soins, admissions, analyses, imagerie, factures) sur la fiche `m1-patients.js`, avec compteurs de recours par année ; droits de la fiche inchangés (RG-13).
- **Lot 6, poste Flutter.** Porter lots 1 à 3 dans `apps/poste/lib/modules/pil/` (`pil_clinique.dart`, `pil_commun.dart`, domaine dans `packages/domaine`), vecteurs tirés de l'écran réel via `build/vecteurs-pilotage.js`, mise à jour de `docs/architecture/parite-statuts.json` ; consigner les écarts dans `ECARTS-MAQUETTE.md`.

## 5. Questions pour la Direction

1. La clinique veut-elle coder les diagnostics en CIM-10 (aujourd'hui référentiel propre, sans codification) ? Sinon la ligne 1.2 du catalogue reste non calculable.
2. Les statistiques par patient restent-elles agrégées (RG-13), ou la Direction veut-elle aussi une liste nominative, et pour quels profils ?
3. Que signifie « patient fidèle » pour la clinique (deux venues ou plus en 12 mois, par exemple) ?
4. Dialyse, chimiothérapie, rééducation : la clinique les pratique-t-elle ? Sinon on ne les ajoute pas.
5. Peut-on dater le règlement de chaque facture mère par l'assureur (délai moyen de paiement) ?
6. Saisir, à l'accueil et à la sortie d'hospitalisation, le mode d'entrée, l'issue du séjour et l'heure d'appel du patient : accord pour ces champs supplémentaires ?

Audit lu seulement, aucun code modifié
