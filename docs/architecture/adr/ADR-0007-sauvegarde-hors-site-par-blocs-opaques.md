# ADR-0007 : Sauvegarde hors site par blocs opaques chiffrés (relais web ou dossier distant), renversement borné de « aucun octet de fichier par le relais »

Statut : **accepté le 14/11/2026** par la Direction (« les deux lots », réponses du 14/11/2026, `docs/decisions/DECISIONS-A-VALIDER.md` sections V « Sauvegardes » et Z). Il **déroge** à la décision de la section S (lot D5, « aucun octet de fichier par le relais ») **pour la seule sauvegarde** ; il ne modifie ni l'ADR-0005 ni l'ADR-0006 (la synchronisation courante reste inchangée).
Date : 2026-11-14
Concerne : synchronisation (relais), sécurité, poste mère, hébergement.

## Contexte

La sauvegarde du magasin (copie nocturne de la base de la mère, chiffrée, 7 jours) et celle des fichiers numérisés (copie horaire incrémentale, lot SAUV-F) sont faites sur un **disque local**. Une panne de disque, un vol ou un incendie emportent les données ET leur copie. Le relais en ligne (`apps/web`, cPanel mutualisé) ne détient que le **journal chiffré** : c'est une copie hors site des données SYNCHRONISÉES, pas de la base de la mère, et pas un seul octet de scan (section S : « le relais reste opaque, il ne détient que le journal chiffré »).

La Direction veut une copie hors site « par un serveur distant OU par le relais web » et a accepté que cela renverse, pour la sauvegarde seule, la décision « aucun octet de fichier par le relais ». Sans décision, la clinique reste exposée à la perte totale (hors de la clinique, rien).

## Options examinées

