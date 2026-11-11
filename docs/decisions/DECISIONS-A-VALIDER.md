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
