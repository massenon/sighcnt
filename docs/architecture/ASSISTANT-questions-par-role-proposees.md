# Lot AST-1 : cinq questions par rôle (proposition)

**Statut : proposition à valider par la Direction.** Date : 16/11/2026. Ces questions sont ÉCRITES, pas collectées : elles sont plausibles, rien de plus. La Direction les relit et les remplace par les questions réelles de son personnel, avec leurs fautes et abréviations (c'est ce que demande l'annexe AST-0 et ce que la décision sur le moteur attend, `docs/architecture/ASSISTANT-couverture-des-intentions.md` section 7).

## Comment l'utiliser

- **Remplacer** une question par celle que l'agent pose vraiment, mot pour mot, fautes comprises (« stk paracetamol », « cb reste »).
- **Corriger** l'intention visée ou le rôle si la question ne correspond pas au travail de ce rôle.
- **Ajouter** des lignes : une question hors catalogue qui revient souvent est le signal qu'une intention manque à la version 1.
- Les noms de patient, prix, numéros et valeurs cliniques sont volontairement absents : « le patient CNT/…/26 », « tel examen », « tel médicament ».
- Colonne « Intention » : code I01 à I25 du PRD (`docs/prd/PRD-ASSISTANT-conversation-locale-base-de-connaissances.md` section 6) ; HC = hors catalogue. Colonne « État » : calculable, après petit lot, non disponible (état du CŒUR de l'intention, avec la limite entre parenthèses quand elle est plus sévère) ou hors catalogue. Colonne « Droit » : lue dans `packages/rbac/data/rbac.json` (`parRole[rôle][écran]`, premier terme) ; l'assistant ne dit jamais ce que l'écran ne montrerait pas (RG-13), une question sur une donnée que le rôle ne lit pas est GARDÉE avec « refus attendu, nommé ».

## Points à connaître avant de relire

- `rbac.json` contient **20 rôles actifs** (22 avec `pharmacien` et `rh`, archivés), pas 16 : les 20 sont couverts. La pharmacie est tenue par `caissier`. Le rôle Ingénieur biomédical n'existe plus. L'Assistant de Direction est `assistant_comptable`, l'Assistant Comptable `aide_comptable`.
- Le droit d'une intention est « au moins un des écrans de lecture listés est visible du rôle » ; l'axe fonction et secteur (résultats du laboratoire, zone médicale) n'est pas vérifié ici et reste à contrôler au moment de l'exécution.
- Questions « non disponible » faute de fiche (I24, I25) : aucune fiche de connaissance n'est validée, donc la réponse est « pas de fiche » tant que la Direction n'a rien validé.
- Aucun avis médical n'est répondu (une seule question en demande un, pour vérifier le refus). Aucune écriture n'est demandée.
- État calculé sur l'intention, pas sur la réponse de bout en bout : aucune intention n'est encore exécutée.

## Les questions

### Administrateur système (`admin`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 1 | La mère est à jour ? Quel poste a du retard ? | I22 | calculable | oui (écran mere-supervision) |
| 2 | Il y a des alertes de synchronisation ouvertes ce matin ? | I22 | calculable | oui (écran mere-supervision) |
| 3 | Quand a été faite la dernière sauvegarde ? | HC | hors catalogue | écran visible du rôle (m14-sauvegardes, mere-sauvegardes) ; à ajouter au catalogue avec ce droit |
| 4 | Comment je crée un nouvel utilisateur et je lui donne un rôle ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 5 | Quels rôles peuvent ouvrir les écrans de la paie ? | HC | hors catalogue | écran visible du rôle (m14-roles) ; à ajouter au catalogue avec ce droit |

### Direction / Gérance (`direction`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 6 | Combien de consultations et d'admissions aujourd'hui ? | I21 | calculable | oui (écran dash-direction) |
| 7 | Recettes de la semaine par secteur, comparées à la semaine d'avant | I14 | calculable | oui (écran m8-recettes) |
| 8 | Qui nous doit le plus d'argent, les assureurs ou les patients ? | I16 | après petit lot (tranches fixes, balance des patients à faire) | oui (écran m9-creances) |
| 9 | Il y a des commandes de stock qui attendent ma validation ? | I13 | calculable | oui (écran m7-commandes) |
| 10 | Combien coûte la masse salariale du mois ? | HC | hors catalogue | écran visible du rôle (m11-calcul) ; à ajouter au catalogue avec ce droit |

### Directeur Médical (`dm`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 11 | Combien d'admissions cette semaine ? | I21 | calculable | oui (écran dash-direction) |
| 12 | Lits libres en hospitalisation | I04 | calculable | oui (écran m3-admissions) |
| 13 | Le résultat de tel examen du patient CNT/…/26 est rendu ? | I19 | calculable (résultat rendu seulement) | oui (écran m5-demandes) |
| 14 | Recettes du mois, ventilées par secteur | I14 | calculable (recettes (encaissé) ou chiffre d'affaires (facturé) à trancher) | oui (écran m8-recettes) |
| 15 | Qui est de garde ce week-end ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) |

### Directrice de l’Administration et des Finances (DAF) (`da`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 16 | Commandes de stock gros en attente de ma validation | I13 | calculable (validateur : RG-04 seulement, pas un réglage lu en base) | oui (écran m7-commandes) |
| 17 | Créances par ancienneté, assureurs et patients | I16 | après petit lot (tranches fixes, balance des patients à faire) | oui (écran m9-creances) |
| 18 | Factures de la semaine non certifiées MECeF | I15 | calculable | oui (écran m8-factures) |
| 19 | Combien on doit à tel fournisseur ? | I12 | calculable (deux définitions de la dette (écart E21)) | oui (écran m7-fournisseurs) |
| 20 | Valeur du stock au CUMP, secteur par secteur | I10 | calculable (secteur = groupe de famille d'article) | oui (écran m6-point-stock) |

### Médecin (`medecin`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 21 | Dans quel lit est le patient CNT/…/26 ? | I04 | calculable | oui (écran m3-admissions) |
| 22 | Le résultat de tel examen de CNT/…/26 est rendu ? | I19 | calculable (résultat rendu seulement) | oui (écran m5-demandes) |
| 23 | Retrouve l'ordonnance d'hier du patient CNT/…/26 | I17 | après petit lot (vue unifiée du dossier à élargir) | oui (écran m1-documents) |
| 24 | Il reste du tel médicament à la pharmacie ? | I07 | calculable | oui (écran m6-produits) |
| 25 | Quelle dose de tel médicament pour un enfant de tel poids ? | HC | hors catalogue (avis thérapeutique : refus attendu AVIS_MEDICAL_REFUSE) | refus attendu, nommé AVIS_MEDICAL_REFUSE (aucune aide au traitement) |

### Infirmier / Sage-femme (`infirmier`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 26 | Lits libres en maternité | I04 | calculable | oui (écran m3-admissions) |
| 27 | Le patient CNT/…/26 est toujours hospitalisé ? Quel lit ? | I04 | calculable | oui (écran m3-admissions) |
| 28 | Le résultat de l'analyse de ce patient est prêt ? | I19 | calculable (résultat rendu seulement) | oui (écran m5-demandes) |
| 29 | Comment je note la sortie d'un patient hospitalisé ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 30 | Qui est de garde cette nuit ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) |

### Biologiste médical (`laborantin`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 31 | Où en est la demande d'analyse du patient CNT/…/26 ? | I19 | calculable | oui (écran m5-demandes) |
| 32 | Le résultat de tel examen est validé ? | I19 | calculable | oui (écran m5-demandes) |
| 33 | Combien coûte tel examen, assuré et non assuré ? | I05 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : cfg-tarifs, m8-facturation) |
| 34 | Où en est la commande de réactifs ? | I13 | calculable | oui (écran m7-commandes) |
| 35 | Il reste combien de tel réactif ? | I07 | calculable (le stock « du laboratoire » n'est pas un stock distinct, lecture par article) | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m6-produits, m6-stock-gros, m6-stock-detail, m6-lots) |

### Gestionnaire de Stock (`stock`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 36 | Articles en rupture | I08 | calculable | oui (écran m6-alertes) |
| 37 | Quel lot de tel article je sors en premier ? | I07 | calculable (FEFO (RG-05)) | oui (écran m6-produits) |
| 38 | Les articles qui n'ont pas bougé depuis un an | I09 | après petit lot (sorties par article à agréger, durée réglable) | oui (écran m6-mouvements) |
| 39 | Où en est l'inventaire, quels écarts ? | I11 | calculable | oui (écran m6-inventaire) |
| 40 | Quels articles n'ont pas été comptés à l'inventaire ? | I11 | non disponible (« non compté » n'est pas enregistré) | oui (écran m6-inventaire) |

### Caissier, Dispensaire (Pharmacie) (`caissier`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 41 | Recettes du jour par mode de paiement | I14 | calculable | oui (écran m8-recettes) |
| 42 | La carte d'assurance du patient CNT/…/26 est valable aujourd'hui ? | I02 | calculable (RG-09) | oui (écran m1-patients) |
| 43 | Combien reste-t-il à payer pour CNT/…/26 ? | I03 | calculable | oui (écran m8-factures) |
| 44 | Quels médicaments vont périmer dans trois mois ? | I08 | calculable (délai de 90 jours codé en dur à corriger) | oui (écran m6-alertes) |
| 45 | Combien il y avait de tel médicament à la fin du mois dernier ? | I07 | non disponible (NON_CALCULABLE_HISTORIQUE, jamais zéro) | oui (écran m6-produits) |

### Comptable (`comptable`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 46 | Factures de la semaine qui ne sont pas certifiées MECeF | I15 | calculable | oui (écran m8-factures) |
| 47 | Valeur du stock de la pharmacie au CUMP | I10 | calculable | oui (écran m6-point-stock) |
| 48 | Impayés de plus de 60 jours | I16 | après petit lot (N libre (60) n'existe pas, tranches fixes) | oui (écran m9-creances) |
| 49 | Quand le prix de tel acte a-t-il changé ? | I06 | calculable (acte du référentiel ; un produit n'a pas d'historique) | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : cfg-tarifs) |
| 50 | Montre-moi la balance des comptes du mois | HC | hors catalogue | écran visible du rôle (m12-balance) ; à ajouter au catalogue avec ce droit |

### Réception / Accueil (`reception`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 51 | Cherche Mme [nom] née en [année] | I01 | après petit lot (recherche par nom à porter, homonymes à lister) | oui (écran m1-patients) |
| 52 | Prix de la consultation générale, assuré et non assuré | I05 | calculable | oui (écran cfg-tarifs) |
| 53 | Combien coûte un certificat de tel type ? | I18 | calculable (prix unique, couverture SOS seule) | oui (écran cfg-tarifs) |
| 54 | Qui est de garde ce soir ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) |
| 55 | Le patient CNT/…/26 est hospitalisé ? Dans quel lit ? | I04 | calculable | oui (écran m3-admissions) |

### Agent Administratif (`agentadmin`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 56 | Retrouve le dernier courrier reçu pour le patient CNT/…/26 | I17 | après petit lot (courriers absents de la vue unifiée) | oui (écran m13-courriers) |
| 57 | Cherche le patient CNT/…/26 | I01 | après petit lot (recherche par code à porter) | oui (écran m1-patients) |
| 58 | Comment j'enregistre un courrier entrant ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 59 | Quelles réunions sont prévues cette semaine ? | HC | hors catalogue | écran visible du rôle (m13-reunions) ; à ajouter au catalogue avec ce droit |
| 60 | Qui est dans le lit 5 ? | I04 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m3-admissions, m3-plan-lits) |

### Ambulancier (`ambulancier`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 61 | Retrouve le patient CNT/…/26 que je dois transporter | I01 | après petit lot (recherche par code à porter) | oui (écran m1-patients) |
| 62 | Quelle ambulance est disponible aujourd'hui ? | HC | hors catalogue | écran visible du rôle (m13-ambulance) ; à ajouter au catalogue avec ce droit |
| 63 | Qui est de garde ce soir ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) |
| 64 | Comment je remplis la fiche de transport ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 65 | Dans quel lit est le patient CNT/…/26 ? | I04 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m3-admissions, m3-plan-lits) |