1. **Ne rien changer** (disque externe, support emporté à la main). Aucune dépendance en ligne, aucune capacité d'hébergement requise. Inconvénient : dépend d'un geste humain quotidien, que personne ne vérifie ; c'est l'état actuel et la raison de la demande.
2. **Copier le dossier de sauvegarde tel quel vers un service en ligne tiers.** Écartée : le texte médical quitterait la clinique en clair ou sous une clé que la clinique ne maîtrise pas (règle du dépôt), et ajouterait un service externe.
3. **Relais web, blocs opaques chiffrés par la clé de la clinique** (retenue). Réutilise l'hébergement et le jeton de la mère déjà en place ; le relais ne voit que des blocs chiffrés, leurs identifiants, tailles et dates. Inconvénient : l'espace disque du cPanel est borné (quota dit), la taille d'une requête PHP aussi.
4. **Dossier distant monté (partage réseau, disque d'un autre site).** Même format, même chiffrement, aucune limite de requête ; la clinique le maîtrise. Inconvénient : cible concrète non fournie, SFTP à décrire sans l'inventer.

Les options 3 et 4 sont livrées derrière **une même interface de destination** ; la Direction règle une destination par type (magasin, fichiers).

## Décision

1. **Deux types de copie, deux réglages indépendants** : `magasin` (instantané de la base de la mère) et `fichiers` (les scans). Chacun a sa destination (`aucune`, `relais`, `dossier`), sa rotation, ses compteurs. Les deux sont **désactivés par défaut** (activation par l'administrateur ou la DAF, motivée, journalisée, RG-12) ; les réglages sont des **paramètres en base** (famille `horssite`, famille R, versionnés par date, **jamais envoyés à un téléphone**).
2. **Chiffrement au poste mère, clé de la clinique, jamais envoyée.** Le clair est découpé en blocs de taille bornée (défaut 1 Mio), chaque bloc est chiffré AES-256-GCM par la clé de la clinique (même clé que le journal), au format `nonce (12) ‖ chiffré ‖ tag (16)`. Le nonce est dérivé (HMAC-SHA-256 de la clé sur l'empreinte du clair) : un même clair donne le même bloc, d'où le **dédoublonnage** et l'**idempotence du rejeu** sans état local. L'**identifiant d'un bloc est l'empreinte SHA-256 du bloc chiffré**. Le **manifeste** (liste ordonnée des éléments et de leurs blocs, tailles, empreintes du clair) est lui aussi chiffré et déposé comme blocs : le relais ne connaît ni noms, ni formats, ni nombre de fichiers, seulement les identifiants de blocs et leur somme.
3. **Une famille de routes DÉDIÉE `/sauvegarde/*`**, jamais le journal (`/depot`), jamais une « charge libre » : état, blocs manquants, dépôt d'un bloc (octets bruts, empreinte revérifiée par le relais), ouverture d'une copie, rattachement des blocs, validation, liste, lecture. **Réservée à la mère** (en-tête de la mère) : un téléphone ou un fileul appairé reçoit **403 `sauvegarde_reservee_mere`**. Le relais ne juge jamais un contenu.
4. **Bornes dites et refus nommés.** Limite par copie (`SAUVEGARDE_TROP_GROSSE`), plafond d'espace hébergé (`ESPACE_RELAIS_INSUFFISANT`, avec le geste : augmenter le quota, réduire le nombre de copies gardées, passer à un dossier distant), bloc trop gros, bloc altéré en route, bloc manquant, rotation hors bornes. Tous les plafonds sont en base du relais (quota, limite par copie, taille maximale d'un bloc, plancher et plafond de rotation, délai des orphelins), défauts semés.
5. **Rotation sans suppression sèche.** Au-delà de N copies, la plus ancienne est **archivée** (restaurable, blocs gardés). Elle n'est **purgée** que si l'espace manque, la plus ancienne d'abord, jamais l'une des N copies courantes ni l'une des `plancher` plus récentes, jamais une copie en cours. Une copie purgée garde sa ligne (date, taille, motif : RG-14) mais n'est plus restaurable ; le relais le dit. Si l'espace manque encore : refus `ESPACE_RELAIS_INSUFFISANT`, la copie en cours n'est pas validée, **rien d'actuel n'est détruit**.
6. **Restauration vérifiée avant d'écrire.** Elle télécharge, déchiffre et vérifie chaque bloc (empreinte du chiffré, authentification, empreinte du clair, longueur) et le manifeste. Un bloc altéré ou manquant est **refusé et NOMMÉ**, et **rien n'est restauré à moitié** : la base et les fichiers sont écrits dans une cible NEUVE, atomiquement, après la dernière vérification ; la base ou le dossier en service ne sont jamais touchés par la restauration.
7. **Ce que le relais voit après cette décision** : pour la synchronisation, rien de plus qu'avant (aucun octet de scan DANS le journal, aucune règle métier, rien en clair). Pour la sauvegarde : des blocs chiffrés, leurs identifiants, tailles et dates, des compteurs. L'écran « Opacité » du panneau le prouve sur les blocs (entropie, aucune signature de fichier, aucun mot du texte).

Ce qu'on ne fait PAS : aucun octet de sauvegarde en clair ; aucune clé au relais ; aucune sauvegarde par un téléphone ; pas de SFTP (non fait, voir section AA) ; pas de suppression sèche tant que l'espace le permet ; pas de restauration qui remplace sans confirmation nommée la base en service.

## Conséquences

- **Positives** : une copie hors site, chiffrée, vérifiable, reprenable, par le relais déjà payé ou par un dossier de la clinique ; la rotation est bornée et dite ; aucune nouvelle dépendance en ligne.
- **Négatives, et ce qui les compense** : (a) l'espace d'un cPanel mutualisé est faible : quota dit, refus nommé, dossier distant en alternative, mesure avant la mise en service ; (b) **la clé de la clinique devient la seule porte de la reprise après sinistre** : sans elle les blocs sont irrécupérables (voir section AA : export de la clé existant, copie papier sous scellé) ; (c) le relais détient désormais des octets de santé chiffrés : la sécurité repose sur la clé, pas sur le relais ; (d) le dédoublonnage par nonce dérivé révèle au relais que deux blocs sont identiques (pas leur contenu) : accepté et dit.
- **Schéma** : une migration du relais (blocs sur disque sous `storage/app/sauvegardes`, jamais en base ; tables de copies et de liens), de nouveaux paramètres (famille `horssite`), aucune nouvelle fiche du magasin ; la maquette n'a pas de relais et n'est pas touchée.
- **RBAC** : le réglage et la restauration sont réservés à l'administrateur et à la DAF (comme la destination de la sauvegarde des fichiers) ; un fileul lit le réglage et ne le pose pas.
- **Bancs** : le banc de protocole (`packages/sync/banc`) porte le protocole en premier (relais de référence, client de référence, coupures) ; le relais Laravel rejoue les MÊMES scénarios (`banc:cible`) ; le domaine Dart porte les règles pures avec vecteurs tirés du banc.

## Comment on vérifiera que c'était la bonne décision

Les scénarios `SAUVHS*` du banc (dépôt coupé puis repris, mère tuée, bloc dupliqué, bloc altéré, quota dépassé, relais restauré, téléphone refusé, restauration complète octet par octet vers une base et un dossier neufs) ; l'écran « Opacité » du panneau ; une **restauration à blanc mensuelle** par l'administrateur sur une machine propre (à planifier) ; revue de cette ADR après la première mesure réelle sur l'hébergement cPanel (espace, `post_max_size`, temps d'exécution).
