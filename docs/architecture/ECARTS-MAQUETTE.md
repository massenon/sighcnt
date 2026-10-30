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

## Mouvements de stock M6 (`m6-transferts`, `m6-mouvements`, `m6-inventaire-feuille`, `m6-pertes`) — écarts relevés en PILOTANT les écrans réels (30/10/2026)

Les règles vivent dans la fermeture des écrans (`ouvrir()`, `valider()`, `declarer()`, `K.crud`) : les vecteurs (`stock_mouvements.json`, 39 cas) sont tirés des écrans montés dans Chrome, modales pilotées, messages captés. Numéros E17+ attribués dans l'ordre de cette section : **à renuméroter au moment de la fusion si une autre section réclame les mêmes**.

| # | Constat | Décision |
|---|---|---|
| E17 ✅ **corrigé** | Les références `M000NNN` (mouvements saisis, régularisations d'inventaire), `INV-NNNN` et `MVT-NNNNN` (pertes) venaient de `C.nextRef`, un compteur **en mémoire de page** qui repart à 1 à chaque chargement : deux sessions pouvaient émettre le même numéro (la même classe que E8). | Corrigé dans la maquette (`C.referenceSuivante`, série lue sur les fiches existantes, archivées comprises), vecteurs régénérés, porté (`referenceSuivante` du domaine). Le numéro de bon `TR-` était déjà lu sur le registre. |
| E18 ✅ **corrigé** | La déclaration d'une perte n'écrivait pas `typeLabel` : la colonne « Nature » du registre des pertes (badge) et l'état imprimé restaient **vides** pour toute perte déclarée à l'écran (les pertes du jeu amorcé, elles, le portent). | Corrigé dans la maquette (libellé tiré de `D.TYPES_MOUVEMENT`), porté. |
| E19 ✅ **corrigé** | **Modifier un mouvement lui attribuait un NOUVEAU numéro** : le `transform` du formulaire ne recopiait pas `reference`, donc `if (!v.reference)` retombait sur la série. Un justificatif cité ailleurs (« M000123 ») ne désignait plus rien. | Corrigé dans la maquette (`transform(values, record)` conserve le numéro de la fiche), porté. |
| E20 | Un mouvement **saisi** à l'écran (`m6-mouvements`, « Nouveau ») s'écrit au registre mais **ne modifie pas le stock** du produit ; une **perte** déclarée ne décrémente que le champ `stock` (total) — ni `stockGros` ni `stockDetail`. Le total et les deux magasins peuvent donc diverger (c'est ce que l'inventaire constate ensuite : le test « total inférieur au stock du magasin » en est l'illustration). | **Porté fidèlement et signalé.** À arbitrer : qui décrémente quel magasin pour une perte (le stock concerné devrait être choisi, comme pour un mouvement). |
| E21 | La règle de `m6-pertes` annonce « génère une écriture comptable au débit du compte de charges (M12) » ; la déclaration **n'écrit aucune écriture** (seul un mouvement et une entrée de journal). | **Porté fidèlement et signalé** (le texte de la règle est conservé). À arbitrer : écrire la charge (RG-10, en brouillon) ou retirer la phrase. |
| E22 | **Archiver un bon de transfert n'annule ni ses deux mouvements par ligne ni le déplacement du stock.** Le refus de « Modifier le bon » indique pourtant « archiver ce bon, puis en émettre un nouveau » : suivre ce chemin **transfère deux fois** la marchandise. | **Porté fidèlement et signalé** (message de refus identique à la maquette). À arbitrer : l'archivage d'un bon doit-il écrire les mouvements inverses (RG-03) ? |
| E23 | La liste « Stock concerné » d'un mouvement saisi propose « Stock laboratoire », mais un article ne porte que `stockGros` et `stockDetail` : le contrôle RG-03 d'une sortie « laboratoire » retombe sur le stock **détail**. | **Porté fidèlement et signalé.** |

**Jeu de démonstration.** `apps/poste/assets/donnees/jeu/transferts.json` est **vide** alors que la maquette amorcée est censée porter 20 bons (`transfertsGrosDetail`, `data-seed.js`) : sur la base jetable des bancs, `transferts` vaut 0 fiche après l'amorçage, sans erreur console — la fonction rend 0 sans se plaindre (cause non élucidée ; 135 produits sont pourtant éligibles). Conséquence : sur le jeu livré, l'onglet « Bons de transfert » montre son état vide, **sans les en-têtes** que la fiche de parité attend (N1 = 0,818 au test partagé) ; `test/m6_mouvements_test.dart` pose son propre bon et mesure 100 %.