### Aide-soignante (`aide_soignant`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 66 | Quels lits sont libres dans le service ? | I04 | calculable | oui (écran m3-plan-lits) |
| 67 | Qui est dans le lit 12 ? | I04 | calculable | oui (écran m3-plan-lits) |
| 68 | Où je note les constantes d'un patient ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 69 | Les résultats du patient CNT/…/26 sont rendus ? | I19 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m5-demandes, m5-resultats, m2-imagerie-demandes) |
| 70 | Quand est ma prochaine garde ? | HC | hors catalogue | écran visible du rôle (m10-mes) ; à ajouter au catalogue avec ce droit |

### Technicien d’échographie (`echographiste`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 71 | L'échographie du patient CNT/…/26 est validée ? | I19 | calculable | oui (écran m5-demandes) |
| 72 | Combien d'échographies ont été faites aujourd'hui ? | HC | hors catalogue | écran visible du rôle (m2-stats-echographie) ; à ajouter au catalogue avec ce droit |
| 73 | Retrouve le patient CNT/…/26 | I01 | après petit lot (recherche par code à porter) | oui (écran m1-patients) |
| 74 | Quels examens d'imagerie attendent aujourd'hui ? | I19 | calculable | oui (écran m5-demandes) |
| 75 | Prix d'une échographie obstétricale | I05 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : cfg-tarifs, m8-facturation) |

