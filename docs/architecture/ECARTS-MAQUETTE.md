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

## Achats M7 — expression des besoins, commandes (RG-04), réception, livraisons, écarts (30/10/2026)

Les vecteurs (`achats-besoins.json`, `achats-commandes.json`, `achats-reception.json`) sont engendrés en PILOTANT les cinq écrans réels dans Chrome (`prototype_html/build/vecteurs-achats.js`) : profils changés, onglets cliqués, modales remplies. Numéros **E70 à E80** réservés au module M7 (pour ne pas heurter les autres tranches portées en parallèle).

| # | Constat | Décision |
|---|---|---|
| E70 ✅ **corrigé** | Les références `BEB-2026-`, `BC-2026-`, `BL-` et `M…` (mouvements) venaient de `C.nextRef`, un compteur **de page** qui repart à 1 : le premier bon créé après un rechargement s'appelait `BEB-2026-0001`, déjà pris par le jeu. | Corrigé dans la maquette (`C.referenceSuivante` lit la série sur les fiches existantes, archivées comprises), vecteurs régénérés, porté (`referenceAchatSuivante`). Le millésime `2026` reste écrit en dur (voir E77). |
| E71 ✅ **corrigé** | Le champ « Étape du circuit » n'est offert qu'à qui pilote le circuit ; pour les autres, la valeur par défaut `soumis` n'était **jamais collectée** : le bon était enregistré **sans étape** et n'apparaissait dans aucune vue (ni arbitrage, ni achat). La règle affichée — « un bon exprimé par un service part SOUMIS » — n'était pas tenue. | Corrigé dans la maquette (`soumis` posé à la création), porté. |
| E72 | **RG-04 est contournable.** (a) « Valider (DA) » est offert à tout profil qui écrit dans M7 — le gestionnaire de stock compris — et le validateur écrit est TOUJOURS `TAKI Alimatou`, quel que soit l'agent. (b) Choisir le statut « Validée », « Transmise », « Livrée » ou « Soldée » à la saisie ou à la modification d'une commande pose d'office la validation de la DAF. | **Porté fidèlement et signalé.** À arbitrer : réserver la validation à la DAF et à la Direction (rôles), refuser les statuts « validée » et suivants hors du geste de validation. |
| E73 | Même mécanisme sur les bons : qui pilote le circuit peut poser « Validation DA » ou « Quantité accordée » à la saisie ; la DAF est alors portée **validatrice sans avoir arbitré**, et aucune notification n'est émise. | **Porté fidèlement et signalé.** |
| E74 ✅ **corrigé** | Modifier un bon ou une commande **déjà validés** écrasait le validateur (et la date de validation de la commande) par `TAKI Alimatou` : le formulaire ne porte pas ces champs, `!v.valideePar` était toujours vrai. | Corrigé dans la maquette (un validateur connu n'est jamais remplacé), porté. |
| E75 ✅ **corrigé** | Modifier un bon ou une commande le **renumérotait** : `!v.reference` était toujours vrai (le formulaire ne porte pas la référence) et une nouvelle référence de la série était attribuée. Une pièce validée changeait de numéro. | Corrigé dans la maquette (la référence n'est posée qu'à la création), porté. |
| E76 | L'écran des écarts annonce que les manquants sont « **reportés automatiquement sur la livraison suivante** » ; aucun code ne le fait. Il compte aussi les **surplus** (écart positif) en valeur absolue dans la « valeur des manquants ». | **Porté fidèlement et signalé** (texte et calcul identiques). |
| E77 | Noms et millésimes en dur : `TAKI Alimatou` (validateur, signatures), `MAMAN Zoukanéri` et `DIEYABIDI Aïssatou` (contrôleurs proposés, signatures), `2026` dans `BEB-2026-` / `BC-2026-` (même défaut que E6). | **Porté fidèlement et signalé** ; à résoudre avec la série annuelle des pièces avant le 1er janvier 2027. |
| E78 ✅ **corrigé** | Modifier un bon de livraison écrivait les contrôleurs en **texte** là où l'écran les lit en **liste** : le détail du bon cassait au clic (`.join` sur une chaîne), hors de portée de `npm run check`. | Corrigé dans la maquette (conversion du texte en liste à l'enregistrement), vecteurs régénérés, porté (`livraisonModifiee`). |
| E79 ✅ **corrigé** | « Réceptionner » (qui ÉCRIT un bordereau, une entrée en stock gros et un nouveau CUMP) était offert à tout profil qui lit l'écran (direction, comptable). | Corrigé dans la maquette (`K.commande` : absente sans droit d'écrire), porté. |
| E80 | La saisie d'une réception est indexée par article : une commande qui porte **deux fois le même article** n'a qu'une saisie (la dernière) et le bordereau n'a qu'une ligne pour lui. Un article absent du référentiel est écrit au bordereau mais n'entre pas en stock, sans le dire. Les gestes « Transformer en bon de commande » et « Marquer distribué » ne sont gardés que par la vue (comptable compris), pas par un droit d'écriture explicite. | **Porté fidèlement et signalé.** |

Limites du portage (dites) : le poste n'a pas d'identité personnelle — « Mes demandes » compare le demandeur au **libellé du profil** connecté (les bons du jeu portent des noms de personnes : cette vue est vide tant que les bons ne sont pas créés au poste) ; l'article « Nouvel article » de la modale des besoins (création d'un produit au référentiel M6, gardée par un droit M6) n'est pas portée.
