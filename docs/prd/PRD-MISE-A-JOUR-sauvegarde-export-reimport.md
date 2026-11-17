# PRD : mettre à jour SIGH-CNT sans perdre les données (sauvegarde, export, réimport, resynchronisation)

Statut : **proposition à valider par la Direction** (17/11/2026), implémentée en partie par le lot MAJ (voir 0). Rédigé à partir de la question de la Direction : « As-tu implémenté l'exportation ou la sauvegarde de la base de données si on doit faire une mise à jour ? À une mise à jour d'une nouvelle version, on peut importer cette base dans le logiciel et faire la synchronisation. »

## 0. État d'implémentation (lot MAJ, 17/11/2026)

Décision de la Direction du 17/11/2026 : « il faut implémenter le manque » ; l'import par l'administrateur ET la Directrice Administrative, sur la mère ET sur un fileul. Détail : écarts E3080 à E3094, section BG des décisions. Les valeurs ci-dessous sont des propositions à valider.

| Exigence | État | Preuve |
|---|---|---|
| 1. Préparer la mise à jour (copie chiffrée, restauration vérifiée dans un dossier neuf, comptes, empreintes, journal) | **Service fait**, aucun écran | `maj_poste_test.dart` |
| 1. Refus `MAJ_SANS_SAUVEGARDE` (copie vérifiée de moins de 24 h, relue sur disque) | **Fait** (service et domaine) | `maj_test.dart`, `maj_poste_test.dart` |
| 2. Version du format lue à l'ouverture, chaîne de migrations idempotentes avec vecteurs, `DONNEES_PLUS_RECENTES` | **Fait** (M001 repère, M002 migration réelle d'exemple, RG-14 : noms archivés) | `maj_test.dart` |
| 3. L'installateur ne touche pas au dossier de données ; reprise après coupure | **Fait** (mesuré : `sigh_poste.iss` ne touche pas aux données ; reprise au démarrage de `main.dart`) ; installateur NON essayé sous Windows | `maj_poste_test.dart` (coupure simulée) |
| 4. Contrôle des comptes et empreintes avant mise en service, rapport « avant, après » | **Fait** (service) | `maj_test.dart`, `maj_poste_test.dart` |
| 5. Resynchronisation ordonnée : 426 sans perte, fileul mis à jour sans doublon | **Fait** contre la vraie mère Dart et deux fileuls ; **426 non branché au format stocké de l'application** (E3084) | `maj_sync_test.dart` |
| 6. Retour arrière (dernière copie vérifiée, saisies postérieures listées et gardées) | **Service fait**, écran « Annuler la mise à jour » NON FAIT | `maj_poste_test.dart` |
| 7. Clé de clinique requise pour tout import | **Fait** (`IMPORT_SANS_CLE`, `IMPORT_AUTRE_CLINIQUE`) | `maj_test.dart`, `maj_poste_test.dart` |
| 8. Export complet portable (un fichier chiffré, manifeste signé, format, fichiers numérisés), import dans un dossier neuf | **Fait** (service) ; fichiers numérisés en mémoire (E3091) | `maj_poste_test.dart` |
| 9. Essai à blanc | **Fait** (migration et import, rien n'est écrit) | `maj_poste_test.dart` |
| 10. Écran de restauration de la clé sur un poste neuf | **NON FAIT** (la fonction existe, E3089) | |
| 11. Mise à jour du relais : export relu avant migrations, retour arrière, outil de relecture `.jsonl.gz` | **Fait** (`relais:mise-a-jour`, `relais:relire-export`) | `MiseAJourRelaisTest.php` |
| 12. Mise à jour guidée des fileuls depuis la mère (P2) | Non fait | |
| 13. Contrôle d'intégrité planifié de la copie hors site (P2) | Non fait | |
| Droit | Geste réservé `lancer_mise_a_jour`, admin et DAF par défaut, un seul droit pour préparer, migrer, importer, annuler | `maj_poste_test.dart` |
| Mesure à 18 000 dossiers | Jeu généré (108 000 fiches) : préparer 5,5 s, migrer 18,6 s, export 6,5 s, import 12,8 s (E3094) ; jamais sur la machine de la clinique | `tool/mesure_maj.dart` |

Reste pour fermer le lot : les écrans (mise à jour mère et fileul, annuler, restaurer la clé), brancher le 426, essai sous Windows. Ne pas lire « fait » pour une ligne marquée service seul.

## 1. Ce qui existe déjà (mesuré dans le dépôt, à confirmer par un lot de mesure)

| Besoin | État | Où |
|---|---|---|
| Sauvegarde chiffrée quotidienne de la mère | **Fait** | écran « Sauvegardes et restauration » (poste mère), supervision |
| Vérification d'une restauration (dans un dossier neuf) | **Fait** | même écran, rien n'est restauré à moitié |
| Copie hors site chiffrée (relais web ou dossier distant monté), clé de clinique jamais envoyée | **Fait**, désactivée par défaut (ADR-0007) | réglage `horssite.*` |
| Sauvegarde de la clé de chiffrement par phrase de passe, restauration de la clé | **Fait** (fonction testée), **aucun écran** pour restaurer la clé sur un poste neuf | poste |
| Remplacement de la mère par une nouvelle mère depuis une sauvegarde | **Fait** (écran M-09) | poste mère |
| Sauvegarde et restauration des fichiers numérisés | **Fait** à la maquette ; au poste via la sauvegarde hors site | SAUV-F, lot 5 |
| Un fileul trop ancien est refusé nommément, sans rien envoyer (`426 schema_incompatible`) | **Fait** | protocole de synchronisation |
| Maquette : une restauration remplace toutes les collections et garde l'état précédent | **Fait** | `api/sauvegardes/` |
| **Sauvegarde OBLIGATOIRE avant une mise à jour** (refus de migrer sans copie vérifiée) | **Non fait** | |
| **Version du format des données et chaîne de migrations testées au poste** | **Non trouvée** dans le code (aucune version de schéma de données lue à l'ouverture du magasin du poste) : à mesurer | |
| **Export complet portable** (un seul fichier chiffré à importer dans une autre version ou une autre machine) distinct de la sauvegarde | **Non fait** | |
| **Procédure de mise à jour documentée** (ordre mère puis fileuls, retour arrière) | **Non fait** (le guide des commandes décrit un retour arrière du relais par restauration complète) | |
| Essai sous Windows | **Jamais fait** | |

Réponse courte à la question : la **sauvegarde et la restauration** existent ; **le parcours « mise à jour »** (copie obligatoire, migration des données, réimport, resynchronisation, retour arrière) **n'est pas implémenté en tant que tel**.

## 2. Énoncé du problème

Quand la clinique installe une nouvelle version, les données de 18 000 dossiers et de 30 agents doivent suivre, intactes. Aujourd'hui rien n'empêche d'installer une version sur un poste dont la dernière sauvegarde est ancienne ou jamais vérifiée, aucune étape ne garantit que le nouveau format sait relire l'ancien, et il n'existe pas de fichier unique pour déplacer la base vers une autre machine. Une mise à jour ratée touche la facturation, le stock et le dossier médical : le coût d'une perte est élevé.

## 3. Objectifs

1. **Aucune donnée perdue** à une mise à jour, mesuré par une comparaison avant et après (comptes par collection et empreintes).
2. **Aucune mise à jour sans copie vérifiée** : sans sauvegarde de moins de 24 h dont la restauration a été vérifiée, la migration refuse, en le nommant.
3. **Retour arrière en moins de 30 minutes** (valeur d'attente, à valider) : ancienne version plus dernière sauvegarde.
4. **Tous les postes resynchronisés** après la mise à jour sans conflit non nommé : mère d'abord, fileuls ensuite.
5. **Parcours de l'administrateur** en dix étapes numérotées au plus, sans commande à taper.

## 4. Hors périmètre (cette version)

- Mise à jour automatique en arrière-plan sans l'administrateur (risque trop élevé pour une clinique).
- Migration depuis le papier ou depuis l'ancien parc (c'est la reprise, autre chantier).
- Mise à jour des téléphones : ils se resynchronisent par le relais, sans base à migrer.
- Dépôt SFTP pour la copie hors site (déjà noté comme non fait).

## 5. Récits d'utilisateurs

- En tant qu'**administrateur**, je veux lancer « Préparer la mise à jour » qui sauvegarde, vérifie la restauration et me dit « prêt » ou « refusé : pourquoi », afin de ne jamais mettre à jour sans filet.
- En tant qu'**administrateur**, je veux installer la nouvelle version sans toucher au dossier de données, et que la migration des données se fasse au premier démarrage avec un compte rendu, afin de ne pas perdre un enregistrement.
- En tant qu'**administrateur**, je veux exporter toute la base en un fichier chiffré et l'importer sur un poste neuf ou une nouvelle version, afin de changer de machine ou de repartir d'une copie.
- En tant qu'**administrateur**, je veux annuler une mise à jour ratée (ancienne version et dernière sauvegarde), afin de reprendre le travail le jour même.
- En tant que **Directrice Administrative**, je veux voir que tous les postes sont à la bonne version et synchronisés, afin de savoir quand la clinique peut reprendre normalement.
- En tant qu'**agent d'un fileul**, je veux un message clair si mon poste est trop ancien (« mettre à jour ») et ne rien perdre de mes saisies hors ligne, afin de continuer à travailler.

## 6. Exigences

### P0 (indispensable)
1. **Préparer la mise à jour** (mère et fileul) : sauvegarde chiffrée, restauration vérifiée dans un dossier neuf, empreintes et comptes par collection enregistrés, journal RG-12. *Critère :* sans copie vérifiée de moins de 24 h (réglage de clinique en base, défaut proposé 24 h, daté), la migration refuse avec le code `MAJ_SANS_SAUVEGARDE` et dit le geste de correction.
2. **Version du format des données** lue à l'ouverture (par collection ou globale), et **chaîne de migrations** ordonnées, idempotentes, chacune avec ses vecteurs d'essai (avant et après) ; une version de données plus récente que le logiciel est refusée nommément (`DONNEES_PLUS_RECENTES`). *Critère :* migrer deux fois donne le même résultat ; aucune migration ne supprime un champ sans le conserver archivé (RG-14).
3. **L'installateur ne touche pas au dossier de données** et ne désinstalle jamais les données ; l'état « mise à jour en cours » est reprenable après une coupure (rien à moitié).
4. **Après migration** : comparaison des comptes et des empreintes avec la copie d'avant, rapport lisible (« 18 204 dossiers avant, 18 204 après »), toute différence est nommée ; le poste ne passe en service qu'après ce contrôle.
5. **Resynchronisation ordonnée** : la mère est mise à jour d'abord ; un fileul de version plus ancienne reçoit `426` et ne perd pas ses saisies en attente ; un fileul mis à jour rejoint la mère et se resynchronise sans doublon (identités par le contenu déjà en place).
6. **Retour arrière** : procédure et écran « Annuler la mise à jour » qui restaurent la dernière copie vérifiée avec l'ancienne version ; les saisies faites entre-temps sont listées, jamais écrasées en silence.
7. **Clé de clinique** requise pour tout import ; sans elle, refus nommé (sans clé aucune copie n'est lisible, c'est voulu).

### P1 (important)
8. **Export complet portable** : un fichier chiffré unique (base, fichiers numérisés, manifeste signé, version du format) importable dans une nouvelle version ou sur une autre machine ; import dans un dossier neuf après vérification.
9. **Essai à blanc** : simuler la migration sur une copie et dire ce qui changerait, sans rien écrire.
10. **Écran de restauration de la clé de chiffrement** sur un poste neuf (la fonction existe, l'écran manque).
11. **Mise à jour du relais** (migrations Laravel) : sauvegarde de sa base avant, retour arrière documenté, outil de relecture de l'export `.jsonl.gz` (absent aujourd'hui).

### P2 (à prévoir dans la conception)
12. Mise à jour guidée des fileuls depuis la mère (l'installateur est déposé par la mère, le fileul le lance).
13. Contrôle d'intégrité planifié de la copie hors site avec alerte.

## 7. Critères d'acceptation (extraits)

- **Étant donné** une mère avec 18 000 dossiers et sans sauvegarde vérifiée de moins de 24 h, **quand** l'administrateur lance la migration, **alors** elle refuse avec `MAJ_SANS_SAUVEGARDE` et propose « Préparer la mise à jour ».
- **Étant donné** une sauvegarde vérifiée, **quand** la nouvelle version migre les données, **alors** les comptes par collection avant et après sont identiques ou chaque différence est nommée.
- **Étant donné** une migration interrompue par une coupure de courant, **quand** le poste redémarre, **alors** il reprend la migration ou revient à l'état d'avant, jamais un état mixte.
- **Étant donné** un fileul de version plus ancienne, **quand** il se connecte, **alors** il reçoit `426 schema_incompatible`, n'envoie rien et garde ses saisies hors ligne.
- **Étant donné** une mise à jour ratée, **quand** l'administrateur choisit « Annuler la mise à jour », **alors** l'ancienne version reprend avec les données de la dernière copie et la liste des saisies postérieures est affichée.
- **Ne doit jamais arriver** : une migration qui supprime physiquement une donnée (RG-14) ; un import sans clé ; un poste mis en service avant le contrôle des comptes.

## 8. Métriques de succès

- **Avancées (premières mises à jour) :** 0 donnée perdue ; 100 % des postes resynchronisés sous 2 h après la mise à jour de la mère ; 100 % des mises à jour précédées d'une copie vérifiée.
- **Différées (3 à 6 mois) :** temps moyen d'une mise à jour sur la mère (cible à fixer par mesure sur 18 000 dossiers) ; nombre de retours arrière (cible : 0 non justifié).
- Mesure : rapport de comparaison avant et après archivé au journal ; essai de charge sur un jeu de 18 000 dossiers (jamais fait à ce jour).

## 9. Questions ouvertes

| Question | Pour qui | Bloquante ? |
|---|---|---|
| Fenêtre de mise à jour acceptable (nuit, dimanche) et durée d'arrêt maximale tolérée ? | Direction | Oui |
| Ancienneté maximale de la copie exigée avant la mise à jour (24 h proposé) ? | Direction | Oui |
| Combien de versions d'écart tolère-t-on entre la mère et un fileul (une seule, ou plusieurs) ? | Ingénierie et Direction | Oui |
| Qui a le droit de lancer la mise à jour et le retour arrière (geste réservé de la fiche RBAC : proposé administrateur et DAF) ? | Direction | Non |
| L'export portable doit-il pouvoir sortir de la clinique (clé de clinique requise pour le relire) ? | Direction | Non |
| Les migrations se font-elles à chaque démarrage ou par un geste explicite après sauvegarde ? (proposé : geste explicite pour la mère, automatique et reprenable pour un fileul) | Ingénierie | Non |
| Taille de la base réelle et temps de sauvegarde sur le matériel de la clinique (mesure à faire sur Windows) | Ingénierie | Oui |

## 10. Calendrier et phasage

- **Phase 1 (P0 : points 1 à 7)** : lot MAJ-1, avec un lot de mesure en tête (état réel de la version des données au poste, temps de migration à 18 000 dossiers). Maquette d'abord s'il y a une forme de donnée (version du format), puis vecteurs, domaine, poste mère, fileul.
- **Phase 2 (P1 : points 8 à 11)** : lot MAJ-2, export portable, essai à blanc, écran de restauration de la clé, mise à jour du relais.
- **Dépendances** : essai sous Windows (installateur, DPAPI) indispensable avant la première vraie mise à jour ; la recette sur site de la Direction (acceptation) ; aucune date imposée par un texte légal.
- **Preuves exigées** (doctrine du dépôt) : un test qui échoue sur l'arbre d'avant puis passe ; mutations rouges avec SHA-256 ; ce qui n'est pas vérifié est dit (Windows, deux machines, charge).