### Surveillant (`surveillant`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 76 | Qui est de garde ce soir ? | I20 | calculable | oui (écran m10-planning) |
| 77 | Planning de permanence de la semaine | I20 | calculable | oui (écran m10-planning) |
| 78 | Qui est en congé cette semaine ? | HC | hors catalogue | écran visible du rôle (m10-conges) ; à ajouter au catalogue avec ce droit |
| 79 | Lits libres en maternité | I04 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m3-admissions, m3-plan-lits) |
| 80 | Comment je valide une proposition de planning ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |

### Assistant de Direction (`assistant_comptable`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 81 | Retrouve le dernier courrier de telle compagnie d'assurance | I17 | après petit lot (courriers absents de la vue unifiée) | oui (écran m13-courriers) |
| 82 | Quelles réunions sont prévues cette semaine ? | HC | hors catalogue | écran visible du rôle (m13-reunions) ; à ajouter au catalogue avec ce droit |
| 83 | Combien de consultations aujourd'hui ? | I21 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : dash-direction, dash-da, dash-croise) |
| 84 | Comment je fais une note de service ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 85 | Imprime l'état des ventes de la semaine | I23 | calculable (droit de la bibliothèque ET de l'écran de l'état) | refus attendu, nommé LECTURE_NON_AUTORISEE (écran de l'état fermé : m6-point-ventes ; bibliothèque : oui) |

