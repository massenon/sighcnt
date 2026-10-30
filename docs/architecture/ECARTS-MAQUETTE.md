# Écarts relevés dans la maquette au moment du portage

> Règle du dépôt : **on porte fidèlement, on signale, on ne corrige pas d'office** (« extraire, ne pas deviner »). Chaque écart ci-dessous est reproduit par un vecteur engendré par la maquette ; le portage Dart en rend le même comportement. Corriger exige une décision de la Direction, puis un changement **dans la maquette d'abord** (exécutable de référence), puis la régénération des vecteurs.

| # | Où | Constat | Effet | Vecteur |
|---|---|---|---|---|
| E1 ✅ **corrigé le 30/10/2026** | `PR.encaisser` → `ecrireEncaissement` | La **part assureur de TOUTE la facture** est ré-inscrite (débit 411 et crédit 706) à **chaque versement partiel**. Une facture assurée réglée en deux fois par le patient pose deux fois la créance sur la compagnie. | Créance assureur et produits **comptés plusieurs fois** au journal (en brouillon : la validation comptable est humaine, mais elle valide ce qu'elle voit). | `encaissement.json` — « assuré : part assureur … » (2 versements, 411 = 14 000 deux fois) |
| E2 | `PR.encaisser`, pièce **sans lignes** (antérieure au modèle par lignes) | Un `montant` supérieur au dû est accepté tel quel : `montantPaye` dépasse le TTC, `baseMecef` aussi. | Base MECeF supérieure à la facture. Concerne les seules pièces anciennes (les nouvelles ont des lignes). | `encaissement.json` — « facture sans lignes … partiel puis solde » (99 999 sur 5 000 dus) |
| E3 ✅ **corrigé le 30/10/2026** | `ecrireEncaissement` | Le numéro de pièce comptable prend les **cinq derniers chiffres** du numéro de facture ; faute de chiffres (id technique), il n'en reste qu'un ou deux (`CAI-2026-8`). Le millésime `2026` est **écrit en dur**. | Collisions possibles de numéros de pièce ; millésime faux dès 2027. | `encaissement.json` — « numéro de pièce sans chiffres » |
| E4 | `PR.repartir` (`carteValide`) | La carte qui expire le jour même est valide si la date de facturation est un **jour** (`2026-08-16`), non valide si c'est un **instant** du même jour (`…T12:00:00Z`) : la comparaison est faite en millisecondes entre minuit UTC et l'instant. | Selon la manière dont l'appelant formate la date, la même carte est valide ou non le dernier jour. À normaliser en jour avant de comparer. | `prise_en_charge.json` — « carte qui expire LE JOUR même » / « date avec heure (UTC) » |

**Décision de la Direction du 30/10/2026 : « il faut corriger » E1 et E3.** Corrigés **dans la maquette d'abord** (`ecrireEncaissement`, `creanceAssureurDejaConstatee`, `numeroPieceCaisse` dans `parcours.js`), vecteurs régénérés, puis portés en Dart :
- **E1** — la créance assureur (411) et le produit correspondant (706) ne sont constatés qu'au **premier** versement ; sur la vie de la facture : 706 = facturé, 411 = part assureur, 571 = part patient.
- **E3** — le numéro de pièce est une **série annuelle** `CAI-AAAA-NNNNN` (millésime de la date de l'écriture, rang suivant) reprise par tous les versements d'une même facture.

E2 (pièce sans lignes) et E4 (date jour / instant) restent à arbitrer ; ils sont portés fidèlement.

## E5 — « Factures par jour (mois en cours) » était figé sur août 2026 — CORRIGÉ dans la maquette le 30/10/2026

`m8-facturation.js` construit les jours du graphique avec `new Date(2026, 7, d)` : le mois est écrit en dur, pas lu de l'horloge. Sur un poste réel, le graphique compterait toujours les factures d'août 2026. Le portage Dart lit le mois de l'horloge du poste (conforme au titre « mois en cours »). **À corriger dans la maquette ; le comportement du Dart fait foi.**

## Émission de facture (`m8-facturation`) — deux écarts (et un faux positif) relevés en PILOTANT l'écran réel (30/10/2026)

Les vecteurs de l'émission (`emission.json`) sont engendrés en montant l'écran dans la page d'extraction, en choisissant le patient, en ajoutant les lignes et en cliquant « Enregistrer » — `enregistrer()` vit dans la fermeture de l'écran, on ne peut pas l'appeler seul.

| # | Constat | Décision |
|---|---|---|
| E6 | Le millésime du numéro de facture est **écrit en dur** (`FN-2026-`, `PRO-2026-`) et le rang compte **toutes** les factures, non celles de l'année. | **Porté fidèlement et signalé** (comme E2) : sans effet en 2026, à arbitrer avec la série annuelle des pièces certifiantes avant le 1ᵉʳ janvier 2027. |
| E6b ✅ **corrigé** | Le rang des pièces était relu **dans la boucle** : la pièce `-B` comptait déjà la pièce `-A` insérée juste avant, d'où un trou (`…00238-A`, `…00240-B`). | Corrigé dans la maquette (`rangDebut` lu avant la boucle), vecteurs régénérés, porté. |
| E7 (retiré) | Faux positif de ma lecture : le souscripteur porte `police` (m9 l'utilise partout) ; c'est le jeu d'essai des vecteurs qui avait le mauvais champ. L'écran de la maquette était juste et n'a PAS été modifié. | Aucune — conservé ici pour que l'erreur de lecture ne se refasse pas. |

Le portage `packages/domaine/lib/src/caisse/emission.dart` porte aussi les refus nommés de la saisie : désignation vide, quantité nulle, **RG-03** (stock insuffisant en pharmacie, cumul des ajouts du même médicament compris) — la ligne refusée n'est pas ajoutée.

## Facture d'avoir (`SIGH.emettreAvoir`) — deux écarts relevés au portage (30/10/2026)

| # | Constat | Décision |
|---|---|---|
| E8 ✅ **corrigé** | La référence d'un avoir (`AV-2026-NNNN`) venait de `C.nextRef`, un compteur **en mémoire de page** qui repart à 1 à chaque chargement : deux avoirs de deux journées pouvaient porter le même numéro. Le millésime `2026` était en outre écrit en dur. | Corrigé dans la maquette (`referenceAvoir` : série annuelle lue sur les avoirs ACTIFS déjà émis, millésime de la date de l'avoir), vecteurs régénérés, porté. |
| E9 | Le texte de refus dit « déjà émise », mais le moteur **ne regarde pas le statut** de la facture mère : une mère encore en **brouillon** bloque l'avoir comme une mère émise. | **Porté fidèlement et signalé** : refuser tant que la mère n'est pas émise ferait sortir de la mère une fille qu'elle consolide encore. À arbitrer par la Direction. |

La contre-passation ne vectorise pas le contrôle RG-10 « débit ≠ crédit » de la maquette : il est **inatteignable par construction** (deux lignes du même montant). Le Dart ne le porte pas ; il vérifie l'équilibre sur chacun des vecteurs.

## Remboursements & annulations (`m8-remboursements`) — écarts relevés en PILOTANT la modale (30/10/2026)

| # | Constat | Décision |
|---|---|---|
| E8 ✅ **corrigé** (suite) | La référence `RB-NNNNN` venait aussi du compteur de page `C.nextRef` : doublons entre sessions. | Corrigé dans la maquette (`referenceSuivante`, lue sur les opérations existantes), porté. |
| E10 | Le champ « Montant (FCFA) » déclare `min: 1`, mais la valeur `0` est **acceptée** : un remboursement de 0 FCFA, ou un avoir de montant nul, s'enregistre. | **Porté fidèlement et signalé** (vecteur « montant nul : ACCEPTÉ »). À arbitrer : refuser tout montant ≤ 0. |
| E11 | La règle de l'écran dit que l'annulation d'une facture normalisée « déclenche l'émission d'un avoir MECeF » ; le code se contente de passer le statut MECeF de la facture à « rejeté » et de la marquer annulée. | **Porté fidèlement et signalé.** |
| E12 | Deux canaux de correction coexistent : cet écran (nature « Facture avoir » = une pièce **négative** dans `factures`, numérotée `AV-2026-NNNNN`) et `m8-facture-avoir` (collection `avoirs`, contre-passation en écritures — le canal de la phase 5, « l'avoir remplace l'annulation »). | **Les deux sont portés.** L'arbitrage de la Direction est nécessaire pour n'en garder qu'un. |

## MECeF (`mecef.js`) — écarts relevés en PILOTANT le module pour chaque régime de TVA (30/10/2026)

| # | Constat | Décision |
|---|---|---|
| E8 ✅ **corrigé** (suite) | `mecef-avoirs` numérotait aussi par `C.nextRef('AV-2026-', 4)` (compteur de page, millésime en dur). | Corrigé : `C.referenceSuivante` (au socle, `core.js`) lit les avoirs existants ; la maquette de `m8-facturation` s'en sert aussi. |
| E13 | « Enregistrer les paramètres » de `mecef-config` journalise la saisie mais **rien ne la relit** : `TAUX_TVA` et `TAUX_AIB` viennent de `D.PARAM_FISCAL` au chargement du module. Changer le régime de TVA à l'écran ne change aucun calcul. | **Porté fidèlement et signalé** (l'écran s'annonce « simulation »). À traiter avec l'intégration du boîtier : la configuration doit devenir une donnée du magasin. |
| E14 | La facture normalisée imprimée porte **« IFU client » = l'IFU de la clinique**, pour tous les clients. | **Porté fidèlement et signalé.** Une pièce fiscale qui nomme le mauvais IFU est un défaut réel : à corriger dès que l'identifiant fiscal du client est une donnée du dossier. |
| E15 | L'avoir MECeF ne vérifie que « montant ≤ facture » : **jamais le cumul** des avoirs, que `emettreAvoir` plafonne — c'est le **troisième canal d'avoir** (avec `m8-facture-avoir` et la nature « Facture avoir » de `m8-remboursements`). Il est transmis et validé d'office. | **Porté fidèlement et signalé.** Le point d'arbitrage est le même qu'E12 : un seul canal. |
| E16 ✅ **corrigé côté poste** | Le magasin Dart **ajoutait** les nouvelles fiches en fin de liste, alors que la maquette les insère **en tête** (`unshift`). L'ordre se voit : le lot transmis par « Synchroniser maintenant » suit l'ordre de la liste, donc le tirage graine ne tombe pas sur les mêmes factures. | `CollectionMagasin.inserer` insère en tête, `plafonner` garde les plus récentes. Les tests qui supposaient « la dernière fiche en fin de liste » sont corrigés. |
| — | L'**exercice** : la maquette filtre les registres MECeF par l'exercice choisi à l'en-tête (`SIGH.exercice`). Le sélecteur n'est pas encore porté (tranche M12). | **Limite dite** : les registres montrent tous les exercices. |

**Ce que la simulation n'est pas.** Aucun des six écrans ne parle au boîtier : les réponses du dispositif sont un tirage pseudo-aléatoire graîné (88 % d'acceptation, codes de rejet E-101…E-500). Le modèle, l'interface et le protocole du boîtier ne figurent dans aucun document du dépôt (dix questions à poser au fournisseur et à la DGI, voir ADR-0003) : le QR et le code de certification imprimés sont des **emplacements**.

## M6 — pharmacies, dispensation, étiquetage, reprise SAGE (`m6-stock.js`, `PR.delivrer`) — écarts relevés en PILOTANT les écrans (30/10/2026)

Les vecteurs (`delivrance.json`, `etiquetage.json`, `reprise.json`) sont engendrés en montant les écrans réels dans la page d'extraction, en posant produits et ordonnances au magasin jetable, en cliquant « Délivrer » / « Créer » / « Valoriser » et en relisant ce qui est né. Les numéros E40–E50 sont réservés à ce lot (d'autres lots portés en parallèle prennent d'autres plages).

| # | Constat | Décision |
|---|---|---|
| E40 ✅ **corrigé** | Les deux pharmacies testaient `statutPaiement === 'payee'` et `statutDispensation === 'delivree'` ; le parcours (`PR.encaisser`, `PR.delivrer`) écrit **`soldee`** et **`servie`**. | Toute ordonnance réglée restait « Non réglée » à jamais : les deux pharmacies ne délivraient rien. Corrigé dans la maquette (`m6-stock.js`), vecteurs régénérés, porté. |
| E41 ✅ **corrigé** | `voieDe` reconnaît « inject », « amp. », « ampoule », « perfus »… mais pas **« inj »**, l'abréviation du catalogue (48 désignations sur 184). | Aucun injectable n'arrivait en pharmacie interne : tous tombaient en voie orale (`\binj\b` ajouté). Aucune ligne d'ordonnance ne porte de `voie` (rien ne l'écrit), c'est donc la désignation qui décide. |
| E41b ✅ **corrigé** | La référence du mouvement (`M000001` dans `PR.delivrer`, `MVT-00001` dans la pharmacie) venait de `C.nextRef`, un compteur de page qui repart à 1 à chaque chargement (même défaut que E8). | `C.referenceSuivante` lit les mouvements existants ; porté (`referenceSuivante` du domaine). |
| E42 ✅ **corrigé** | `PR.verifierStock` contrôlait chaque ligne **seule** : deux lignes de 5 sur un même produit en stock de détail 8 passaient chacune, et la délivrance laissait un stock de détail de **−2** (RG-03 violée). | Le cumul des lignes d'un même produit est contrôlé ; `disponible` est ce qui reste après les lignes précédentes. Vecteur dédié. |
| E43 | `PR.alerterStock` cherche une tâche de réapprovisionnement « ouverte » par `statut !== 'termine'` ; **rien n'écrit `termine`** (une tâche close vaut `fait`). Une tâche déjà traitée est donc **mise à jour** et jamais recréée : le gestionnaire n'est plus alerté pour cet article. | **Porté fidèlement et signalé** (vecteur « déjà TERMINÉE »). À arbitrer : tester `fait`. |
| E44 ✅ **corrigé** | La délivrance par ligne des pharmacies appelait `PR.alerterStock(r.produit.id)` avec un identifiant **nu** (la fonction attend une liste) : `forEach is not a function`, levé **après** l'écriture du mouvement. | Le stock était décompté, le mouvement et l'ordonnance écrits, mais la vue ne se rafraîchissait pas et le message de succès ne paraissait jamais. Corrigé (`[id]` + justificatif), porté. |
| E45 | Les pharmacies **comptent et décomptent le stock TOTAL** (`produit.stock`) ; `PR.delivrer` (file de la dispensation) contrôle et décompte le stock de **détail** (`stockDetail`). La délivrance par ligne ne touche pas `stockDetail` : l'alerte de seuil, qui lit le stock de détail, ne voit pas la sortie. | **Porté fidèlement et signalé** : les deux circuits ne parlent pas du même stock. À arbitrer avec la Direction (lequel fait foi pour une délivrance au comptoir). |
| E46 | La délivrance **par ligne** marque l'ordonnance **entière** « servie » : délivrer la ligne orale d'une ordonnance mixte retire de la pharmacie interne ses lignes injectables, jamais servies. | **Porté fidèlement et signalé.** |
| E47 | `U.confirm({requireMotif: true})` demande le motif d'un archivage (« consigné dans le journal d'audit ») mais **accepte un motif vide** (la réponse est un objet, donc vraie). | **Porté fidèlement et signalé** (vecteur « archivage sans motif »). Le motif saisi est gardé sur la fiche (`_motifArchivage`). |
| E48 ✅ **corrigé** | Le plan des rayons groupe par `emplacement` ; `groupBy` fait de l'absence de clé la **chaîne « undefined »** : la carte des articles sans emplacement s'intitulait « undefined » (et son étiquette « undefined — 1 étiquette(s) »). | Corrigé (« Sans emplacement »), l'ordre des cartes est inchangé. |
| E49 | `m6-dispensation` embarque un `ouvrir()` (modale « Nouvelle dispensation » au panier) **inatteignable** : la décision du 02/09/2026 a retiré la commande, pas le code. | **Non porté** (code mort). |
| E50 | `m6-reprise` : l'action « Valoriser / Corriger la valorisation » d'une ligne n'est **pas** gardée par les droits (`K.iconBtn`), contrairement à « Valider la reprise » (`K.commande`). | **Porté gardé** : la commande est absente sans droit d'écriture (doctrine du kit). Le bouton « Valider la reprise » est inchangé. |

Limites du portage (dites) : l'**archivage** du poste ne pose pas `_archivePar` / `_archiveLe` comme le magasin de la maquette (le magasin du poste journalise l'archivage, RG-12) ; les **étiquettes** s'impriment une par bloc de texte de la pièce A4 (la maquette les met en grille de cadres, la pièce commune n'a pas de bloc grille) ; la méthode de **valorisation des sorties** (prix de vente ou CUMP) est un réglage d'exploitation que le jeu du poste ne porte pas : le poste valorise au prix de vente (= prix d'achat, RG-02), le moteur du domaine accepte les deux méthodes et est rejoué sur les deux.
