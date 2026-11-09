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