### Chirurgien (`chirurgien`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 86 | Quel patient est dans le lit 8 ? | I04 | calculable | oui (écran m3-admissions) |
| 87 | Le bilan pré-opératoire du patient CNT/…/26 est rendu ? | I19 | calculable | oui (écran m5-demandes) |
| 88 | Retrouve le compte rendu opératoire du patient CNT/…/26 | I17 | après petit lot (vue unifiée du dossier à élargir) | oui (écran m1-documents) |
| 89 | Qui est de garde ce week-end ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) |
| 90 | Où en est la demande d'imagerie du patient CNT/…/26 ? | I19 | calculable | oui (écran m5-demandes) |

### Anesthésiste, Réanimateur (`anesthesiste`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 91 | Le bilan sanguin du patient CNT/…/26 est rendu ? | I19 | calculable | oui (écran m5-demandes) |
| 92 | Dans quel lit est le patient CNT/…/26 ? | I04 | calculable | oui (écran m3-admissions) |
| 93 | Retrouve la fiche d'anesthésie du patient CNT/…/26 | I17 | après petit lot (vue unifiée du dossier à élargir) | oui (écran m1-documents) |
| 94 | Comment on remplit la check-list du bloc ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 95 | Il reste du tel produit anesthésique à la pharmacie ? | I07 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m6-produits, m6-stock-gros, m6-stock-detail, m6-lots) |

