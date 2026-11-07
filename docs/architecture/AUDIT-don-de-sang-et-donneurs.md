# Audit : don de sang, donneurs et demandes de bon de sang (M5, avec la surveillance M3)

Date : 07/11/2026. Audit en lecture seule. Fait nouveau de la Direction : lors d'une campagne de don, l'ANTS (agence nationale de transfusion sanguine) transporte et stocke le sang chez elle ; la clinique ne stocke pas de sang et ÉMET des demandes de bon de sang auprès de l'ANTS.

## 1. Périmètre examiné

- Maquette : `prototype_html/assets/js/modules/m5-laboratoire.js:3386-3585` (écrans `m5-banque-sang`, `m5-donneurs`), `m3-hospitalisation.js:2540-2735` (`m3-transfusion`), `store.js:2001-2002` et `2929-2940` (fermeture par activité), `store.js:4068` (libellés de corbeille), `nav.js:303-331` et `1186-1230`, `data.js:1097` (`GROUPES_SANGUINS`), `data.js:2126` et `rapports.js:30` (état « Bon de demande de sang »), `data-seed.js:409-450`, `build/test-fonctionnel.js:3437-3467`.
- Poste : `apps/poste/lib/modules/m5/sang_banque.dart`, `sang_donneurs.dart`, `sang_crud.dart`, `sang_stats.dart`, `registre_m5.dart:34-37`, `apps/poste/lib/modules/m3/surv_transfusion.dart`.
- Documents de cadrage : grep « sang | transfus | donneur | ANTS » sur `docs/cadrage`, `docs/annexes`, `docs/prd`, `docs/specs`, `Instructions/`, `suite/`, `reunions/`, `draf1.txt`, `draft2.txt` : AUCUNE occurrence (les PDF scannés sans couche texte et les docx ne sont pas lisibles par grep : « non vérifié » pour leur contenu). Seules mentions textuelles : la description de poste de l'Infirmier Général citée en `m3-hospitalisation.js:2543` (« vérifier le bon remplissage des documents de transfusion sanguine »), et `docs/architecture/ECARTS-MAQUETTE.md` E200 à E205, E1126, `LIMITES-ET-SOLUTIONS.md` A4. Le motif « La clinique ne pratique pas la banque de sang » vient d'une décision de la Direction du 21/08/2026 (`store.js:2932-2933`), pas d'un document. Le grep `\bANTS\b|\bCNTS\b|hémovigilance|bon de sang` sur `prototype_html/assets/js`, `apps/poste/lib`, `packages` ne donne rien : le processus réel n'est modélisé nulle part.

## 2. Ce que ferme exactement la fermeture par activité

- Deux fiches `modulesActifs` : MOD01 ferme `m5-banque-sang` (`store.js:2930-2934`), MOD02 ferme `m5-donneurs` (`store.js:2936-2940`), `actif: false`. Le module M5 et `m3-transfusion` restent ouverts (commentaire `m3-hospitalisation.js:2541-2546`).
- Effet : écrans retirés du ruban, de la recherche, des hubs et de leurs adresses pour tous les rôles, admin compris (E203, `ECARTS-MAQUETTE.md:241`). Le banc le sonde (`test-fonctionnel.js:3452-3453`).
- Conséquence non dite : l'état imprimable « Bon de demande de sang » (`data.js:2126`) pointe vers `m5-banque-sang` (`rapports.js:30`), écran fermé : le lien de la bibliothèque des états mène à un refus. Le seul bouton qui imprime ce bon est sur l'écran fermé (`m5-laboratoire.js:3439`). Donc la demande de sang n'est atteignable par personne aujourd'hui.
- Incohérence de vocabulaire : le motif de MOD02 dit « ne pratique pas la transfusion » (`store.js:2938`) alors que `m3-transfusion` documente que la clinique en POSE (`m3-hospitalisation.js:2541-2546`).

## 3. Fonction demandée contre l'existant

