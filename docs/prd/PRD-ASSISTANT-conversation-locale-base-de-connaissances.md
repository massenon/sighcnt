# PRD : Assistant de la clinique (conversation locale, base de connaissances, requêtes en lecture)

Statut : **brouillon, réponses de la Direction du 14/11/2026 intégrées** (section 10) ; toutes les décisions de la section 10 sont tranchées. **Lot AST-0 livré le 14/11/2026 (mesure seulement, rien au poste)** : couverture des 25 intentions 19 calculables, 4 après un petit lot, 2 non disponibles ; reconnaissance déterministe 94,0 % sur le contrôle figé, 100 % après corrections (non indépendant, l'auteur avait lu les cent questions), 0 réponse inventée, 0 connexion ; voir `docs/architecture/ASSISTANT-couverture-des-intentions.md` et la section AC de `DECISIONS-A-VALIDER.md`. Aucune valeur, aucun moteur, aucune borne n'est choisi ici sans source : ce qui manque est dit en section 10.
Sources : demande de la Direction du 14/11/2026 (assistant conversationnel sur le poste fileul et la mère, avec base de connaissances, pour analyser les recettes, vérifier les niveaux de stock, voir les articles qui tournent, produire des rapports, tenir l'inventaire du stock, retrouver vite un nom de patient, le prix d'un acte, un certificat, un fournisseur, la validité de l'assurance d'un patient, etc.), `CLAUDE.md` (règles RG-01 à RG-14, « le texte médical ne quitte jamais la clinique », hors périmètre CDCT §4.3 : « IA d'aide au diagnostic »), skills `sigh-maitre`, `sigh-flutter`, `spec`.
Règle de rédaction : pas de tiret cadratin comme ponctuation.

## 1. Problème

Les agents (réception, caisse, pharmacie, stock, comptabilité, Direction) passent par des écrans différents pour de simples questions de lecture : « le patient CNT530/25 a-t-il une assurance valide aujourd'hui », « combien coûte cet acte », « combien reste-t-il de cet article », « qui est ce fournisseur », « quelles recettes cette semaine ». Chaque réponse demande de connaître l'écran, ses filtres et ses droits. Les agents nouveaux ne connaissent pas les procédures (comment annuler un avoir, où saisir une sortie), que la clinique n'a écrites nulle part de façon consultable.

## 2. Ce que l'assistant EST et n'EST PAS

- **Est** : une zone de conversation, au poste (fileul et mère), qui comprend une question courte en français, la rattache à une **intention connue** d'un catalogue fermé (section 6), exécute la lecture par les **moteurs existants** (domaine Dart, un seul exemplaire des règles), et répond avec la **source** (écran, date de calcul, droit appliqué). Il répond aussi aux questions de procédure à partir de la **base de connaissances** de la clinique (section 7).
- **N'est pas** une aide au diagnostic, un avis thérapeutique, une interprétation de résultats, une prescription (hors périmètre CDCT §4.3, rien de cela n'est proposé).
- **N'est pas** un service externe : aucun appel hors de la clinique, aucune donnée de santé dans une requête, une alerte ou un son. Aucun fournisseur d'IA en ligne.
- **N'écrit rien en version 1** : jamais de création, modification, annulation. Une commande interdite est ABSENTE de l'assistant, pas grisée. Quand l'agent veut agir, l'assistant OUVRE l'écran concerné (formulaire éventuellement prérempli), l'agent valide lui-même avec ses droits.

## 3. Objectifs

- **O1.** Un volet « Assistant » au poste fileul ET au poste mère (même code, un seul exemplaire des règles), hors ligne, qui répond sans réseau à partir de la réplique locale.
- **O2.** Un **catalogue d'intentions fermé** (section 6), chacune avec sa source de données, son droit, son format de réponse et son refus nommé. Une question qui ne rentre dans aucune intention est dite « non comprise » avec trois intentions proches proposées, jamais une réponse inventée.
- **O3.** **Chaque réponse respecte les droits du demandeur** (rôle, fonction, secteur, zone) exactement comme l'écran concerné : l'assistant ne dit jamais ce que l'écran ne montrerait pas à cet agent (RG-13).
- **O4.** **Une base de connaissances locale** : guide d'utilisation, procédures, glossaire, règles de gestion, tarifs en vigueur, consignes de la clinique ; texte versionné, recherche locale, citation de la fiche source dans la réponse.
- **O5.** **Zéro chiffre inventé** : tout total est CALCULÉ par un moteur existant, « non calculable » est dit comme tel, jamais zéro (CLAUDE.md, règles 3 et 10).
- **O6.** **Traçabilité** : chaque question qui lit une donnée nominative est journalisée (RG-12 : utilisateur, date, intention, identifiants consultés) sans recopier le texte de la réponse au journal.
- **O7.** Réglages en base avec défaut semé (règle de paramétrage du 09/11/2026) : activation (désactivée par défaut), intentions actives, durée de conservation des conversations, moteur de langue éventuel.

## 4. Non-objectifs (version 1)

- Aucune écriture (pas de sortie de stock, pas d'encaissement, pas de certificat signé, pas de prescription).
- Aucun modèle de langage tiers en ligne ; aucun modèle local n'est installé ni choisi (section 8, comme pour l'OCR : l'interface existe, le moteur se choisit après essai).
- Pas d'assistant sur les téléphones (les mobiles passent par le relais et ne portent pas la réplique complète) ; pas de lecture par le relais : le relais ne voit jamais une question ni une réponse.
- Pas de synchronisation des conversations entre postes (section 9, décision proposée).
- Pas d'analyse prédictive ni de BI avancée (hors périmètre CDCT §4.3).

## 5. Utilisateurs et droits

L'assistant n'a **aucun droit propre** : il agit avec le profil de l'agent connecté. Un rôle sans droit de lecture sur l'écran source obtient le refus nommé `LECTURE_NON_AUTORISEE` (motif : « votre fonction ne lit pas cet écran », geste : « demander l'accès à l'administrateur »). **Tous les utilisateurs du système** disposent du volet (décision du 14/11/2026), chacun avec ses seuls droits : l'entrée du volet suit un geste réservé « utiliser l'assistant », accordé d'origine à tous les rôles qui ont un poste et réglable par rôle sur la fiche RBAC (comme `valider_seuil_labo` et `corriger_texte_ocr`), pour pouvoir le retirer à un rôle si la Direction le décide ; l'activation générale est un réglage de clinique (administrateur ou DAF).

Cloisonnement : une intention qui touche une donnée médicale exige le droit médical habituel ET la zone du scan ou du dossier ; un patient d'une zone interdite est répondu comme inexistant à ce profil (« aucun résultat visible pour votre profil »), jamais « interdit » (qui révélerait l'existence).

## 6. Inventaire des intentions (la liste à mettre en place)

Chaque ligne : intention, exemple de question, source à confirmer au lot de mesure (aucune collection n'est nommée ici sans l'avoir lue), droit exigé. Toutes sont **en lecture**.

**Patients (M1)**
1. Retrouver un patient par nom ou par code `CNT` (« CNT530/25 », « Mme Adjovi ») : identité, date de naissance, dernière visite. Droit M1 lecture, zone. Plusieurs homonymes : liste à choisir, jamais le premier.
2. Validité de l'assurance d'un patient **à la date du jour ou à une date donnée** (RG-09) : compagnie, numéro, dates de validité, taux ; si la carte est invalide, dit que la facturation sera intégrale au patient. Droit réception, caisse, comptabilité.
3. Reste à payer et dernière facture d'un patient (caisse, comptabilité, Direction).
4. Admission en cours et lit occupé (hospitalisation, soignants habilités).

**Tarifs et actes (référentiel de tarifs unique)**
5. Prix d'un acte ou d'un produit : DEUX prix (non assuré, assuré), l'assuré cité avec la compagnie si connue ; prix du jour, ou prix à une date (versionnage par date). Droit : lecture du référentiel (caisse, réception, comptabilité, médecins).
6. Historique des changements de prix d'un acte (comptabilité, Direction).

**Stock et pharmacie (M6, M7)**
7. Niveau d'un article (stock total, par lot, par emplacement), seuil de réapprovisionnement, **FEFO** : lot à sortir en premier (RG-05).
8. Articles en rupture ou sous le seuil ; articles proches de péremption (délai paramétré).
9. **Articles qui tournent** (sorties les plus fortes sur une période choisie, classement) et **articles qui ne tournent plus** (aucune sortie depuis N jours, N réglable).
10. Valorisation du stock (CUMP) par secteur : calculée par le moteur, jamais saisie (comptabilité, DAF, Direction).
11. Inventaire du stock : état du dernier inventaire, écarts, articles non comptés ; **lancer** l'inventaire est une écriture, donc l'assistant OUVRE l'écran, il ne compte rien.

**Fournisseurs et achats (M7)**
12. Retrouver un fournisseur (nom, contact, délais), ses dernières commandes et livraisons, sa dette ouverte (comptabilité, achats).
13. Commandes en attente de validation (RG-04) : liste, qui doit valider.

**Caisse et recettes (M8, M6, M12)**
14. Recettes d'un jour, d'une semaine, d'un mois, par secteur, par groupe de prestation, par mode de paiement, par caissier (profils financiers). Comparaison à la période précédente. Totaux CALCULÉS.
15. Factures et avoirs d'une période, factures non certifiées MECeF (état de la certification locale).
16. Créances et impayés par ancienneté (comptabilité, DAF).

**Documents et certificats**
17. Retrouver un document, un courrier, un certificat déjà émis d'un patient (renvoi vers la pièce, droit de zone).
18. **Prix d'un certificat** (décision du 14/11/2026 : la demande portait sur la consultation du prix, pas sur la production du certificat) : « combien coûte un certificat médical », « quels certificats existent et à quel prix », avec les DEUX prix (non assuré, assuré) comme l'intention 5, lus dans le référentiel de tarifs unique. L'assistant ne prépare, n'ouvre ni n'émet aucun certificat (la signature et l'émission restent un geste du médecin habilité à l'écran, une pièce émise ne se réécrit jamais).

**Laboratoire et imagerie**
19. État d'une demande (demandée, payée, exécutée, validée) par code d'analyse ; résultats RENDUS seulement (jamais une saisie non validée), droit médical. Aucune interprétation clinique.

**Personnel et planning (M10, M11)**
20. Qui est de garde ou de permanence à une date (planning validé). Droit : lecture du planning.

**Pilotage et système**
21. Indicateurs du jour déjà calculés par le tableau de bord (nombre de consultations, d'admissions, d'analyses) ; ouvrir le tableau de bord.
22. État de la synchronisation (mère : fileuls et retard du journal ; fileul : état de sa connexion à la mère), alertes ouvertes (administrateur, DAF).

**Rapports**
23. **Générer un rapport** : l'assistant OUVRE l'état existant avec les filtres de la question (période, secteur) et propose l'impression (A4 ou rouleau). Aucun état nouveau n'est calculé par l'assistant : il appelle le moteur d'état (CLAUDE.md : un total d'état est CALCULÉ par `somme`).

**Aide et procédures (base de connaissances)**
24. « Comment annuler une facture » / « où saisir une sortie » / « qui valide les commandes » : réponse tirée de la base de connaissances, avec le lien vers l'écran.
25. Glossaire et règles (« que veut dire FEFO », « qu'est-ce qu'un avoir »).

*Confirmé par la Direction le 14/11/2026 : « inventaire des trcs a mettre » signifiait l'inventaire des INTENTIONS (la liste ci-dessus). Le catalogue est EXTENSIBLE : la Direction pourra ajouter des intentions ; ajouter une intention = une entrée du catalogue (source, droit, format, refus nommé) + ses vecteurs + son test, jamais du code éparpillé.*

## 7. Base de connaissances

- **Contenu initial semé** : guide de démarrage, procédures par module (celles de `docs/guides/`, du glossaire et des fiches d'écran `docs/architecture/ecrans/*.json`), règles de gestion RG-01 à RG-14 en langage d'agent, consignes écrites par la Direction. Aucun contenu inventé : ce qui n'a pas de source est marqué « à rédiger ».
- **Gestion** : fiches de connaissance en base (titre, texte, module, rôles destinataires, date d'entrée en vigueur, version), créées et modifiées par l'administrateur ou la Direction avec journal ; une fiche modifiée ajoute une version datée (jamais une réécriture) ; une fiche réservée à un rôle n'est jamais citée à un autre.
- **Recherche** : index local plein texte (sans modèle externe, sans « embeddings » tant qu'aucun moteur n'est choisi), classement par pertinence et par rôle destinataire, la fiche source est toujours citée avec sa date. Pas de fiche, pas de réponse : « aucune fiche ne répond à cette question », avec le moyen de la demander à la Direction.
- **Données de santé** : la base de connaissances ne contient JAMAIS de donnée nominative de patient (consignes, procédures, règles seulement).

## 8. Moteur de compréhension (décision en deux temps, comme l'OCR)

- **Version 1, sans modèle** : compréhension par intentions, règles de reconnaissance en français (mots clés, synonymes, entités : code patient, nom, article, fournisseur, période), entièrement déterministe, testable par vecteurs, sans réseau.
- **Interface `MoteurAssistant`** : le choix d'un modèle de langage LOCAL (installé au poste, jamais en ligne) est une décision ultérieure, après un essai chiffré sur un jeu de questions réelles de la clinique (mesure du taux de bonne intention, du temps de réponse, de la mémoire sur un poste de la clinique, taux de réponses inventées = zéro toléré). Aucun modèle n'est choisi ni livré dans ce lot. Un modèle éventuel ne fait que choisir l'intention et remplir ses paramètres ; la réponse chiffrée vient toujours d'un moteur du domaine, jamais du texte généré.
- **Garde-fou** : toute sortie du moteur est validée contre le catalogue (intention connue, paramètres typés) ; une sortie hors catalogue est refusée (`INTENTION_INCONNUE`).

## 9. Conversations : conservation et partage

Proposition (à valider) : une conversation est **propre au poste et à l'agent**, jamais synchronisée vers la mère, les fileuls ni le relais (elle peut contenir des noms), chiffrée au repos comme le reste de la base locale, conservée 30 jours par défaut (réglable, borné), purgée au-delà (archivage RG-14 : la purge est un archivage de la conversation, la trace RG-12 d'une lecture nominative reste au journal). L'agent peut effacer ses conversations. Aucune conversation ne sert à améliorer un modèle (aucun envoi).

## 10. Décisions de la Direction (14/11/2026) et ce qui reste ouvert

Tranché :
1. **Intentions de la version 1 : les 25 de la section 6**, avec la possibilité d'en AJOUTER (catalogue extensible, section 6).
2. **Rôles : tous les utilisateurs du système** (chacun avec ses seuls droits, section 5).
3. **Certificat : consultation du PRIX seulement** (intention 18), l'assistant ne prépare ni n'ouvre aucun gabarit.
4. **Téléphone : NON** en version 1 (les mobiles passent par le relais et ne portent pas la réplique).
5. **Base de connaissances : la Direction valide** chaque fiche avant publication (une fiche non validée n'est jamais citée) ; l'administrateur peut en proposer.

Restent ouverts :
6. **Un modèle de langage local à terme ?** TRANCHÉ le 14/11/2026 (« on suit ta recommandation ») : rien n'est décidé maintenant ; la version 1 fonctionne sans modèle (section 8) ; la question se reposera après la mesure du lot AST-0 (taux de bonne intention de la version déterministe) : si ce taux est suffisant, aucun modèle n'est nécessaire.
7. **Conversations** (section 9) : TRANCHÉ le 14/11/2026 (« on suit ta recommandation ») : propres au poste et à l'agent, non synchronisées, chiffrées, gardées 30 jours (réglable, borné).

Le lot de mesure AST-0 est lancé dès que le lot 8 est poussé (décision du 14/11/2026). Jeu de questions : `ANNEXE-ASSISTANT-100-questions-AST-0.md` (100 questions proposées, à compléter par les agents).

## 11. Critères d'acceptation (extraits)

- Une question de chaque intention livrée donne la bonne réponse, avec sa source et la date de calcul, au poste fileul ET à la mère, hors ligne.
- Un profil sans le droit d'un écran obtient `LECTURE_NON_AUTORISEE` sur l'intention correspondante ; la commande d'une écriture n'existe pas dans l'assistant.
- Le même patient, la même question, deux profils (accueil, comptabilité) : chacun reçoit seulement ce que son écran montre.
- « Non calculable » n'est jamais « zéro » : un article sans lot, une assurance sans carte, une période sans vente le disent.
- Aucune requête sortante : le test d'étanchéité (aucun accès réseau de l'assistant hors du poste et de la mère) passe ; aucun nom de patient dans le journal du relais.
- Une question inconnue ne donne jamais une réponse inventée : « non comprise » + intentions proches.
- Les droits de l'assistant et ses intentions se lisent dans `rbac.json` et dans le catalogue (une source), jamais en double dans l'interface.

## 12. Plan de livraison proposé (maquette d'abord, doctrine du dépôt)

1. **Lot AST-0 : mesure et catalogue (livré le 14/11/2026, voir le statut en tête)** : lister les moteurs et collections qui répondent à chacune des 25 intentions, dire lesquelles sont déjà calculables (et lesquelles non : une intention sans source reste « non disponible » et se dit, jamais une réponse inventée), jeu de 100 questions réelles de la clinique à fournir par la Direction pour mesurer la compréhension.
2. **Lot AST-1 : maquette** : volet « Assistant » (poste fileul et mère à venir), les 25 intentions (livrées par groupes : patients et tarifs, stock, fournisseurs et achats, caisse et recettes, laboratoire et planning, aide et rapports), base de connaissances semée, vecteurs tirés de l'écran réel.
3. **Lot AST-2 : domaine Dart** : intentions comme fonctions pures sur un port de lecture, reconnaissance en français, vecteurs de la maquette.
4. **Lot AST-3 : poste** : volet, droits, journal RG-12, conversation locale chiffrée, tests contre la réplique locale ; la mère passe par le même code.
5. **Lot AST-4 : moteur de langue local (optionnel)** : seulement après la décision 5 et un essai chiffré.

Preuves attendues : test qui échoue avant puis passe pour chaque intention et chaque refus nommé, mutations rouges (droit ignoré, intention hors catalogue acceptée, total fourni au lieu de calculé, conversation synchronisée, réponse nominative hors zone, écriture déclenchée par l'assistant), sonde d'étanchéité réseau. Non vérifié d'avance : qualité de compréhension sur le vocabulaire réel de la clinique, performance sur les vieux postes, un modèle local.