### Assistant Comptable (`aide_comptable`)

| N° | Question telle que dite | Intention | État aujourd'hui | Droit à vérifier (RG-13) |
|---|---|---|---|---|
| 96 | Factures de la semaine non certifiées MECeF | I15 | calculable | oui (écran m8-factures) |
| 97 | Combien doit encore le patient CNT/…/26 ? | I03 | calculable | oui (écran m8-factures) |
| 98 | Les impayés des patients par ancienneté | I16 | après petit lot (balance des patients à faire) | oui (écran m9-creances) |
| 99 | C'est quoi un avoir ? | I25 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) |
| 100 | Combien on doit à tel fournisseur ? | I12 | calculable (deux définitions de la dette (écart E21)) | oui (écran m7-fournisseurs) |

## Récapitulatif chiffré (compté sur les questions ci-dessus)

Questions écrites : **100** (20 rôles, 5 par rôle).

| État aujourd'hui | Nombre |
|---|---|
| calculable | 64 |
| après petit lot | 14 |
| non disponible | 11 |
| hors catalogue | 11 |
| total | 100 |

Droit : 83 question(s) où le rôle a le droit de lire (ou intention ouverte à tous), 17 où le refus nommé est attendu.

Questions par intention (les intentions non listées n'ont aucune question) :

| Intention | Nombre |
|---|---|
| I01 | 4 |
| I02 | 1 |
| I03 | 2 |
| I04 | 12 |
| I05 | 3 |
| I06 | 1 |
| I07 | 5 |
| I08 | 2 |
| I09 | 1 |
| I10 | 2 |
| I11 | 2 |
| I12 | 2 |
| I13 | 3 |
| I14 | 3 |
| I15 | 3 |
| I16 | 4 |
| I17 | 5 |
| I18 | 1 |
| I19 | 11 |
| I20 | 7 |
| I21 | 3 |
| I22 | 2 |
| I23 | 1 |
| I24 | 8 |
| I25 | 1 |
| hors catalogue | 11 |

Intentions jamais demandées dans cette proposition : aucune.

Questions hors catalogue (à examiner pour décider quoi ajouter), regroupées par écran visé :

| Sujet (écran) | Nombre | Rôles |
|---|---|---|
| m13-reunions | 2 | agentadmin, assistant_comptable |
| m14-sauvegardes | 1 | admin |
| m14-roles | 1 | admin |
| m11-calcul | 1 | direction |
| avis médical (refus) | 1 | medecin |
| m12-balance | 1 | comptable |
| m13-ambulance | 1 | ambulancier |
| m10-mes | 1 | aide_soignant |
| m2-stats-echographie | 1 | echographiste |
| m10-conges | 1 | surveillant |

Lecture : aucun sujet hors catalogue ne revient plus d'une ou deux fois ici ; ce comptage ne dit rien du terrain. Les questions réelles diront lesquels reviennent (congés, planning personnel, réunions, ambulance et paie sont les candidats proposés).
