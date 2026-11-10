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