| Fonction demandée | Existe (maquette) | Existe (poste) | Manque | Preuve |
|---|---|---|---|---|
| Stock de poches, groupage, péremption | Oui, mais INCOMPATIBLE avec le processus réel | Oui, porté tel quel | À retirer ou à reléguer : la clinique ne stocke pas | `m5-laboratoire.js:3393-3495`, `sang_banque.dart:12-20` |
| Poches amorcées au hasard (2 à 9 par groupe, donneurs fictifs) | Oui, amorçage à l'ouverture | Non semées | Données de démonstration d'un stock qui n'existe pas | `m5-laboratoire.js:3395-3412` |
| Fiche de campagne de don (date, lieu, organisation, ANTS) | Non | Non | Collection, écran, état | grep `campagne` sans résultat dans M5 |
| Registre des donneurs | Partiel : nom, téléphone, groupe, type, dernier don, éligible (booléen) | Oui, porté | Consentement, questionnaire pré-don, motif d'ajournement et durée, dépistage, rattachement à une campagne | `m5-laboratoire.js:3504-3585`, `sang_donneurs.dart` |
| Éligibilité | Règle unique en dur : 90 jours depuis le dernier don, case à cocher libre | Idem | Règle par sexe et par produit, ajournement daté et motivé, contre-indications | `m5-laboratoire.js:3543-3545` |
| Résultats de dépistage transmis par l'ANTS | Non | Non | Champ « résultat transmis, date, confidentialité » sans stocker de donnée infectieuse en clair | grep `depistage` sans résultat |
| Demande de bon de sang (patient, prescripteur, groupe/rhésus, produit, quantité, urgence, justification, états) | Non : seulement un tableau papier vide imprimé | Non | Collection, écran, cycle d'états, impression à signatures | `m5-laboratoire.js:3439-3458` (cases vides, patient non lié) |
| Produit sanguin demandé (CGR, plasma, plaquettes, sang total) | Non | Non | Référentiel à fournir par le biologiste | grep `CGR|plasma` sans résultat |
| Traçabilité transfusionnelle (n° de poche ANTS, heure, surveillance, incident) | Oui, à temps imposés, poche de PSL en texte libre, incident case + nature | Oui | Lien vers la demande de bon, lot ANTS contrôlé, groupe du receveur et de la poche, déclaration d'hémovigilance, contrôle ultime au lit | `m3-hospitalisation.js:2548-2735`, `surv_transfusion.dart:40` |
| Hémovigilance (déclaration, suivi, retour d'information à l'ANTS) | Non (une alerte sonore à l'incident seulement) | Non | Fiche d'incident transfusionnel distincte, imputabilité, transmission | `m3-hospitalisation.js:2730` |
| Facturation de la prestation | Non : aucune ligne payable ; seul le tarif « Pose de transfusion » 1 000 / 1 500 existe | Non | Ligne de facture, règle RG-09, décision sur le produit (frais ANTS refacturés ou non) | `data-tarifs.js:195`, 0 appel `PR.` dans M5 sang |
| Impression à en-tête officiel et signatures | Bon à trois signatures, cases vides, nom du laborantin écrit en dur | Oui, porté | Bon rempli depuis la demande, numéro de pièce certifiante, signature du prescripteur et du biologiste | `m5-laboratoire.js:3456-3457` |
| RBAC et confidentialité (RG-13) | Aucune fiche d'écran : droits du module M5 (laborantin, médecin, dm, admin, direction) | Idem | Droits propres (prescrire, transmettre, recevoir, délivrer) ; donneur et receveur sont des données de santé | `nav.js:309`, grep `m5-donneurs` dans les fiches RBAC : seulement `store.js:2937` |
| Statistiques | Non (4 KPI de stock) | `sang_stats.dart` : à relire | Demandes par état, délai de réponse ANTS, taux de refus, dons par campagne | `m5-laboratoire.js:3420-3425` |

## 4. Défauts réels trouvés

1. Gravité haute. La maquette modélise un stock local de poches avec péremption, destruction et réservation (`m5-laboratoire.js:3416-3424`), faux au regard du processus réel : si l'activité est rouverte telle quelle, elle présente des disponibilités qui n'existent pas, ce que la clinique ne peut pas honorer.
2. Gravité haute. Le « Bon de demande de sang » est un tableau papier vide (`m5-laboratoire.js:3443-3450`) : patient, groupe et indication ne sont pas liés au dossier, rien n'est enregistré, aucun état de suivi. Il est de plus inatteignable (écran fermé, `rapports.js:30`).
3. Gravité moyenne. `m3-transfusion` demande une « poche de PSL » en texte libre sans lien avec une demande de bon, sans contrôle de compatibilité receveur / poche (`m3-hospitalisation.js:2668-2669`). La traçabilité exigée par l'hémovigilance (poche, receveur, produit) est donc rompue en amont. Même forme au poste (`surv_transfusion.dart:40`).
4. Gravité moyenne. Un incident transfusionnel n'est qu'une case et un texte plus une alerte (`m3-hospitalisation.js:2682-2683, 2730`) : aucune déclaration, aucun suivi, aucune imputabilité.
5. Gravité moyenne. Le motif de MOD02 (« ne pratique pas la transfusion », `store.js:2938`) contredit `m3-transfusion` ouvert ; le nom de MOD01/MOD02 et l'intitulé « Donneurs & transfusions » (`nav.js:331`) annoncent une transfusion que l'écran ne tient pas (il ne tient que des donneurs).
6. Gravité moyenne. Éligibilité : booléen saisi à la main et règle de 90 jours en dur, identique pour tous (`m5-laboratoire.js:3543-3545`), non documentée ; viole « ne rien coder en dur ». Un donneur sans date de dernier don est traité au poste (E202) mais pas modélisé comme ajourné.
7. Gravité moyenne. Confidentialité : le registre des donneurs copie nom, téléphone et groupe depuis le répertoire patient (`m5-laboratoire.js:3513-3518`) ; aucun consentement, aucun droit d'écran propre. Les cloisonnements de RG-13 ne sont pas posés (aucune fiche RBAC ne nomme `m5-donneurs`).
8. Gravité basse. `etat` de la poche écrit à la saisie, jamais recalculé (E201) ; E204 : poches et donneurs amorcés seulement à l'ouverture de l'écran, donc absents du jeu extrait. Sans objet si le stock est retiré.
9. Gravité basse. Le bon porte en dur le nom d'un agent (`m5-laboratoire.js:3456`, `3580`), contraire à la règle des signatures nominatives lues du compte.
10. Non vérifié : le contenu des PDF et docx de `docs/`, `suite/`, `reunions/` (aucune couche texte) : une mention de la banque de sang ou de l'ANTS peut y figurer.

## 5. Plan de correction en lots (maquette d'abord, puis poste)

Principe : une demande de bon est une pièce émise, elle ne se réécrit pas (RG-14) ; l'ANTS est un tiers, aucune donnée de contact n'est inventée.

- Lot 0, arbitrages : obtenir les réponses de la section 6. Rien de codé avant.
- Lot 1, maquette, socle de données (`store.js`, `VERSION` +1 car collections semées) : collections `campagnesDon`, `demandesSang` (cycle demandée, transmise à l'ANTS, reçue, délivrée, refusée, retournée ; motif obligatoire au refus et au retour ; horodatage et auteur à chaque transition), référentiel `produitsSanguins` marqué « proposition à valider ». Retirer `poches` du jeu et de `COLLECTIONS_ESSENTIELLES` ; libellés de corbeille (`store.js:4068`). Fabrique unique `PR.ouvrirDemandeSang` dans `parcours.js` (patient du répertoire ou externe via `PR.dossierExterne`, numéro `NNNNN-AAAA` série annuelle comme `PR.codeAnalyse`).
- Lot 2, maquette, écrans (`m5-laboratoire.js`, `nav.js`) : `m5-demandes-sang` (registre à états), `m5-campagnes-don`, refonte de `m5-donneurs` (consentement, questionnaire pré-don en variables, ajournement daté et motivé, résultat de dépistage transmis stocké comme « conforme / à convoquer » sans détail infectieux en clair, rattachement à une campagne). Remplacer `m5-banque-sang` par une page-renvoi hors ruban (doctrine : jamais retirer l'entrée du manifeste). Supprimer le motif contradictoire de MOD02, rouvrir les écrans par `modulesActifs` seulement après arbitrage.
- Lot 3, maquette, traçabilité (`m3-hospitalisation.js`) : `pochePSL` devient le numéro de poche ANTS choisi parmi les demandes « reçues » du patient ; contrôle de compatibilité receveur / poche en refus nommé ; fiche d'incident transfusionnel (collection `incidentsTransfusionnels`, gravité, imputabilité, déclaration transmise) ; signalement conservé, jamais refusé quand le protocole est incomplet (doctrine existante).
- Lot 4, maquette, caisse et pièces : ligne payable `demandeSangId` dans la facture selon la décision tarifaire (`PR.prescrire`), tarif d'attente marqué `tarifProvisoire` (aucun document ne le fixe) ; impression du bon de demande à en-tête officiel, trois signatures lues des comptes (prescripteur, biologiste, Direction médicale), numéro de pièce, filtres en force ; corriger `rapports.js:30`.
- Lot 5, droits : fiches RBAC avec droits par écran (prescrire : médecin et sage-femme ; transmettre et recevoir : biologiste ; délivrer : biologiste ; lecture : infirmier, surveillant) ; écran donneurs fermé à l'accueil et au caissier ; `m5-demandes-sang` accessible au prescripteur par déclaration `servant` si une page de saisie est créée. Relancer `npm run audit-rbac` et `inventaire-rbac`.
- Lot 6, statistiques (`m5-stats-sang`, PIL) calculées depuis les registres : demandes par état et par urgence, délai de réponse, taux de refus, dons par campagne ; « non calculable » quand la donnée manque.
- Lot 7, poste Flutter : porter dans `apps/poste/lib/modules/m5/` les nouveaux écrans, retirer `sang_banque.dart`, adapter `registre_m5.dart:34-37` et `surv_transfusion.dart`, tests de parité N1 (vecteurs tirés de l'écran réel), ECARTS-MAQUETTE.
- Sondes à écrire (nouveau scénario du banc) : cycle complet de la demande avec refus nommé sans motif ; compatibilité receveur / poche ; une demande transmise ne se modifie plus ; le caissier n'ouvre ni donneurs ni demandes ; l'incident crée sa fiche ; aucune poche ne subsiste au jeu ; compte affiché = recompte du magasin ; le bon imprimé porte les trois signatures et le numéro.

## 6. Questions pour la Direction

1. Contact ANTS : nom du correspondant, canal de transmission (papier, courriel, téléphone), gabarit exact de leur bon de demande. À fournir : numéros de téléphone, adresse et courriel de l'ANTS (rien n'est inventé dans le logiciel).
2. Un bon rempli par la clinique doit-il reproduire le formulaire de l'ANTS ? Un exemplaire est-il disponible ?
3. Produits demandés : sang total, concentré de globules rouges, plasma, plaquettes ? Quels tarifs de refacturation au patient, et la clinique perçoit-elle un frais d'acte distinct de la pose (1 000 / 1 500 existe) ?
4. Qui prescrit, qui transmet à l'ANTS, qui réceptionne la poche, qui signe la délivrance ?
5. Le don de sang en campagne se tient-il dans la clinique ou hors site ? Qui tient le registre des donneurs, et l'ANTS en conserve-t-elle l'original ?
6. Résultats de dépistage transmis par l'ANTS : doivent-ils figurer au registre de la clinique, ou la clinique ne détient-elle que « apte / ajourné » ?
7. Retire-t-on définitivement la notion de stock de poches (arbitrage à noter comme exception, car archivage normalement) ?

## Décision de la Direction du 07/11/2026
L'**ANTS n'est qu'un exemple** d'organisme. Il faut donc créer un **écran « Organismes partenaires »** (entreprises et établissements auxquels la clinique adresse des demandes : agence de transfusion, autres fournisseurs de produits sanguins ou de services) et un **formulaire de demande de bon enregistrable** qui choisit l'organisme dans ce registre. Chaque organisme porte ses propres coordonnées, contacts et gabarit de bon, **saisis par l'administration** (aucune coordonnée ni gabarit n'est inventé ou préchargé). Les sept questions du rapport restent à valider ; celle sur les coordonnées de l'ANTS est remplacée par « saisir les organismes dans l'écran ».

Audit lu seulement, aucun code modifié.
