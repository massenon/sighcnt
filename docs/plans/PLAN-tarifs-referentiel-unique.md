# PLAN : référentiel de prix unique, écran « Tarifs et prix », changement de prix validé et jamais rétroactif
Source : `docs/prd/PRD-TARIFS-referentiel-unique-et-changement-de-prix.md` (décisions de la Direction du 10/11 et réponses T1 à T15 du 11/11/2026, `docs/decisions/DECISIONS-A-VALIDER.md` section G) · Écarts : `docs/architecture/ECARTS-MAQUETTE.md` E2361 à E2369.

## Résultat attendu
- UNE liste de prix lue par la caisse, la prescription, les soins, l'imagerie, les certificats et la caisse manuelle, au prix EN VIGUEUR à la date de la pièce ; UN écran « Tarifs et prix » pour les proposer, les décider (Oui ou Non) et lire leur historique.
- Une pièce émise garde son prix : le prix se versionne par date d'effet, une version est immuable.
- Aucun prix facturé aujourd'hui ne change à la migration ; les prix de la grille imprimée des analyses arrivent en version 2 PROPOSÉE.

## Étapes
### Lot T0 : caractérisation [FAIT 11/11/2026]
- Ce qu'on a fait : un scénario qui mesure l'état d'AVANT (la caisse ne lit ni `catalogueTarifs` ni la collection `analyses`, une facture émise ne bouge pas, l'assurance du personnel ne relit plus le prix courant), la marge de quota (191 Ko).
- Résultat : constats 1 et 2 du PRD confirmés, constat 9 FAUX (déjà soldé par la vague 109), chiffres des analyses rectifiés (39 rapprochables, 9 sans ligne). PRD corrigé, E2361.
### Lot T1 : socle et adaptateur de lecture [FAIT 11/11/2026]
- Fichiers : `assets/js/data-tarifs.js` (moteur pur, migration, accesseurs), `assets/js/store.js` (semence, reprise, projection, parité, gardes, `VERSION` 79), `assets/js/parcours.js` (`PR.tarifALaDate` et les voies datées), `api/schema/`, `packages/schema/postgres/0001_modules.sql`.
- Preuve : `node build/capture-prix.js <sortie>` (268 codes, cinq voies, assuré et non assuré, points d'entrée publics) sur l'arbre d'avant (`build/tarifs/prix-avant-t1.json`, versionné) puis d'après, `node build/tarifs/comparer-prix.js avant.json apres.json` : 0 écart inattendu, 368 écarts attendus sur les 39 lignes LABO fusionnées (E2362, E2363). Scénario Vague 113.
- Piège à ne pas réintroduire : une version de prix ne se retire pas du serveur (RG-14, le magasin ne propage que des ajouts) : un scénario qui pose une version de sonde la pose sur une prestation NEUVE.
### Lot T2 : l'écran unique [FAIT 11/11/2026]
- Fichiers : `assets/js/modules/configuration.js` (écran et page de renvoi), `assets/js/parcours.js` (noyau `PR.proposerTarif`, `PR.deciderTarif`, `PR.retirerProposition`), `assets/js/nav.js` (libellés, hors ruban, rubriques de recherche), `assets/js/store.js` (fiche du caissier, garde des collections de lecture), `assets/js/modules/m5-laboratoire.js`, `assets/js/app.js` (projection du jour à l'ouverture d'un écran).
- Preuve : scénarios Vague 114 (une seule liste lue par cinq voies AU GESTE, une proposition ne change rien, Oui et Non à l'écran, deux droits, renvoi, recherche, liens profonds) et Vague 115 (non rétroactivité, date de la pièce, date d'effet future et horloge, rejeu, vidage) ; mutations (b), (d), (e), (g) du PRD 9.2 : voir le rapport du lot.
### Lot T3 : le circuit Oui/Non complet [À FAIRE]
- `tarif_deja_utilise`, alerte de la cloche (source `prix_a_valider`), retour à l'auteur, famille du centre des validations (lève aussi le marquage « tarif d'attente », E2366), modale avec le choix Valider, date passée permise à la DAF et à la Direction avec motif et info-bulle, « Oui à tout » encadré, un scénario par cas limite de 5.6.
### Lot T4 : l'importation [À FAIRE] (dépend de T3 et du lot d'import `K.importer`)
### Lot T5 : les produits [À FAIRE] (prix d'achat versionné, RG-02 à l'écriture, corrige E846)
### Lot T6 : le poste Flutter [À FAIRE]
- Domaine `packages/domaine/lib/src/tarifs/`, vecteurs (`build/vecteurs-tarifs.js`), écran, huit groupes de lecteurs, synchronisation (famille R : la mère seule écrit, DAF = la mère, Direction = fileul), parité N1 des trois écrans, `flutter analyze`, `flutter test`, banc de synchronisation à deux postes.
### Lot T7 : retrait des anciennes listes [À FAIRE]
- Retirer les projections, les propriétés calculées de `D.ANALYSES` et `D.TYPES_CHAMBRE`, `D.CATALOGUE` comme source ; garde de génération contre toute lecture directe. Rend aussi une partie de la marge de quota (le catalogue tarifaire pèse 50 Ko).

## Commandes
- `node prototype_html/build/capture-prix.js <sortie.json>` : relevé exhaustif (banc isolé : `SIGH_PORT_PHP`, `SIGH_BASE_TEST`, `SIGH_PORT_TEST`, `CHROME_PATH`).
- `node prototype_html/build/test-fonctionnel.js --seul=Vague_113|Vague_114|Vague_115`
