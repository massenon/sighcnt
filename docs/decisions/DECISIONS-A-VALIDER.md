# Décisions de la Direction

**Statut : toutes les recommandations ci-dessous sont VALIDÉES par la Direction le 09/11/2026** (« je valide toutes tes décisions »). Les cases restent pour mémoire : lire la colonne « Recommandation » comme la décision arrêtée. Deux points ne sont pas des décisions mais des démarches : le texte réglementaire de l'AIB (Q1) et la charge des 5 % (Q7) restent à obtenir auprès de l'expert-comptable ou du centre des impôts ; en attendant, l'AIB reste un acompte imputable affiché sans écriture et tout reste « proposition à valider ».

État au 09/11/2026. Une ligne par décision : cocher une case ou écrire une réponse, et rien d'autre à faire. Les recommandations sont celles de l'équipe de développement ; aucune n'est appliquée tant que la case n'est pas cochée.

## A. Déjà tranchées (pour mémoire)

- CNSS : la déclaration reste au 10, modifiable dans les paramètres ; une obligation « versement des cotisations » est ajoutée au 15, marquée « à confirmer par la CNSS ».
- Barème AIB par situation de l'acheteur (IFU actif 1 %, sans IFU actif 5 %, prestation de service 3 %) : en place, marqué « proposition à valider ».
- Tout taux, date et seuil est modifiable dans les paramètres.

## B. À trancher

### 1. Validation par modale (PRD `docs/prd/PRD-M13-validation-par-modale-et-fin-du-statut-a-valider.md`)

| N° | Question | Recommandation | Réponse |
|---|---|---|---|
| Q1 | « En enregistrant, plus de statut à valider » vaut-il pour les seuls profils de la famille de validation ? | Oui : la Direction ne signe pas à la place du professionnel | ☐ Oui ☐ Non |
| Q2 | Un profil qui peut modifier sans être de la famille (ex. administrateur sur une borne de laboratoire) | (b) il enregistre, l'élément repasse « à valider » | ☐ (a) refus ☐ (b) repasse à valider ☐ (c) proposition à accepter |
| Q3 | Les éléments semés restent-ils « à valider » jusqu'à la première relecture par la famille ? | Oui | ☐ Oui ☐ Non |
| Q4 | Motif obligatoire quand le validateur modifie une valeur ? | Oui pour les valeurs chiffrées (bornes, tarifs, barème), non pour les libellés | ☐ Oui ☐ Non ☐ Autre |
| Q5 | Un élément créé par un validateur naît-il validé ? | Oui | ☐ Oui ☐ Non |

### 2. AIB (PRD `docs/prd/PRD-M12-bareme-AIB-calendrier-fiscal-et-valeurs-d-attente-du-personnel.md`)

| N° | Question | Recommandation | Réponse |
|---|---|---|---|
| Q1 | Fournir le texte réglementaire (communiqué DGI de septembre 2026, articles 132 d) et 135 du CGI) | À demander à l'expert-comptable ou au centre des impôts de Natitingou ; d'ici là tout reste « proposition à valider » | ☐ Texte joint ☐ À demander |
| Q3 | Taux par défaut de la fenêtre MECeF : selon la situation de l'acheteur, pas un taux unique | Oui (déjà appliqué) | ☐ Confirmé ☐ Autre |
| Q5 | Brancher l'AIB sur les écritures d'achat | Différer : le comptable choisit d'abord le compte d'acompte | ☐ Différer ☐ Brancher |
| Q7 | Qui supporte le prélèvement de 5 % : l'acheteur ou la clinique ? | Aucune : à trancher avec le texte officiel ou l'expert-comptable. L'AIB reste un acompte imputable, sans écriture | ☐ Acheteur ☐ Clinique ☐ À demander |

### 3. MECeF au poste

| Question | Recommandation | Réponse |
|---|---|---|
| Sans boîtier, le poste peut-il attribuer un numéro simulé, clairement non fiscal ? | Oui, avec la mention « non fiscal » sur la pièce et l'écran. Aucune pièce simulée ne sert de preuve fiscale | ☐ Oui ☐ Non |

### 4. Planning individuel (PRD `docs/prd/PRD-M10-planning-individuel-et-libre-service-agent.md`)

| N° | Question | Recommandation | Réponse |
|---|---|---|---|
| Q1 | Le régime individuel déroge-t-il champ par champ ou remplace-t-il celui de la catégorie ? | Déroge champ par champ (durée, repos, honoraire), le reste suit la catégorie | ☐ Champ par champ ☐ Remplace |

## C. Travail restant (aucune décision requise, ordre proposé)

