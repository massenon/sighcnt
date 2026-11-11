# PLAN : le bouton « Importer les données » dans chaque écran qui reçoit des données en masse, et le droit d'import distinct par jeu
Source : `docs/prd/PRD-IMP-bouton-importer-par-ecran.md` (décisions de la Direction du 10/11 et réponses I4 à I13 du 11/11/2026, `docs/decisions/DECISIONS-A-VALIDER.md` sections E, G et K) et `docs/prd/PRD-TARIFS-referentiel-unique-et-changement-de-prix.md` section 7 (jeu `tarifs`) · Écarts : `docs/architecture/ECARTS-MAQUETTE.md` E2410 à E2421.

## Résultat attendu
- UN bouton « Importer les données » (fabrique unique `K.importer`, fenêtre en trois temps : modèle, vérification sans écriture, import), ABSENT sans le droit d'importer du jeu, posé sur l'écran qui reçoit les données.
- UN droit d'import par jeu (`voir`, `importer`, `annuler`), déclaré au manifeste (`N.IMPORTS`), porté par la fiche RBAC (`droitsImport`) et par `rbac.json` (section `import`), jamais déduit du droit d'éditer l'écran ; le moteur refuse aussi.
- La rangée « Importation de données » SEULE ouverte aux postes qui détiennent un jeu (calculée de la matrice) ; le reste de l'onglet « Système » reste réservé.
- Aucune donnée sensible recopiée dans l'historique d'un jeu restreint ; un seul jeu de prix `tarifs`, écrit par le même chemin que la saisie à l'écran.

## Étapes
### Lot L0 : le socle [FAIT 11/11/2026, maquette]
- Fichiers : `assets/js/nav.js` (`N.IMPORTS`, `N.droitImport`, `importsVisibles`, `superviseImport`, `capacitePaie`, ruban), `build/gen-pages.js` (garde des jeux), `assets/js/modules/_kit.js` (`K.importer`, clé `importer` de `K.crud`), `assets/js/app.js` (chargeur paresseux exposé), `assets/js/modules/import.js` (droit au moteur, masquage, modes de doublon, colonnes selon le profil, taille maximale réglable, historique par auteur), `assets/js/modules/m14-securite.js` (section « Importation » de « Rôles & permissions »), `build/extraire.js` (`rbac.json` section `import`), `assets/js/store.js` (`VERSION` 80).
- Preuve : scénarios Vague 121 (droit distinct, bouton présent ou absent sur chaque hôte, moteur qui refuse), 122 (rangée du ruban, matrice administrable), 123 (masquage, salaire, groupe sanguin, taille maximale, « ignorer », supervision) ; mutations et mesure : voir E2418, E2419.
### Lot L1 : les jeux existants sur leurs écrans [FAIT 11/11/2026, maquette]
- Hôtes du bouton : `m6-stock-gros` (jeu `grand-stock`), `m7-fournisseurs`, `m9-compagnies`, `m12-plan-comptable`, `m12-ouverture`, `m1-patients`, `m10-personnel`, `cfg-tarifs`. Les pages `imp-*` et `m6-import-grand-stock` deviennent des pages de supervision (même contenu, droit `voir` du jeu).
### Lot T4 : le jeu `tarifs` [FAIT 11/11/2026, maquette]
- Fichiers : `assets/js/parcours.js` (`PR.evaluerProposition`, `proposerTarif` en mode essai et par l'import), `assets/js/modules/import.js` (jeu `tarifs`, `analyses-modele`), `assets/js/modules/configuration.js` (bouton sur `cfg-tarifs`).
- Preuve : scénarios Vague 124 (décisions Oui, vide, Non, inchangée, tiret, zéro, NC, tout ou rien) et 125 (gestionnaire de stock, prix déjà utilisé, annulation). Voir E2416, E2417.
### Lot IMP-B : stock et autres référentiels [À FAIRE]
- `produits-referentiel`, `emplacements`, `transfert-lignes`, `stock-detail-initial`, `inventaire-comptage`, `tarifs-produits` (prix d'achat, T5), `couvertures-assurance`, `garanties`, `centres-couts`, `natures-facture`, `catalogue-imagerie`, `unites-labo`, `prestataires`, `immobilisations`, `budgets`, `courriers`. Chaque jeu s'ajoute à `N.IMPORTS` et au moteur : `gen-pages` refuse l'un sans l'autre.
### Lot IMP-C : le poste Flutter et la demande d'import fileul vers mère [À FAIRE, derrière la maquette]
- Section `import` de `rbac.json` lue par la matrice du poste, `BoutonImporter`, jeux portés dans `packages/domaine`, vecteurs tirés de la maquette ; le poste du gestionnaire de stock est un FILEUL (réponse Q5) : demande d'import vérifiée (collection `demandesImport`, famille B) appliquée par la mère.

## Commandes
- `node prototype_html/build/test-import.js` : non-régression des jeux (banc isolé : `SIGH_PORT_PHP`, `SIGH_BASE_TEST`, `SIGH_PORT_TEST`, `CHROME_PATH`).
- `node prototype_html/build/test-fonctionnel.js --seul=Vague_121|Vague_122|Vague_123|Vague_124|Vague_125`
- `node prototype_html/build/audit-rbac.js --pages=m7-fournisseurs,imp-fournisseurs` (la sonde du droit d'import s'exécute pour les hôtes et pages de jeu cités)
- `node prototype_html/build/extraire.js rbac` puis les générateurs de vecteurs dépendants du manifeste (voir E2420).
