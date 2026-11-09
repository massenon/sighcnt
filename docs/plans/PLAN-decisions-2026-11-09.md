# Plan : mise en œuvre des décisions de la Direction du 09/11/2026

Source : `docs/decisions/DECISIONS-A-VALIDER.md` (section D). Règle commune : tout paramètre est **en base**, réglable dans les paramètres du poste et du web, avec un défaut semé ; un paramètre qui change se versionne par date. Méthode : maquette d'abord, puis vecteurs, domaine Dart, poste. Un agent par lot, banc isolé, une suite complète et un audit RBAC à la fin de la série. Un seul agent écrit dans la maquette à la fois.

| Lot | Décision(s) couverte(s) | Contenu | Défaut |
|---|---|---|---|
| L1 | Validation Q1 à Q5 | Choix « Valider » dans la modale de mise à jour des 14 familles ; enregistrer par un profil de la famille valide ; hors famille l'élément repasse « à valider » (b) ; élément semé reste « à valider » jusqu'à la première relecture ; motif obligatoire pour les valeurs chiffrées ; création par un validateur naît validée ; une seule ligne de journal ; sonde du refus fileul | |
| L2 | AIB Q1, Q3, Q5, Q7 | Formulaire de validation du barème AIB dans les paramètres (famille `bareme_aib`) ; taux selon la situation de l'acheteur (1 %, 5 %, 3 %) ; charge des 5 % : paramètre **acheteur / clinique** ; branchement sur les écritures d'achat **différé**, avec son formulaire de validation | charge : clinique |
| L3 | MECeF (décision 3) | Paramètre **mode : boîtier ou e-MECeF** ; aucun numéro simulé au poste ; e-MECeF « non configuré : dossier d'interface DGI requis » | boîtier |
| L4 | Planning Q1 | Régime individuel qui déroge **champ par champ** (durée, repos, honoraire), le reste suit la catégorie | |
| L5 | Planning Q2, Q3 | Circuit de validation des présences et absences **paramétrable** (surveillant seul, DAF seule, surveillant puis DAF) ; congés et ordres de mission au même circuit, mission avec avis du chef de service | surveillant seul |
| L6 | Planning Q4 | L'agent **propose** une modification de son planning, le surveillant valide ; réglage « l'agent peut modifier directement » | non |
| L7 | Planning Q5, Q6, Q8 | Fiche de paie : copie chiffrée locale sur le téléphone, réglage oui/non ; espace « Mes » accessible sur poste partagé en secours (session nominative) ; « Mon assurance du personnel » en lecture seule | téléphone : oui |
| L8 | Planning Q7 | Le badge sert de pointage, réglage oui/non, relié au registre des présences | oui |
| L9 | Travail restant | Valeurs d'attente du personnel (marquage par champ) ; portage barème AIB, paramètres fiscaux, calendrier et versement CNSS vers vecteurs, Dart et poste ; SMS S3 à S6 ; module satisfaction ; relais en ligne R0 à R7 ; dictionnaire de données ; rechargements de page à rendre attentifs à l'envoi (E2307) | |

Ordre : L1, L2, L3, puis L4 à L8 (même écran M10 pour L4, L5, L6, L8 : un agent à la fois), puis L9. Le poste Flutter suit chaque lot de la maquette (vecteurs régénérés, parité N1).
Chaque lot rend : scénario de banc qui sonde au geste, réglage en base visible dans les paramètres, défaut vérifié, entrée ECARTS-MAQUETTE.md, commit.