1. Valeurs d'attente du personnel : marquage par champ, sans valeur inventée.
2. Portage vers les vecteurs, le Dart et le poste du barème AIB, des paramètres fiscaux, du calendrier et du versement CNSS.
3. MECeF : écran des modes, puis adaptateur du vrai boîtier (dix questions au fournisseur et à la DGI restent à poser, voir l'ADR).
4. SMS : étapes S3 à S6 (vecteurs, domaine, relais, poste).
5. Module satisfaction.
6. Relais en ligne : étapes R0 à R7.
7. Dictionnaire de données à régénérer pour les nouvelles tables.
8. Une vingtaine de rechargements de page (MECeF, M2, M7, M9, M10, M13, M14) à rendre attentifs à l'envoi, comme celui de la clôture (E2307).

## D. Réponses de la Direction du 09/11/2026 (formulaire de validation)

Les 18 questions ont reçu une réponse. Règle générale posée par la Direction : **tout ce qui est paramétrable l'est dans les paramètres du poste, ENREGISTRÉ EN BASE de données (jamais une constante du code), avec un défaut** semé et modifiable ; un paramètre qui change se versionne par date quand des pièces ont été émises sous l'ancienne valeur.

| Question | Réponse | Paramétrage demandé |
|---|---|---|
| Validation Q1 à Q5 | recommandations retenues (oui, b, oui, valeurs chiffrées, oui) | |
| AIB Q3 | taux selon la situation de l'acheteur | |
| AIB Q5 | différer le branchement sur les écritures d'achat | formulaire de validation du branchement dans les paramètres |
| AIB Q7 | la clinique supporte le prélèvement | **paramétrable**, défaut « clinique » (la clinique ne subit pas d'AIB) |
| MECeF simulé | non : pas de numéro simulé ; **choix boîtier ou e-MECeF dans les paramètres du poste** | choix du mode |
| Planning Q1 | déroge champ par champ | |
| Planning Q3, Q6, Q8 | recommandations retenues | |
| Planning Q4 | l'agent propose, le surveillant valide | **paramétrable** oui/non, défaut non |
| Planning Q5 | copie chiffrée de la fiche de paie sur le téléphone | **paramétrable** oui/non, défaut oui |

**Synchronisation des paramètres (Direction, 09/11/2026)** : les paramètres se règlent au poste, se synchronisent du poste vers le relais, qui les stocke **chiffrés** (relais opaque, il ne lit jamais leur contenu) ; le panneau web du relais n'affiche que les **réglages propres au relais** (appareils, jetons, sauvegardes, supervision). Un paramètre métier ne se règle donc jamais dans le panneau web.

### Contradictions tranchées : la remarque de la Direction l'emporte (09/11/2026)

1. **AIB Q1** : aucun texte réglementaire n'existe ; un **formulaire de validation du barème AIB** est créé dans les paramètres (poste et web). Le barème reste « proposition à valider » jusqu'à sa validation par ce formulaire.
2. **Planning Q2** : le **surveillant valide les présences et absences pour tout le personnel et peut valider seul**. Le circuit est paramétrable (surveillant seul, DAF seule, surveillant puis DAF) ; défaut : surveillant seul. La DAF garde son droit d'écran.
3. **Planning Q7** : le **badge sert de pointage**, réglage oui/non dans les paramètres, **défaut oui** ; le badge se relie au registre des présences.
4. **MECeF** : **aucun numéro simulé**. Les paramètres du poste offrent le **choix du mode : boîtier ou e-MECeF**. Le mode e-MECeF s'affiche « non configuré : dossier d'interface DGI requis » tant qu'aucun document n'en décrit le protocole ; aucun code d'intégration n'est écrit à l'aveugle.

## E. Importation de données (Direction, 10/11/2026)

- Chaque écran de référentiel ou de registre qui doit recevoir des données en masse porte un bouton « Importer les données » (fenêtre en trois temps : modèle téléchargeable, vérification sans écriture, import). Écrans cités : Catalogue tarifaire, Transferts gros vers détail, Référentiel produits, « et autres écrans » (inventaire en cours : `docs/prd/PRD-IMP-bouton-importer-par-ecran.md`).
- La rangée « Importation de données » devient VISIBLE aux autres postes, avec un RBAC créé pour l'import (droit distinct par jeu). Cela remplace, pour cette rangée, la décision du 05/11 (onglet Système réservé à l'administrateur et à la DA). Hypothèse à confirmer : seule la rangée IMP est ouverte, le reste de l'onglet Système reste réservé.
- Réponses du 10/11/2026 : Q1 de l'importation = la rangée « Importation de données » seule (le reste de l'onglet Système reste réservé) ; Q5 = le poste du gestionnaire de stock est un FILEUL (un référentiel importé à un fileul passe par la demande d'import vérifiée, appliquée par la mère).

## F. Tarifs : une seule liste, un seul écran, et le changement de prix validé (Direction, 10/11/2026)

- Les deux listes de prix des prestations (« actes », lue par la caisse, et « Catalogue tarifaire (deux prix) ») sont FUSIONNÉES en une seule, que la caisse lit pour facturer. Un seul écran pour tous les prix (principe du TARIF MASTER, vague 26), pour éviter les doublons et le double travail.
- Un import de prix porte un champ de validation Oui/Non : Oui, le nouveau prix s'applique ; Non, il ne s'applique pas. Quand le logiciel constate un changement de prix, il crée une ALERTE DE VALIDATION Oui/Non.
- Le changement d'un prix (produit ou acte) n'influence JAMAIS les anciennes facturations : une pièce émise ne se réécrit pas ; le prix est versionné par date d'effet.
- Q3 des analyses : même principe (un prix unique, lu par la facturation) ; le modèle de résultat (unités, bornes) reste séparé.
- Réponses du 10/11/2026 (PRD tarifs) : Q3 oui, l'auteur valide son propre changement en un geste tracé (Direction, DAF, administrateur) ; Q8 alerte par lot, décision ligne par ligne avec comparaison, « Oui à tout » encadré ; Q9 le caissier perd l'édition des produits ; Q10 le biologiste perd le prix des analyses (il garde le modèle de résultat) ; Q11 DAF : peut-être la mère (à confirmer), Direction : fileul.

## G. Réponses de la Direction du 11/11/2026 (importation, tarifs, organigramme, paie)

**Importation.** I4 : le gestionnaire de stock PEUT importer aussi le prix de vente des prestations (le changement reste soumis à l'alerte de validation de la DAF ou de la Direction). I6 oui (stock détail initial, une seule fois tant qu'aucun mouvement n'existe). I7 : l'assistant comptable est en lecture seule, mais la mise à jour de rôle et la matrice RBAC doivent permettre de lui ouvrir l'import plus tard sans code. I8 oui (ignorer les existants : produits, fournisseurs, emplacements, courriers seulement). I9 oui : groupe sanguin retiré du modèle d'accueil ; **toutes les informations sensibles du patient ne doivent pas être visibles de certains profils du système lors de la consultation** (cloisonnement par champ à concevoir). I10 oui (salaire réservé au profil paie). I11 oui. I12 oui (mesurer puis borner par jeu, réglable en base). I13 oui (comptage d'inventaire).

**Tarifs.** T1 oui (un code canonique, l'autre en alias). T2 oui (valeur facturée aujourd'hui en version 1, grille en proposition Oui/Non analyse par analyse). T4 oui (ligne impayée figée à la prescription). T5 oui (pro-forma : prix du jour à la conversion avec l'écart affiché, durée réglable, 30 jours proposés). T6 : date d'effet passée PERMISE à la DAF et à la Direction avec motif, et une **info-bulle** informe l'utilisateur qui modifie que la DAF a l'habilité de le faire. T7 oui. T11 : la DAF est LA MÈRE, comme l'administrateur (la Direction reste fileul). T12 oui (journée d'hospitalisation au référentiel). T13 : dater les garanties des assureurs, **à faire maintenant**. T14 oui. T15 : « Tarifs et prix ».

**Organigramme.** O1 oui (six intitulés alignés sur la photo). O2 : garder « épse BASSONGUI » ; l'organigramme est modifiable (on peut renommer le titulaire quand une autre personne est affectée au poste) et le PDF paysage suit ces modifications. O3 : le surveillant général est en réalité un infirmier : un agent peut porter un autre titre dans l'organigramme (titre porté par l'agent, pas par le poste). O4 : respecter l'organigramme de la photo, mais il n'est PAS figé : le CRUD de l'organigramme permet de réaffecter. O5 : l'étoile ne veut rien dire, ne pas l'imprimer.

**Paie et espace « Mes ».** P1 oui (la copie de la fiche de paie voyage hors de la liste blanche des paramètres). P2 : aucune durée de conservation. P3 (délai de verrou d'un poste de secours) : recommandation de l'équipe, 5 minutes, réglable en base, marquée « à valider » (le délai ordinaire est de 15 minutes, CDCT 12.2). P4 oui (la garde soins compte comme garde dans « Mes statistiques de garde »).

**Mise en œuvre de la section G (lot ORG2, 11/11/2026).** O1 à O5 : `ECARTS-MAQUETTE.md` E2352 à E2356 (intitulés de la photo, hiérarchie lue avec ses trois hypothèses, CRUD de l'organigramme, titre « SG » porté par l'agent, reprise qui épargne ce que la clinique a modifié, impression paysage sans étoile). P3 : E2357 (délai de 5 minutes en base, « à valider », réglable par l'administrateur et la DAF ; un « poste de secours » est un poste désigné à ce poste même, hypothèse à confirmer). P4 : E2358. Reste à confirmer par la Direction : E2360.

## H. Réponses de la Direction du 11/11/2026 (documents numérisés, courriers, antériorité des résultats)

Sur `docs/prd/PRD-DOCS-numerisation-courriers-dossier-et-antecedents.md` : Q1 à Q10, **recommandations acceptées**, avec ces précisions :

- **Q6 conservation des scans : ILLIMITÉE.** Aucune purge, jamais (cohérent avec RG-14). Le logiciel ne porte pas de durée de conservation pour les courriers ni les documents patient.
- **Q7 OCR : OUI en phase 2**, local, après un essai sur trois vrais scans de la clinique.
- **Q8 recherche par le sens : NON.** On implémente la **recherche avancée** (plein texte sur les métadonnées, filtres, plages de dates, texte des PDF qui portent une couche texte).
- **Q9 seuils de variation brutale : VIDES par défaut.** Le Biologiste médical les saisit. La liste des variables du laboratoire et de l'hospitalisation est établie dans `docs/prd/ANNEXE-DOCS-variables-delta-check-laboratoire-hospitalisation.md` (72 variables numériques du laboratoire ; constantes d'hospitalisation sans alerte).
- **Q10 antériorités affichées : trois, réglable.**
- Q1 (10 Mo, réglable), Q2 (lecteur natif du navigateur), Q3 (visionneuse écrite pour le projet), Q4 (session plus règle par famille), Q5 (nom normalisé `AAAA-MM-JJ_ARR_NNNN.ext`) : acceptées telles que proposées.

### H bis. Compléments du 11/11/2026

- **Chemin local des scans** : la conservation reste illimitée, **et la fiche indique le chemin local du fichier** (celui de ce poste ; « pas encore reçu sur ce poste » quand la copie n'est pas arrivée). PRD documents, EF-DOC-3b.
- **Seuils de variation : bouton Valider.** Chaque seuil passe de **Enregistré** à **Validé** par le bouton Valider ; seul un seuil Validé alerte. Lecture retenue de « Valider qui transforme en Enregistrer ou Validée » : deux états, Enregistré (sans effet) et Validé (en vigueur). À corriger si vous entendiez autre chose. PRD documents, EF-ANT-3b.
- **Droits modifiés, menus à jour automatiquement** : quand l'administrateur modifie les rôles (matrice, modules actifs), le ruban, le méga-menu, les cartes de hub et les accès rapides des sessions ouvertes se mettent à jour d'eux-mêmes (Afficher/Masquer), au pire à la reconnexion. Lot à mesurer puis à faire après le lot des prix : mesurer d'abord ce que fait l'existant (le ruban est construit une fois au chargement de l'écran, `app.js` `buildMenubar`), puis corriger la maquette, puis le poste.

## I. Réponses de la Direction du 11/11/2026 (clôture annuelle)

Sur `docs/prd/PRD-M12-cloture-annuelle-ecarts-et-droits-parametres.md` :

- **Q1 oui** : aucun masquage d'interface par un rôle écrit en dur ; ce qu'un profil voit ou fait vient de la matrice des droits ou d'un réglage en base.
- **Q2** : la clôture définitive est prononcée par **la Directrice Administrative, la Direction, l'administrateur ou le comptable** (défaut du circuit réglable). Hypothèse conservée et signalée : la personne qui a démarré la clôture ne la prononce pas elle-même.
- **Q3** : **pas de format DGI.** Format proposé et nommé SIGH-ARC version 1 (`docs/specs/SPEC-archive-cloture-exercice.md`), archive actuelle conservée : CSV des écritures, balance, états à imprimer en PDF, manifeste SHA-256. Conservation illimitée.

## J. Demandes de la Direction du 11/11/2026 (écrans d'accès)

- **Pastille du haut** : retirée de « Session verrouillée » et des pages 403 et 404 (même gabarit) ; « Mot de passe oublié » et « Réinitialisation » gardent la leur. `ECARTS-MAQUETTE.md` E2371.
- **Plan du site réglable** : case « Afficher le plan du site » à « Paramètres », onglet « Installation et données », carte « Affichage », décochée par défaut, en base, journalisée à chaque changement ; décochée, les boutons du plan (403, 404, Paramètres) disparaissent et son adresse mène à la page 404. Maquette et poste. E2372.
- **Repli** : un profil sans écran dans son ruban tombe sur la page 404, plus sur le plan du site. E2373.

**Mise en œuvre de la section G (lot T3 des tarifs, 11/11/2026).** T4 mesuré (ligne impayée figée), T5 : moteur et écran de l'écart, durée réglable en base (30 jours, à valider), pas de geste de conversion à la maquette ; T6 : date passée pour la DAF et la Direction, case, motif, info-bulle ; T7 : lecture à confirmer (E2375) ; T11 : décisions à la mère. `ECARTS-MAQUETTE.md` E2374 à E2379.

## K. Validations de la Direction du 11/11/2026 (tarifs au poste, lancement du lot import)

- **Pro forma** : validité de 30 jours par défaut, réglable (réglage en base). Validé.
- **« Oui à tout »** : seuil de variation vide par défaut. Validé.
- **Grille imprimée des analyses** : les 39 prix restent des PROPOSITIONS tant que la Direction n'a pas tranché Oui ou Non (dont le VIH à 3500 / 2500, jamais facturé). Validé tel quel, modifiable à tout moment par le circuit.
- **Lot import lancé** : `docs/prd/PRD-IMP-bouton-importer-par-ecran.md` avec les réponses de la section G (I4 à I13) et les remplacements de `docs/prd/PRD-TARIFS-referentiel-unique-et-changement-de-prix.md` section 7 (jeu unique `tarifs`, lots T4 et T5). Ordre : maquette (socle et jeux existants, puis stock et autres référentiels), puis poste Flutter, puis demande d'import fileul vers mère.
- **Archivage d'un poste de l'organigramme qui porte des sous-postes** : on RÉAFFECTE les sous-postes (avec confirmation, journal et annulation) au lieu de refuser. Remplace le refus `POSTE_PORTE_DES_POSTES`. Maquette d'abord, puis domaine et poste. **Mise en œuvre (lot ORG3, 11/11/2026)** : maquette, domaine et poste faits, cible par défaut le parent, sommet exigeant une cible, annulation, journal 1 + N, tout ou rien ; cinq hypothèses à confirmer (`ECARTS-MAQUETTE.md` E2426), preuves et limites E2427.
- **Quatre écrans de la maquette non portés au poste** (calendrier fiscal, journal SMS, barème de l'AIB, passerelle SMS) : on les MASQUE au poste, par une fermeture d'activité en base (réversible depuis la gestion des activités), jamais par un nom de rôle en dur. Ils se portent plus tard, chacun à son tour, et la fermeture tombe à ce moment. **Mise en œuvre au poste (11/11/2026)** : quatre fiches `MODP01` à `MODP04` dans le jeu livré du poste seulement (la maquette ne change pas), motif écrit et daté, aucun nom de rôle ; la réouverture n'est pas proposée tant que l'écran n'a pas de widget (`ECARTS-MAQUETTE.md` E2422 à E2425).
- **Produits dans « Tarifs et prix » : option B** (PRD-TARIFS 4.7). L'onglet Produits est en LECTURE SEULE : code, désignation, prix d'achat en vigueur versionné par date, prix de vente dérivé (RG-02, jamais de marge sur un médicament), date d'effet, version. La modification se fait à l'écran des produits (M6) et par l'import `tarifs-produits`. **Chaque ligne de produit porte un bouton « Historique de prix »** qui ouvre la modale « Historique de prix » du produit (versions, dates d'effet, auteurs, statuts), sur l'onglet Produits et sur l'écran des produits. Lot T5, après IMP-B1 (un seul agent écrit dans la maquette).
- **Mise en œuvre du lot IMP-B1 (11/11/2026, maquette)** : les cinq jeux du stock sont posés (référentiel produits, emplacements, stock détail initial une seule fois, bon de transfert par la même fabrique que le geste, comptage d'inventaire dont la régularisation reste un geste humain) ; `ECARTS-MAQUETTE.md` E2428 à E2435. À confirmer : la Direction n'a pas la lecture de ces cinq jeux (consigne du lot, PRD 7.2 la lui donnait) ; un prix d'achat absent crée l'article à 0 « à valoriser » (la caisse le facturerait à 0 : refuser plutôt ?) ; un lot précisé à l'import de transfert qui n'est pas le premier à sortir est refusé.
- **Mise en œuvre du lot T5 (12/11/2026, maquette)** : option B appliquée (onglet Produits en lecture seule, « Historique de prix » sur chaque ligne de l'onglet et de « Référentiel produits », prix d'achat versionné par le même moteur, prix de vente dérivé, jeu `tarifs-produits`, RG-02 tenu à l'écriture). Réponse au point d'IMP-B1 : un prix d'achat absent crée l'article « à valoriser » SANS prix facturable (jamais à zéro : la prescription, la caisse et la pharmacie refusent en le nommant), plutôt que de refuser la ligne. À confirmer : ce choix (refuser plutôt, pour le seul jeu du référentiel produits ?), la version 1 d'une création validée d'emblée et sans date d'effet, une réception d'achat à un prix différent qui ne propose aucun changement, la Direction sans lecture du jeu des prix d'achat. `ECARTS-MAQUETTE.md` E2436 à E2447.
- **Décisions de la Direction du 12/11/2026 (lot T5b, maquette et libellés du poste)** :
  1. **Plus aucun « SAGE » visible.** Tous les libellés visibles (écrans, onglets, modales, aides, messages, états imprimés de la reprise, rapports et modèles d'import, fiches semées) disent « Inventaire initial (reprise) » ; la source documentaire reste citée par le nom de son document. Les identifiants techniques (`INVENTAIRE_SAGE`, `valorisationsSage`, `IMPORT-SAGE-20260715`, `SAGE_100_GESTION_COMMERCIALE_15.01`, noms de fichiers et de collections) ne changent pas : aucune donnée ne migre, ce qui se LIT les traduit.
  2. **Prix d'achat absent, deux cas séparés.** (a) L'import `produits-referentiel` REFUSE une ligne sans prix d'achat (vide, tiret, zéro, NC) en nommant l'article, tout ou rien ; la création manuelle (`m6-produits`, et « Nouvel article » des achats par cohérence) l'exige aussi. (b) La reprise du Grand Stock GARDE « à valoriser » (le stock existe déjà, RG-03) : jamais facturable, liste « Produits à valoriser » avec son compte et sa raison, alerte à la DAF par le moteur d'alertes existant (qui disparaît quand la liste est vide), premier prix par une proposition ordinaire (Oui ou Non).
  3. **Écriture en lot de l'import** : un lot s'écrit en UN envoi par collection touchée au lieu d'une requête par fiche, sans rien perdre (journal RG-12, projection relationnelle, événements entre postes, tout ou rien, annulation).
  4. **Réception d'achat à un autre prix** : le CUMP bouge comme avant et une PROPOSITION de changement du prix d'achat s'ouvre (date d'effet = date de réception, motif « prix constaté à la réception n° … »), jamais bloquante, une seule par produit ; aucun prix ne change avant le Oui (RG-02).
  5. **`cfb.json`** : le générateur est réparé à la racine.
- **Mise en œuvre du lot T5b (12/11/2026)** : les cinq décisions ci-dessus, maquette (Vagues 137 à 140) et libellés du poste ; `ECARTS-MAQUETTE.md` E2448 à E2455. À confirmer : le prix de réception est celui de la ligne de commande réceptionnée (la modale de réception ne le ressaisit pas) ; une date de réception antérieure à aujourd'hui n'ouvre la proposition que pour la DAF et la Direction (sinon la réception le dit, sans rien bloquer) ; le zéro est refusé comme l'absence au référentiel produits ; la liste « à valoriser » garde un article tant qu'un Oui n'a pas mis un prix en vigueur (une proposition en attente ne l'en sort pas) ; l'alerte va à la famille qui décide des prix.
- **Mise en œuvre du lot IMP-B2 (12/11/2026, maquette)** : les dix autres référentiels sont posés (natures de facture, centres de coûts, catalogue de l'imagerie, unités de mesure, prestataires, garanties datées, couvertures d'assurance, immobilisations, budgets, courriers) ; `ECARTS-MAQUETTE.md` E2456 à E2469, Vagues 141 à 151. Matrice d'origine : administrateur et DAF `VIA`, Direction `V`, comptable `VIA` sur ses cinq jeux, assistant comptable `V` sans `I`, biologiste `VIA` sur les unités, agent administratif `VIA` sur les courriers. **À confirmer** : (1) la Direction `V` sur les dix, alors que les jeux du stock et des prix d'achat ne lui donnent rien ; (2) le secteur des natures de facture est celui de l'écran (huit secteurs d'activité), non les six secteurs de recette ; (3) la clé des garanties ajoute le libellé de la garantie à (souscripteur, catégorie, date d'effet) et le plafond est facultatif ; (4) un examen d'imagerie ou une unité importés naissent « à valider » même par la famille qui valide ; (5) la prescription applique le taux plat du dossier et ne lit pas la grille de garanties (constat, non corrigé).

## L. Lot IMP-C (12/11/2026, poste) : ce qui reste à trancher par la Direction

- **Famille de la demande d'import** : la consigne disait la famille B (ajout seul) ; la demande est une fiche que le fileul dépose et que la mère complète du verdict. Elle suit le précédent des propositions de prix (famille A de la synchronisation, champ à champ). Recommandation : garder. Alternative : deux collections en ajout seul. ☐ Garder la famille A ☐ Deux collections en ajout seul.
- **Pages de jeux non portées, fermées au poste** : douze jeux d'import ne sont pas portés au poste (voir `ECARTS-MAQUETTE.md` E2477) ; leur page est fermée pour tous les rôles par une fermeture d'activité propre au poste, jusqu'à leur portage. Recommandation : accepter, porter les jeux dans l'ordre stock, prix, garanties et couvertures, comptabilité. ☐ Accepter ☐ Autre ordre.
- **Jeux de stock au poste d'un fileul** : le Grand Stock (déjà porté) écrit `produits`, collection de configuration que la mère seule écrit : sur un fileul rattaché il passe désormais par une demande d'import (la mère rejoue et écrit produits, lots, mouvements). Le stock détail initial et le bon de transfert (non portés) écrivent aussi `produits` : demande, ou écriture en PART du stock par variations (E2149) ? Recommandation : le stock en PART, la demande pour les référentiels sans quantité (produits, emplacements, prix). ☐ Demande ☐ PART et variations.
- **Lignes du fichier dans la demande** : elles voyagent en clair dans le magasin du fileul et de la mère jusqu'au verdict, puis sont effacées ; le journal vers le relais est chiffré de bout en bout. Acceptable pour des référentiels de configuration non sensibles. Un jeu restreint ne passe JAMAIS par une demande (le personnel, de configuration et restreint, ne s'importe qu'au poste de la mère) : appliqué par le code, à confirmer. ☐ Accepter.
- **Accueil du module** : il liste aussi les jeux non portés pour qui les voit (« Non porté au poste »), pour garder la page à parité avec la maquette. ☐ Accepter ☐ Les masquer.
- **Réglage des droits d'import par jeu au poste** : le poste lit la matrice et les fiches RBAC, il ne sait pas encore les écrire (section Importation de « Rôles & permissions »). Recommandation : lot suivant. ☐ Lot suivant.

## M. Lot DOCS-1 (12/11/2026, maquette) : documents numérisés, ce qui reste à trancher par la Direction

Mise en œuvre des réponses Q1 à Q10 (section H) pour les courriers M13 et le dossier patient M1 : `ECARTS-MAQUETTE.md` E2481 à E2491, plan `docs/plans/PLAN-documents-numerises.md`.

- **Droit de dépôt** : le droit d'import par jeu (IMP-A) est celui d'un FICHIER TABLEUR de lignes ; déposer un scan sur une fiche est un autre geste. Il suit le droit de l'écran (éditer pour déposer et remplacer, annuler pour retirer). Recommandation : garder. ☐ Garder ☐ Un droit « déposer » distinct, réglable par rôle.
- **Zones du dossier patient** : seules la pièce d'identité et la carte d'assurance sont administratives (zone 1, lisibles de tout profil qui ouvre l'écran) ; les huit autres types (dont la facture, par prudence) sont médicaux (zone 2, profils cliniques : administrateur, directeur médical, médecin, infirmier, chirurgien, anesthésiste). Conséquence à connaître : la DAF et la Direction, qui ouvrent l'écran, ne lisent plus que la zone 1 (RG-13, PRD section 3). ☐ Accepter ☐ Autre classement.
- **Un fichier par fiche, avec remplacement** : le PRD parle d'un champ `fichier` ; le doublon « même fiche » se voit donc au remplacement (le même fichier est refusé en nommant la pièce, un autre fichier remplace et l'ancien est retiré à l'historique). Alternative : plusieurs pièces jointes par fiche. ☐ Garder ☐ Plusieurs pièces.
- **`numerise` dérivé** : les 25 courriers du jeu qui se disaient « numérisés » sans aucun fichier redeviennent « À scanner ». ☐ Accepter.
- **Taille maximale** : 10 Mo reste « à valider » ; réglable par l'administrateur et la DAF (hypothèse, à confirmer), entre 100 Ko et 64 Mo.
- **Chemin local** : dans la maquette, c'est le chemin sur le serveur du poste (le serveur PHP tourne sur la machine du poste). Un bouton « Ouvrir le dossier » n'existe pas dans un navigateur : absent. ☐ Accepter.
- **Sauvegarde des fichiers** : FAITE par le lot SAUV-F (12/11/2026), voir la section O. La sauvegarde nocturne ne copiait que le magasin JSON ; une tâche à part copie maintenant le dossier de fichiers, et une restauration le relit.
- **Pièces produites, dans la vue unifiée** : ordonnances, résultats rendus (selon le droit de lire un résultat), comptes rendus opératoires et comptes rendus d'imagerie rendus. Les comptes rendus de maternité et les fiches de consultation n'y sont pas : à confirmer. ☐ Accepter ☐ Les ajouter.

## N. Décision de la Direction du 12/11/2026 : un fileul importe directement dans son propre magasin

Phrase reçue : « un fileul peut importer donc directement dans son propre magasin ». Elle REMPLACE la réponse précédente (le fileul qui importe de la configuration passe par une demande que la mère applique, lot IMP-C). Point non tranché : un référentiel de la famille R est écrit par la mère seule, et le fileul refuse aujourd'hui toute écriture de référentiel (`FILEUL_LECTURE_SEULE`). Trois façons de l'appliquer : (a) écriture locale seule, jamais propagée ; (b) exception à la règle de synchronisation, la mère accepte ces écritures du fileul pour les jeux concernés ; (c) écriture directe chez le fileul ET demande automatique à la mère. Recommandation : (c). Lot IMP-D, après DOCS-1, une fois l'option choisie. **Choisi par la Direction le 12/11/2026 : (c)**, écriture directe chez le fileul ET demande automatique à la mère (la mère reste l'autorité de la configuration). Lot IMP-D ouvert après le lot de sauvegarde des fichiers (SAUV-F). **APPLIQUÉE le 12/11/2026 (lot IMP-D, poste)** : un fileul rattaché écrit chez lui par le même chemin que la mère ET une demande part automatiquement ; la mère reste l'autorité (qui gagne, restitution, injoignable : `ECARTS-MAQUETTE.md` E2500 à E2508). Ce qui reste à confirmer est à la section P.

## O. Lot SAUV-F (12/11/2026, maquette) : sauvegarde, restauration et contrôle des fichiers numérisés

Mise en œuvre du constat E2491 (le dossier `api/fichiers/` n'était pas sauvegardé) : `ECARTS-MAQUETTE.md` E2492 à E2499, plan `docs/plans/PLAN-documents-numerises.md` (lot SAUV-F), guide `docs/guides/GUIDE-DEMARRAGE.md` sections 7 et 8.4. Ce qui reste à trancher :

- **Désigner un AUTRE disque avant la mise en service.** Par défaut la destination est `api/sauvegardes/`, sur le MÊME disque que les données : une panne de disque emporte les scans ET leur copie (c'est aussi vrai de la copie du magasin, qui existait déjà). L'écran « Tâches planifiées » et une alerte à l'administrateur et à la DAF le disent tant que c'est le cas. Le geste est fait (« Destination de la sauvegarde »), mais le CHOIX du support est à la Direction : un disque externe, un partage réseau, un autre poste. Support retenu : ________.
- **Une seule destination pour le magasin et pour les fichiers** (hypothèse) : le réglage s'applique aux copies du magasin (7 derniers jours) et aux fichiers numérisés. ☐ Garder ☐ Deux réglages séparés.
- **Fréquence** (proposition) : copie des fichiers toutes les heures (incrémentale, peu coûteuse tant que rien ne change), contrôle d'intégrité chaque nuit. ☐ Accepter ☐ Autre fréquence : ________.
- **Conservation** : les fichiers ne tournent jamais (réponse de la Direction, section H). Le magasin garde 7 jours (inchangé). Les manifestes datés (`fichiers-AAAA-MM-JJ.json.gz`) sont conservés sans limite (proposition, un par jour, quelques Ko à quelques centaines de Ko). ☐ Garder ☐ Une conservation plus longue du magasin : ________ jours.
- **Copie hors site** : non faite. La destination est un dossier ; une copie hors site (service en ligne, disque emporté) est une décision à part. ☐ À prévoir.
- **Support de sauvegarde non chiffré** : les scans (données de santé) sont copiés tels quels, comme sur le disque source. Si le support quitte la clinique, il doit être chiffré par le système (BitLocker, LUKS) : ce n'est pas fait par l'application. ☐ Chiffrement du support à prévoir.
- **Orphelins** : un fichier déposé dont la fiche n'a jamais été enregistrée est SIGNALÉ (alerte en information), jamais supprimé (RG-14). ☐ Garder ainsi ☐ Prévoir un geste d'archivage explicite.
- **Qui règle la destination** : l'administrateur et la DAF, comme la taille maximale des fichiers. Le serveur vérifie le chemin et la tâche le revérifie à chaque passage, mais il ne peut pas empêcher un autre profil d'écrire le réglage par le magasin tant que la matrice des droits n'est pas portée en PHP (même limite que `documentsBornes`).

## P. Lot IMP-D (12/11/2026, poste) : le fileul importe directement chez lui, ce qui reste à trancher par la Direction

Mise en œuvre de la décision de la section N (option (c)) : `ECARTS-MAQUETTE.md` E2500 à E2508, plan `docs/plans/PLAN-importation-bouton-par-ecran.md` (lot IMP-D). La mère reste l'autorité de la configuration et gagne en cas de conflit (appliqué, pas rouvert). Hypothèses écrites plutôt qu'inventées :

- **Grand Stock : DÉCIDÉ le 13/11/2026 (écriture directe chez le fileul, avec idempotence).** La Direction a répondu : « l'argument du double comptage n'est pas prouvé », il fallait le mesurer. Il est prouvé (300 unités en lot pour 150 importées, E2520), puis levé (E2521 à E2531) : le Grand Stock s'écrit chez le gestionnaire de stock ET une demande part à la mère. Remplace l'hypothèse « par demande seule » écrite au lot IMP-D. Ce qui reste à confirmer est à la section R.
- **Même résultat ou refus** : la mère ne confirme que si elle écrit EXACTEMENT les mêmes lignes que le fileul ; sinon elle refuse en nommant les lignes (`RESULTAT_DIFFERENT`) et le fileul restitue puis refait son import à jour. Alternative : la mère applique le sous-ensemble et le fileul apparie ses fiches par clé naturelle (une clé par jeu à exposer). Recommandation : garder (aucune fiche doublée sans que quelqu'un l'ait vu). ☐ Garder ☐ Sous-ensemble apparié.
- **Pièce émise entre-temps** : une fiche qu'un acte émis utilise déjà n'est pas archivée quand la mère refuse ; elle reste, marquée « Refusée par la mère » avec le motif, et la demande dit « restitution partielle ». Tant que l'agent n'a pas régularisé, le fileul peut porter deux fiches actives d'un même code (la sienne et celle de la mère). Recommandation : garder (une pièce émise ne se réécrit jamais). Alternative : refuser l'import tant qu'un acte émis pourrait s'appuyer sur la fiche (impossible à savoir avant le refus). ☐ Garder ☐ Autre règle.
- **Annulation du lot chez le fileul** : permise tant que la mère n'a pas statué (la demande est alors retirée), refusée après sa confirmation (la mère détient les mêmes fiches, elle annule à son poste). ☐ Accepter ☐ Autoriser l'annulation chez le fileul aussi après confirmation.
- **Jeu restreint de configuration** (le personnel) : il reste réservé au poste de la mère, ses lignes ne voyagent pas dans une demande (RG-13). La décision de la section N ne le couvre pas explicitement. ☐ Garder ☐ Étendre au personnel (les salaires voyageraient dans la demande).
- **Lignes du fichier dans la demande** : elles voyagent en clair dans la demande jusqu'au verdict, à tous les fileuls et à la mère (constat plus large qu'il n'était écrit en section L). Acceptable pour des référentiels de configuration non sensibles. ☐ Accepter.


## Q. Lots A1 et A2 (13/11/2026, maquette) : antériorités du laboratoire et seuils de variation brutale, ce qui reste à trancher

Mise en œuvre des lots A1 et A2 du plan `docs/plans/PLAN-documents-numerises.md` (EF-ANT-1 à 6, EF-ANT-3b) : `ECARTS-MAQUETTE.md` E2510 à E2519. Les décisions du 11/11/2026 sont appliquées telles quelles (seuils vides par défaut, bouton Valider, deux états Enregistré et Validé). Hypothèses écrites plutôt qu'inventées :

- **Forme d'un seuil.** Une variable numérique porte une variation ABSOLUE (dans l'unité de la variable) et/ou une variation RELATIVE (en pourcentage) ; l'alerte part dès que l'une des deux est atteinte (« au moins »). Aucune valeur n'est proposée : c'est au Biologiste médical de les poser, variable par variable (72 variables numériques, liste à l'écran « Valeurs de référence »). ☐ Garder ☐ Un seul mode par variable ☐ Autre : ________.
- **Qui valide un seuil.** Le Biologiste médical seul (la liste de rôles de la famille « Variables et unités du laboratoire »). Le technicien de laboratoire qui valide un résultat par intérim ne valide PAS un seuil. ☐ Garder ☐ Ajouter le technicien de laboratoire.
- **À quelle date une mesure se juge.** Au seuil validé en vigueur à la date de sa validation biologique (à aujourd'hui tant qu'elle n'est pas validée). Une date d'effet ne peut pas être passée : un seuil ne s'applique jamais en arrière. Granularité du jour : une mesure validée le jour même où un nouveau seuil entre en vigueur se juge à ce nouveau seuil. ☐ Garder ☐ Juger à la date de la demande.
- **Aucune fenêtre de temps entre deux mesures.** Une variation sur six mois est signalée comme une variation sur deux jours. Une pratique de delta check borne souvent l'intervalle ; aucun document ne la fixe. ☐ Garder ☐ Prévoir un délai maximal, réglable par variable.
- **Seuil relatif et valeur précédente nulle.** Le pourcentage ne se calcule pas sur une valeur précédente nulle : le seuil relatif n'est alors pas évalué (le comparatif le dit), seul le seuil absolu l'est. ☐ Garder.
- **L'alerte se voit du médecin au comparatif.** Le comparatif est ouvert au médecin (comme l'écran l'était) et porte l'alerte, ce que demandait le PRD ; elle n'apparaît ni sur le résultat qu'il lit, ni dans une notification. ☐ Garder ☐ Réserver l'alerte aux profils du laboratoire.
- **Les seuils ne sont pas au centre « Validations en attente ».** Ils ont leur propre geste (Enregistré puis Validé, motif obligatoire) à l'écran « Valeurs de référence » et ne comptent pas parmi les familles du centre des validations. ☐ Garder ☐ Les y ajouter.
- **Comparatif : trois antériorités, ordre de la date de la demande, une seule antériorité sur la fiche imprimée.** ☐ Garder ☐ Autre : ________.
- **Constantes d'hospitalisation.** Aucune courbe : la diurèse (litres à l'accueil, millilitres à l'hospitalisation) et la tension (texte « 12/8 ») ne se comparent pas sans conversion ni scission (E2513). ☐ Corriger à la source ☐ Convertir à l'affichage.


## R. Lot IMP-E (13/11/2026, poste) : le Grand Stock s'écrit chez le gestionnaire de stock, ce qui reste à trancher par la Direction

Mise en œuvre de la décision du 13/11/2026 (« le Grand Stock s'écrit directement chez le fileul ; l'argument du double comptage n'est pas prouvé : le mesurer, puis mettre en place l'idempotence ») : `ECARTS-MAQUETTE.md` E2520 à E2531, plan `docs/plans/PLAN-importation-bouton-par-ecran.md` (lot IMP-E). La mère reste l'autorité (appliqué, pas rouvert). Hypothèses écrites plutôt qu'inventées :

- **Un stock en attente n'est vu que du poste qui l'a écrit.** Tant que la mère n'a pas confirmé, les articles, lots et entrées du fileul ne partent PAS au journal (ni vers la mère, ni vers un autre fileul, ni vers un téléphone) et le fileul peut en sortir sans la règle de la part (E2149) : aucun autre poste ne le voit. Alternative : publier tout de suite et laisser la mère corriger, ce qui exposerait à tous un stock qu'elle peut refuser (deux fileuls qui importent le même inventaire le feraient voir en double le temps du verdict). Recommandation : garder. ☐ Garder ☐ Publier tout de suite.
- **Une sortie déjà faite sur un lot en attente, puis refus de la mère.** L'article (article, lots, entrées) ne se restitue pas : une pièce émise ne se réécrit jamais. Il reste chez le fileul seul, marqué « Refusée par la mère », la demande dit « restitution partielle » ; les autres articles du même fichier sont restitués (mouvements inverses nommés, archivage). La sortie, faite sur un stock que la mère n'a jamais tenu, ne lui est pas envoyée. Conséquence assumée : tant que l'agent n'a pas régularisé, le fileul porte DEUX articles actifs de même code (le sien, marqué, et celui de la mère). ☐ Garder ☐ Autre règle (par exemple demander à la mère d'adopter l'article et sa sortie).
- **Restitution par mouvements inverses, pas par suppression.** Chaque entrée écrite est contre-passée par une sortie nommée (« Restitution du lot IMP-… : refusé par la mère »), l'entrée d'origine reste à l'historique du fileul, les lots et les articles sont archivés (RG-14). Les mouvements d'entrée et inverses restent propres au poste. ☐ Garder.
- **Mouvement de sortie sur un article en attente.** Un mouvement qui s'appuie sur un article propre au poste n'est pas publié non plus (sinon la mère recevrait une sortie d'un article qu'elle ne tient pas, sans retour possible si elle refuse). Il part dès que la mère a confirmé l'article. ☐ Garder.
- **Aucun lot ni mouvement d'un fileul vers un téléphone avant la confirmation de la mère** (RG-13) : vérifié. Après confirmation, les lots et mouvements de la mère vont aux téléphones selon leurs règles actuelles (non changées). ☐ Garder.
- **Un compteur ne se remplace jamais par la valeur d'un autre poste** (correctif trouvé par la mesure, E2522) : le stock d'un produit, que la configuration de la mère publie encore comme une valeur pour les téléphones, n'est plus adopté par un fileul ; il bouge par ses variations. ☐ Garder.
- **Le fileul peut sortir du stock d'un produit** (correctif E2523) : la garde « réglé sur la mère » couvrait toute la fiche `produits`, donc aucune dispensation, perte ou inventaire d'un fileul n'était possible. Les modifications qui ne touchent QUE les compteurs de stock passent désormais (elles voyagent par variations) ; le reste de la fiche reste réglé sur la mère. ☐ Garder.
- **Deux fileuls, même inventaire** : *(remplacé le 13/11/2026 par les sections V et W : le même inventaire est adopté, un fichier dont une cellule change reste refusé `DOUBLON_MAGASIN`)* le second est refusé en nommant (`DOUBLON_MAGASIN`) et restitue. Un fichier déjà importé par la mère ou un autre fileul se voit donc refusé après coup, pas avant : le fileul le découvre à la réponse de la mère. ☐ Garder ☐ Vérifier le doublon à la mère avant d'écrire chez le fileul (impossible hors ligne).
- **Annulation du lot chez le fileul** : inchangée (permise tant que la mère n'a pas statué, refusée après sa confirmation) ; pour le Grand Stock elle est refusée dès qu'un autre mouvement s'appuie sur l'un des articles (`MOUVEMENT_POSTERIEUR`). ☐ Garder.



## S. Lot D5 (13/11/2026, poste) : les fichiers numérisés au poste Flutter, ce qui reste à trancher par la Direction

Mise en œuvre du poste pour les documents numérisés de DOCS-1 : `ECARTS-MAQUETTE.md` E2532 à E2543, plan `docs/plans/PLAN-documents-numerises.md` (lot D5). Ce qui reste à trancher :

- **Chiffrement au repos des fichiers** (hypothèse retenue) : les scans sont chiffrés par la MÊME clé que le magasin du poste (AES-256-GCM), donc une seule clé à sauvegarder. ☐ Garder ☐ Une clé distincte pour les fichiers (deux clés à sauvegarder, une fuite de l'une ne livre pas l'autre).
- **Les fichiers ne passent pas par le relais en ligne** (hypothèse retenue : le relais reste opaque, il ne détient que le journal chiffré). Un fileul qui ne joint pas la mère voit les pièces des autres postes « non disponible hors ligne ». ☐ Garder (les fichiers restent dans le réseau de la clinique) ☐ Prévoir un transfert de morceaux chiffrés par le relais (protocole à part, taille et coût d'hébergement à fixer).
- **Le lecteur de PDF** : celui livré ouvre le PDF vérifié dans l'application PDF du système, à partir d'une copie temporaire en clair (supprimée au mieux après dix minutes). ☐ Garder ☐ Un rendu intégré au logiciel (paquet natif à éprouver sous Windows, aucune copie en clair).
- **Le rôle qui décide du droit de zone est déclaré par le poste** : la mère authentifie l'appareil, non la personne (comme pour le journal). ☐ Accepter la limite ☐ Authentifier la personne auprès de la mère (jeton de session).
- **Sauvegarde des fichiers du poste** : une passe par heure, copie incrémentale vérifiée, conservation illimitée, destination propre au poste réglée par l'administrateur et la DAF. ☐ Accepter la fréquence ☐ Autre : ________. **Désigner un AUTRE disque** avant la mise en service (le poste le dit tant que la destination est dans le dossier des données, et ne sait pas le dire autrement). ☐ Alerte au centre de notifications quand la destination disparaît (aujourd'hui : carte et journal seulement). ☐ Copie hors site à prévoir. ☐ Support de sauvegarde sorti de la clinique : la copie est chiffrée par la clé du poste, qui doit être sauvegardée à part (export existant).
- **La taille maximale d'un fichier** reste à 10 Mo « à valider » (section M), réglage propre à chaque poste.
- **Le poste mère et son service partagent le dossier des fichiers** (même dossier, même clé) : un scan déposé à la mère est aussitôt chez elle, sans transfert. ☐ Garder.

- Vérification : voir E2539 et E2540 (vingt-six mutations rouges, répétitions, avant/après).


## T. Lot OCR-prep (13/11/2026, maquette et poste) : la lecture OCR des scans, PRÉPARÉE, ce qui reste à trancher par la Direction

Suite de la décision Q7 (« OCR : OUI en phase 2, local, APRÈS un essai sur trois vrais scans »). Ce lot a préparé tout ce qui ne dépend pas du moteur ; **aucun moteur n'est choisi, installé ni embarqué, aucune qualité d'OCR n'a été mesurée**. Écarts : `ECARTS-MAQUETTE.md` E2544 à E2556, guide : `docs/guides/GUIDE-mesure-ocr.md`. Ce qui reste à trancher :

- **Le moteur** : à choisir par la Direction APRÈS l'essai sur trois vrais scans de la clinique (candidats réalistes cités à E2551, tous « à mesurer »). ☐ Un moteur local installé avec le poste ☐ Un exécutable embarqué ☐ Une bibliothèque Dart ☐ Autre : ________. Les PDF scannés exigent en plus un rendeur de pages (pages de PDF en images) : à choisir avec le moteur.
- **Activation par défaut** (hypothèse retenue : DÉSACTIVÉE tant qu'aucun moteur n'est choisi, puis activée à la main par l'administrateur ou la DAF) : ☐ Garder (activation explicite) ☐ Activer d'office quand un moteur est installé.
- **Correction manuelle du texte reconnu** : PAS faite dans ce lot. Aujourd'hui le texte lu par machine est toujours marqué « à vérifier » et ne se corrige pas ; une relance ou un autre moteur AJOUTE une version datée. ☐ Pas de correction (le scan est la référence) ☐ Une correction par un agent habilité, qui s'ajoute comme une version signée (la lecture machine reste lisible).
- **Durée de conservation du texte lu** (hypothèse retenue : conservation illimitée de toutes les versions, comme les fichiers, RG-14) : ☐ Garder ☐ Limiter les anciennes versions à : ________ (le texte reste une métadonnée peu volumineuse ; une durée courte ferait perdre ce que l'agent a pu lire).
- **Qui peut relancer la lecture** (hypothèse retenue : qui peut ÉCRIRE sur l'écran de la pièce, la zone du type de document en plus pour le dossier patient) : ☐ Garder ☐ Réserver à l'administrateur et à la DAF.
- **Le réglage est propre à chaque poste** (le moteur s'installe sur un poste, pas sur la clinique) : ☐ Garder ☐ Un réglage de clinique qui voyage avec la configuration de la mère.
- **Le texte lu d'un scan de zone 2** (compte rendu, ordonnance) voyage par le journal vers TOUS les fileuls, comme la fiche qui le porte ; seul l'AFFICHAGE est de zone (un poste dont l'agent ne lit pas la zone n'en lit rien, et ne reçoit pas le binaire). ☐ Accepter la limite (même niveau que la fiche) ☐ Filtrer côté mère par rôle (la mère ne connaît pas la personne, E2542 de la section S).
- **Les scans d'essai** : un dossier PROPRE AU POSTE, hors du dépôt, jamais versionné (`GUIDE-mesure-ocr.md`), avec une transcription recopiée à la main à côté de chaque scan. ☐ Garder ☐ Autre emplacement : ________. Le rapport de mesure ne cite par défaut AUCUN mot des documents. ☐ Trois scans suffisent pour décider ☐ Plus de trois (la décision Q7 dit trois : un échantillon de cette taille indique, il ne démontre pas).
- **La charge d'un poste de clinique** pendant une lecture (UNE lecture à la fois, bornée à 120 s par page, hors de la saisie) : à relever sur un poste réel avec le moteur choisi ; le délai de 120 s est une valeur d'attente « à valider ».

## U. Lot RLS-SYNC (13/11/2026, relais et mère) : l'écran « Synchronisation » du panneau, ce qui reste à trancher par la Direction

Les trois décisions de la Direction du 13/11/2026 sont appliquées (compteurs et horodatages seulement, superadmin seul, historique de trois mois réglable). Les valeurs ci-dessous sont des **propositions « à valider »** : elles sont enregistrées en base, bornées et modifiables aux paramètres du panneau, donc aucune n'est figée par le code. Écarts : `ECARTS-MAQUETTE.md` E2557 à E2564, PRD : `docs/prd/PRD-RELAIS-synchronisation-fileuls-mere-mobiles.md`.

- **Durée de conservation de l'historique** (90 jours retenus, bornes 30 et 365) : ☐ Garder ☐ Autre : ________ jours. Le plancher de 30 jours empêche de vider l'historique par une saisie ; le plafond de 365 jours borne la taille de la table (un relevé toutes les 10 minutes par appareil).
- **Intervalle entre deux relevés** (10 minutes retenues, bornes 1 et 60) : ☐ Garder ☐ Autre : ________ min.
- **Délai « en retard » et « silencieux » du fileul** (30 minutes puis 240 minutes, ou plus de 500 opérations de retard de journal : ce sont les seuils que la console de la mère emploie déjà pour ses propres contrôles) : ☐ Garder ☐ Autres : ________ min, ________ min, ________ opérations.
- **Délai « en retard » et « silencieuse » de la mère** (2 minutes puis 5 minutes ; l'alerte de battement existante garde son seuil de 5 minutes dans le fichier d'environnement) : ☐ Garder ☐ Autres : ________ min. Les deux seuils de silence de la mère sont deux réglages distincts (l'un en base, l'autre dans le fichier d'environnement) : ☐ Accepter ☐ Faire lire à l'alerte de battement le réglage en base.
- **Délai « en retard » et « silencieux » d'un mobile** (12 heures puis 48 heures) : un téléphone ne dépose que lorsqu'on s'en sert, un week-end sans consultation n'est pas une panne. ☐ Garder ☐ Autres : ________ min, ________ min.
- **Boîte qui grossit** (200 enveloppes non relevées) : ☐ Garder ☐ Autre : ________.
- **Publication des fileuls par la mère** : le relais ne les voit pas, c'est la mère qui publie leur état dans ses indicateurs de battement. ☐ Accepter ☐ Ne rien publier d'eux (l'écran ne montrerait alors que la mère et les mobiles).
- **Le nom du poste** publié est l'étiquette de l'appairage (40 caractères, un jeu de caractères qui exclut l'identifiant d'un dossier). La liste blanche prouve sa forme, pas son intention : un administrateur pourrait nommer un poste du nom d'une personne. ☐ Accepter (consigne : nommer le poste, jamais une personne) ☐ Publier un identifiant neutre (« Poste 3 »), au prix d'un écran moins lisible.
- **Version du protocole** : aucune n'est publiée aujourd'hui (le protocole n'en porte pas). Le relais accepte la clé `protocole` (entier de 1 à 9999) et l'écran la montre quand elle existe, sinon « non publié ». ☐ Ne pas en publier ☐ La mère publie un numéro de version du protocole (à définir avec la spécification).
- **Accès superadmin** : le panneau entier (et non le seul écran) est réservé aux comptes `superadmin`, vrai par défaut pour tout compte existant (le seul chemin de création est la commande `relais:superadmin`). ☐ Garder ☐ N'en réserver que cet écran.
- **Un fileul « jamais vu »** (appairé, jamais contacté) ne lève pas d'alerte de silence : on ne peut pas juger un silence sans premier contact. ☐ Garder ☐ L'alerter après ________ jours.
- **Écran du poste** : l'écran « Synchronisation » existe au panneau du relais seulement. Le poste Flutter porte les douze écrans de la maquette (module RLS) ; celui-ci n'a pas de pendant à la maquette. ☐ Pas de pendant au poste ☐ Le porter au poste (la mère y a déjà ces compteurs).


## V. Réponses de la Direction du 13/11/2026 (sections L à U) et lots qui en découlent

Réponses reçues le 13/11/2026 sur les points ouverts des sections L à T. Les cases cochées ci-dessous font foi. Les interprétations que le texte de la réponse laisse ouvertes sont marquées « à confirmer ». Aucune de ces réponses n'est encore appliquée au code : chaque ligne « Lot » est à lancer.

### Laboratoire (section Q)
- **Forme du seuil** : GARDER « l'une ou l'autre » (absolue ou relative, l'alerte part dès que l'une est atteinte). Rien à changer.
- **Qui valide un seuil** : la validation RESTE au Biologiste médical. L'administrateur système n'en a pas le droit par défaut. Le technicien de laboratoire est exclu par défaut, mais cette exclusion n'est pas figée dans le code : valider un seuil devient un DROIT de la fiche RBAC (par rôle), le Biologiste médical seul l'ayant à l'origine, et un administrateur peut l'accorder au technicien sur sa fiche. Lot : sortir la liste de rôles `labo_variables` du code vers un droit RBAC réglable (à confirmer : le droit s'accorde par rôle, pas par agent).
- **Date de jugement d'une mesure** : à sa validation biologique. GARDER.
- **Alerte visible du médecin au comparatif** : GARDER. **Comparatif à trois antériorités, une seule sur la fiche imprimée** : GARDER.
- **Courriers « numérisés » sans fichier** : les 25 du jeu sont des textes de démonstration. En production, un courrier enregistré sans scan est « À scanner ». Déjà le comportement du moteur (`numerise` dérivé du fichier), rien à changer.
- **Seuils et centre « Validations en attente »** : la Direction n'a pas compris la question, voir la proposition ci-dessous.
- **Constantes d'hospitalisation** et **délai maximal entre deux mesures** : proposition ci-dessous, à valider.

### Importation et fichiers (sections L, M, P, R, S)
- **Article déjà sorti, import refusé par la mère** : GARDER (l'article reste chez le fileul, marqué « refusée par la mère », restitution partielle) ET prouver l'IDEMPOTENCE : rejouer le verdict, la restitution ou la réconciliation ne produit jamais un second mouvement ni un second article. Lot.
- **Deux fileuls, même inventaire** : IDEMPOTENCE au lieu d'un refus après coup. Le même fichier d'inventaire (même empreinte) est reconnu comme le MÊME lot : la mère confirme une fois, le second fileul adopte les mêmes identifiants de fiche, aucun double comptage, aucune restitution nécessaire. Remplace `DOUBLON_MAGASIN`. Lot.
- **Journal des demandes d'import** : lisible par la mère ET les fileuls (pas par un téléphone). C'est le comportement actuel, GARDER.
- **Grand Stock en attente** : vu du seul poste qui l'a écrit, restitution par mouvements inverses. GARDER.

### OCR (section T)
- **Moteur** : à choisir après l'essai sur trois vrais scans (TROIS SUFFISENT). **Activation** : désactivée par défaut, activée à la main par l'administrateur ou la DAF. **Relance** : à qui écrit sur l'écran de la pièce, plus l'administrateur et la DAF.
- **Correction manuelle du texte lu** : OUI, par un agent habilité, SIGNÉE et JOURNALISÉE ; elle s'ajoute comme une version signée, la lecture machine reste lisible. Lot.
- **Réglage** : propre à chaque poste ET remonté à la mère pour une synchronisation uniforme. À confirmer : lecture proposée = l'activation, la langue et le délai sont des réglages de CLINIQUE posés à la mère (famille R, jamais vers un téléphone), chaque poste ne portant en propre que ce qu'il a d'installé (le moteur disponible ou non). Lot.
- **Texte d'un scan de zone 2** : ACCEPTER qu'il voyage à tous les fileuls comme la fiche (seul l'affichage est de zone).
- **Conservation des versions du texte lu** : sans réponse, illimitée par défaut.

### Sauvegardes (section O)
- **Destinations** : DEUX réglages séparés, magasin d'un côté, fichiers de l'autre. **Fréquence** : copie des fichiers toutes les heures, contrôle chaque nuit. OK.
- **Copie hors site** : la Direction la veut par un serveur distant ou par le relais web. État réel à ne pas confondre : le relais ne détient aujourd'hui que le JOURNAL chiffré (donc une copie hors site des données synchronisées), aucun octet de scan, aucune copie de la base de la mère, et la section S disait « aucun octet par le relais ». Lot proposé : sauvegarde chiffrée au poste (clé de la clinique) puis déposée au relais ou à un serveur distant, en blocs opaques, avec limite de taille et d'espace d'hébergement dite, deux destinations (magasin, fichiers). À confirmer : cela renverse la décision « aucun octet de fichier par le relais », pour la seule sauvegarde.

### Documents (sections L et M)
Propositions soumises, pas encore tranchées : demande d'import en famille A ; ordre de portage des 12 jeux (stock, prix, garanties et couvertures, comptabilité) ; droits d'import par jeu écrits au poste ; résultat différent = refus et restitution ; annulation après confirmation refusée chez le fileul ; personnel réservé à la mère ; dépôt d'un scan = droit de l'écran ; un fichier par fiche avec remplacement ; taille maximale 10 Mo réglable ; vue unifiée du dossier élargie aux comptes rendus de maternité et aux fiches de consultation (renvois seulement, droit de zone inchangé).

## W. Lot IDEM (13/11/2026, domaine et poste) : l'idempotence de l'import chez les fileuls, ce qui reste à trancher par la Direction

Appliqué : les trois décisions de la section V (article déjà sorti : comportement gardé et idempotence prouvée ; deux fileuls, même inventaire : adoption au lieu du refus après coup ; journal des demandes et Grand Stock en attente : inchangés). Écarts E2565 à E2574, plan `docs/plans/PLAN-importation-bouton-par-ecran.md` (lot IDEM). Ce qui suit est ce que le lot a dû choisir sans réponse écrite de la Direction : à confirmer ou corriger.

- **Qu'est-ce que « le même fichier » ?** La section V dit « même empreinte ». L'empreinte consignée au lot est un CRC-32 de l'OCTET du fichier (parité avec la maquette) : 32 bits, et un classeur et un CSV du même inventaire en donneraient deux. Le lot retient donc l'**identité de CONTENU** : SHA-256 du jeu et de ses lignes normalisées (cellules rognées, espaces insécables ramenés à l'espace, entiers sans décimale, lignes vides ignorées, en-têtes sans casse ni accent). Un même fichier donne toujours la même identité. ☐ Garder (contenu normalisé) ☐ Exiger l'identité d'OCTETS (un classeur et un CSV du même inventaire seraient alors deux lots, ce qui rouvre le double comptage).
- **Un fichier presque identique** (UNE cellule change, une ligne de plus) : c'est un AUTRE lot. Si ses articles recouvrent ceux d'un lot déjà tenu, il est refusé par la règle ordinaire (`DOUBLON_MAGASIN`, ligne et article nommés) ; si ses articles sont nouveaux, il s'écrit comme un lot ordinaire. Rien ne « devine » qu'un fichier ressemble à un autre. ☐ Garder ☐ Ajouter, avant d'écrire, un message « ce fichier ressemble au lot X : N lignes sur M sont identiques » (non fait : demande un seuil de ressemblance que personne n'a fixé).
- **Durée pendant laquelle une identité de lot est retenue.** Proposition : TANT QUE des fiches du lot existent. L'identité est portée par les fiches et le lot (jamais une table à part, jamais purgée) : un lot actif ou confirmé la retient, donc le même fichier est « déjà importé ». Elle se LIBÈRE quand le lot est défait (annulé avant la réponse de la mère, restitué après un refus, annulé à la mère) ; une nouvelle tentative prend alors la série suivante (`T2`, `T3`…). Une fiche archivée à la main, sans défaire le lot, continue de retenir l'identité. ☐ Garder ☐ Limiter dans le temps (par exemple 12 mois) ☐ Libérer aussi quand un article est archivé à la main.
- **Le même fichier réimporté par le MÊME fileul** : permis tant que le lot précédent est défait (annulation avant la réponse de la mère, refus de la mère) ; refusé, nommé « ce fichier est déjà importé » (`LOT_DEJA_IMPORTE`, rien n'est écrit, aucune demande) tant que le lot est actif ou confirmé. La mère ne vérifie rien de plus : une demande dont la série est celle d'un lot qu'elle a ANNULÉ est refusée (`LOT_ANNULE_A_LA_MERE`, une nouvelle tentative prend une série neuve). ☐ Garder.
- **Le premier lot est refusé par la mère, un second fileul dépose le même fichier** : la mère rejoue l'analyse (jamais un refus recopié) : le même contenu sur le même état redonne le même refus nommé, rien n'est écrit, chaque fileul restitue ; si l'état de la mère a changé entre-temps (l'article en cause a été archivé), le second dépôt peut être accepté. Un fichier refusé est consigné UNE fois par demande, un rejeu n'en consigne pas un second. ☐ Garder ☐ Retenir le refus avec l'identité du lot (le second dépôt est refusé sans rejouer, même si l'état a changé).
- **Adoption d'un lot sous une autre série** (un fileul qui avait réimporté après annulation, tentative 2, alors que la mère a confirmé la tentative 1 d'un autre fileul) : la mère adopte quand même (même contenu), le fileul dont la série diffère REBASE son écriture : elle est restituée comme après un refus (archivage, contre-passations nommées) mais sans refus, les fiches de la mère lui arrivent. Limite : si ce fileul avait DÉJÀ sorti du stock sur sa copie, cette copie reste, marquée, à côté des fiches de la mère (restitution partielle, dite sur la demande) : un article en double visible jusqu'à décision. ☐ Garder ☐ Fusionner à la main (écran de réconciliation, non fait).
- **Identifiants des fiches d'un lot** : la série des identifiants (`<COL>-<série>-<rang>`) ne vaut plus l'identifiant de la demande mais `IMP` et les 20 premiers caractères de l'identité (suffixe `T<n>` à la tentative `n`). Les lots écrits avant ce lot gardent leurs identifiants (`PRO-DIM…`) ; une demande déposée avant ce lot et encore en attente suit l'ancien chemin (série = demande, pas d'adoption). ☐ Garder.

## X. Lot B (13/11/2026, maquette) : le droit de valider un seuil, les constantes d'hospitalisation à la source, le délai entre deux mesures, ce qui reste à trancher par la Direction

Appliqué : les quatre réponses de la section V qui touchent le laboratoire et l'hospitalisation (qui valide un seuil ; correction à la source des constantes ; délai maximal entre deux mesures ; ligne du centre des validations). Écarts E2575 à E2585, plan `docs/plans/PLAN-documents-numerises.md` (lot B). Maquette seulement : le poste Flutter n'est pas touché.

- **Le droit de valider un seuil s'accorde par RÔLE, jamais par agent.** Proposition (interprétation de « il aura ses droits RBAC ») : une case par geste réservé dans « Rôles et permissions », sur la fiche d'un rôle. Le Biologiste médical l'a d'origine ; l'administrateur système et la Direction non. Conséquence à confirmer : dans la matrice actuelle, le technicien de laboratoire n'est PAS un rôle (c'est la fonction `tsl` portée par le rôle « Biologiste médical »). Pour lui accorder le droit, l'administrateur crée un rôle « Technicien de laboratoire » et coche la case ; accorder le droit au rôle « Biologiste médical » l'accorderait aux deux biologistes ET aux techniciens qui s'y connectent. La Direction veut-elle ce rôle distinct, ou un droit par fonction ?
- **Le droit n'ouvre pas l'écran.** Un rôle qui détient le droit doit aussi pouvoir ouvrir « Valeurs de référence » (et le centre des validations) ; ces ouvertures se règlent à part, écran par écran. Proposition retenue : ne pas les lier, pour ne rien ouvrir à l'insu de l'administrateur.
- **Unité de la tension : cmHg.** Reprise de ce que la saisie d'accueil de la clinique porte déjà (libellés, semence, échelle de la feuille de température 5 à 30). Deux nombres entiers stockés (systolique, diastolique) ; « 12/8 » n'est qu'un affichage. **À confirmer par un soignant** : que l'unité réelle de la clinique est bien le cmHg (et non le mmHg) pour tous les services.
- **Unité de la diurèse : millilitres**, saisie et stockée partout, sans décimale. Plafond de saisie de 5 000 mL repris de l'ancienne borne de 5 L de l'accueil ; pour l'hospitalisation c'est une **proposition à valider** (une diurèse de 24 heures cumulée peut dépasser 5 L ; faut-il une borne plus haute, ou aucune ?). Bornes de tension reprises de l'accueil (4 à 30 et 2 à 20 cmHg), **à valider** aussi.
- **Données déjà saisies sur un poste ancien.** Un poste en version 84 est ré-amorcé à l'ouverture : ses relevés de démonstration sont remplacés (comme à chaque incrément de la maquette). La Direction confirme que la maquette n'abrite que des données d'essai ; sinon un convertisseur est à écrire (règle dans E2578).
- **Délai maximal entre deux mesures : par variable, vide par défaut, jamais bloquant.** Posé avec le seuil (même version, même validation, même motif). Au-delà : « Variation non évaluée : mesure précédente trop ancienne (N jours, délai réglé D jours) », jamais « pas d'alerte ». L'âge de la mesure précédente s'affiche toujours. **Aucune valeur n'est proposée** : le biologiste règle chaque variable. Détail à confirmer : l'âge se compte en jours de calendrier entre les deux dates de mesure (pas à la validation), et un âge égal au délai est dans le délai.
- **La ligne du centre « Seuils enregistrés à valider » n'est visible que du porteur du droit.** Ni l'administrateur ni la Direction ne la voient sans le droit (le centre leur reste ouvert pour le reste). Elle compte les versions de seuil à l'état Enregistré et renvoie à « Valeurs de référence » : le geste de validation, avec son motif, reste à cet écran, un seuil à la fois, jamais en lot.
- **Courbes de constantes.** Aucune nouvelle courbe n'est ajoutée : la correction rend la courbe de surveillance existante exacte (plus de conversion), et la comparaison des antériorités porte toujours sur les résultats d'analyses, pas sur les constantes. La Direction souhaite-t-elle une comparaison des constantes dans le temps ?

## Y. Lot C (14/11/2026, maquette, domaine, poste, banc) : correction signée du texte lu et réglage OCR de clinique, ce qui reste à trancher par la Direction

Appliqué : les réponses de la section V qui touchent l'OCR (correction manuelle OUI, par un agent habilité, signée et journalisée ; réglage « propre à chaque poste ET remonté à la mère » ; texte d'un scan de zone 2 qui voyage comme la fiche). Écarts E2586 à E2596, plan `docs/plans/PLAN-documents-numerises.md` (lot C), PRD EF-DOC-15 et EF-DOC-16. **Aucun moteur d'OCR n'est choisi ni branché, aucune qualité de lecture n'est mesurée.**

- **Conservation des versions : ILLIMITÉE** (hypothèse, la Direction n'a pas répondu). Une lecture machine et une correction ne s'archivent ni ne se suppriment (RG-14) ; le coût est le poids du journal. À confirmer : une durée ou un nombre maximal de versions par scan, et ce qu'on en ferait au-delà (archivage vers la sauvegarde ?).
- **Correction signée contre relance machine.** Règle retenue : le texte courant est la correction signée la plus récente non remplacée ; une relance AJOUTE une lecture machine et ne la remplace jamais. Argument : une lecture machine ne vaut pas la signature d'un agent, et l'ordre des dates ne doit pas défaire un geste humain. L'agent « décide autrement » en signant une nouvelle correction (qui peut partir de la nouvelle lecture machine, proposée dans la fenêtre). À confirmer : la Direction veut-elle plutôt que la nouvelle lecture machine redevienne courante quand elle est jugée meilleure (un geste « abandonner ma correction » à nommer) ?
- **Réglage de clinique contre réglage de poste.** Lecture retenue de « propre à chaque poste ET remonté à la mère pour une synchronisation uniforme » : l'activation, la langue et le délai sont des réglages de CLINIQUE posés à la poste mère (versionnés par date, jamais vers un téléphone) ; chaque poste ne garde en propre que ses moteurs INSTALLÉS. **Hypothèse supplémentaire à confirmer : le CHOIX du moteur est aussi posé par la clinique** (identifiant lu partout ; un poste qui ne l'a pas installé le dit), ce qui garde l'identifiant de version de lecture identique d'un poste à l'autre. L'inverse (choix du moteur propre à chaque poste) est possible. Un fileul ne règle pas (commande absente, refus nommé) ; tant que la mère n'a rien publié, le fileul le DIT (« réglage non encore reçu de la poste mère ») au lieu de lire le défaut. Activation : désactivée par défaut, activée à la main par l'administrateur ou la DAF (inchangé).
- **Délai de lecture : 120 s** par page, valeur d'attente du lot OCR-prep, aucun document ne la fixe ; réglable à l'écran « Lecture des scans (OCR) ».
- **Qui peut corriger : proposition à valider.** D'origine, les rôles qui écrivent sur l'écran d'une pièce (courriers M13, documents du patient M1), PLUS lire la zone du scan (un compte rendu de zone 2 ne se corrige que par un profil clinique) ; le droit est un geste réservé de la fiche RBAC, que l'administrateur accorde ou retire par rôle. Question : la correction d'un texte médical doit-elle être réservée aux soignants (retirer le geste à l'accueil, à l'agent administratif, à l'ambulancier) ?
- **Conflit de correction.** Deux postes qui corrigent la même version avant de se parler donnent DEUX versions ; aucune n'est perdue ; le conflit est dit sur la carte, le texte courant est la plus récente (ordre que tous les postes retrouvent) ; une correction signée ultérieure remplace les deux. À confirmer : un agent doit-il être obligé de départager avant que la recherche lise l'un des deux textes ?
- **Correction sans lecture.** On ne corrige que ce qu'une lecture a produit (refus `CORRECTION_SANS_BASE`) : saisir à la main le texte d'un scan jamais lu est un autre geste (transcription), non demandé. À confirmer.
- **Journal.** Il ne porte que des identifiants de versions et des comptes de mots, jamais le texte médical ; la trace entière est la version immuable, lisible de qui lit la pièce.
- **Texte corrigé d'un scan de zone 2.** Même règle que la lecture machine : lisible du seul profil qui lit la zone, il arrive à tous les fileuls par le journal comme la fiche (réponse de la Direction, inchangée).
