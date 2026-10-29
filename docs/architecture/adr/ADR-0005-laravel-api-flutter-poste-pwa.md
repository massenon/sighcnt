# ADR-0005 — Hub Laravel (API + panneau d'administration), poste Flutter, PWA Vue : réévaluation d'ADR-0003

| | |
|---|---|
| **Statut** | **proposé** — demandé par la Direction le 27/10/2026 ; **ne remplace pas ADR-0003 tant qu'il n'est pas accepté** |
| **Date** | 27/10/2026 |
| **Décideurs** | Direction, ingénierie |
| **Lié à** | ADR-0001 (local-first, hub en étoile, journal d'opérations), ADR-0003 (Flutter + hub Dart), `docs/prd/PRD-FLUTTER-poste-fidelite-maquette.md` |

## Contexte

ADR-0003 recommandait un seul langage (Dart) pour le poste, le mobile et le hub, afin que RG-03 / RG-09 / RG-10 n'existent qu'en **un** exemplaire. La Direction demande désormais une pile différente pour le serveur et le web :

- **Flutter desktop** (poste Windows/Linux) et mobile ;
- **Laravel** comme **API de synchronisation** et comme **panneau d'administration complet** (Livewire) ;
- **PWA** (Vue) pour les utilisateurs qui n'ont pas le poste installé ; la fin de cette exigence est tronquée dans la demande (« …pour des utilisateurs qui ont des… ») — voir Q1.

Un projet Laravel 12 + Inertia/Vue existe déjà hors dépôt (`sigh_web/`, ~70 000 lignes de PHP, base `sigh_cnt` de 173 tables ; cf. `CLAUDE.md`, « Architecture cible »). Il n'est pas versionné ici : son état réel est à vérifier avant de décider d'en reprendre quoi que ce soit.

## Le point qui décide : où vivent les règles métier ?

Avec Laravel côté serveur et Dart côté poste, **chaque règle existerait deux fois** (PHP + Dart) — exactement la divergence que ce dépôt a payée à chaque règle écrite en double (code patient, `carteValide`, date du jour). Trois façons de la contenir ; il faut en choisir **une** :

| Option | Principe | Coût | Risque |
|---|---|---|---|
| **A. Serveur autoritaire, poste en saisie** | Le poste capte et affiche ; les règles qui engagent (RG-03 stock, RG-09 assurance, RG-10 équilibre, RG-01 code) sont **appliquées par Laravel** à la synchronisation et leur refus revient en **conflit nommé**. Le poste n'exécute qu'un sous-ensemble de contrôles de confort. | Moyen | Hors ligne, le poste ne peut pas toujours *calculer* (part assureur, avoir) : l'agent voit un montant provisoire |
| **B. Règles en double + vecteurs de tests partagés** | PHP et Dart implémentent les mêmes règles ; des cas JSON (entrée → sortie) exportés de la maquette sont rejoués des **deux** côtés en CI | Élevé, permanent | La divergence est détectée, pas empêchée |
| **C. Un seul exemplaire exécutable partout** | Domaine en Dart appelé aussi par le serveur (ADR-0003) | — | C'est l'option que la demande écarte |

**Recommandation : A pour les invariants qui engagent, B (vecteurs) pour tout ce que le poste doit calculer hors ligne** (répartition assureur/patient, totaux, écritures). Les vecteurs de tests viennent de la maquette, exécutable de référence.

## Répartition des responsabilités

| Composant | Rôle | Hors ligne ? |
|---|---|---|
| **Flutter poste** (Windows/Linux) | Saisie et caisse à plein débit, impression (A4, 80 mm, CR80), boîtier MECeF, SQLite chiffré | **Oui** (autonome) |
| **Laravel API** | Autorité des données (PostgreSQL), endpoint de synchronisation par journal d'opérations, RBAC serveur, notifications, planificateur (`schedule:run`), journal d'audit | — |
| **Laravel + Livewire** | Panneau d'administration complet (utilisateurs, rôles/RBAC, référentiels, tarifs, modules actifs, audit, sauvegardes, tâches planifiées, supervision) | Non (en ligne) |
| **PWA Vue** | Accès navigateur/téléphone pour les profils qui n'ont pas le poste ; consultation + saisie ciblée ; mise en cache et file d'envoi hors ligne limitées | **Partiel** |

**Contrainte à écrire noir sur blanc** : la PWA n'est **pas** un support de données de santé hors ligne durable (ADR-0003, option F écartée : le cache du navigateur n'est pas un coffre). Elle met en file des opérations non sensibles ; le reste exige la connexion.

## Ce qui ne change pas

Journal d'opérations (ADR-0001), archivage au lieu de suppression (RG-14), aucune action anonyme (RG-12), boîtier MECeF branché à la **caisse** (pas au serveur), pas d'exposition du serveur à Internet sans passerelle/VPN, fidélité à la maquette (PRD Flutter).

## Conséquences

- **Positives** : écosystème Laravel/Livewire mûr côté API et administration ; panneau d'administration quasi gratuit ; recrutement PHP plus large que Dart serveur ; un panneau web sans installation.
- **Négatives** : deux langages et deux exemplaires de règles (voir ci-dessus) ; trois interfaces à tenir à parité (Flutter, Livewire, Vue) — **l'ergonomie doit venir d'un seul système de conception** (jetons partagés, §« Système de conception ») ; le moteur de synchronisation (ADR-0004) change de nature : un **endpoint** Laravel remplace PowerSync/ElectricSQL-sur-Dart, ou les complète.
- **Impose** : schéma unique source de vérité (migrations Laravel → PostgreSQL, **et** SQLite poste dérivé du même dictionnaire) ; suite de vecteurs de tests partagée ; RBAC exprimé **une fois** (matrice exportable en JSON) et lu par Laravel, Flutter et Vue ; règles de nommage des identifiants techniques figées (cf. doctrine « on ne renomme pas un identifiant technique »).

## Architecture recommandée (27/10/2026, après réponse de la Direction)

```
 Salle / réseau local de la clinique (Wi-Fi + câble, HTTPS par autorité interne)
 ┌──────────────────────────── Serveur local (+ onduleur) ───────────────────────────┐
 │ Laravel API (sync, RBAC, audit)  ·  PostgreSQL 16 (autorité)  ·  Redis (files)     │
 │ Reverb (WebSocket, temps réel)   ·  Planificateur  ·  Stockage de pièces (fichiers)│
 │ Panneau d'administration (Vue/Inertia)  ·  PWA servie ici                          │
 └────────▲───────────────▲───────────────────────▲──────────────────────────────────┘
          │ sync          │ sync                  │ HTTPS + WebSocket
 ┌────────┴───────┐ ┌─────┴────────┐       ┌──────┴───────────────────────┐
 │ Poste Flutter  │ │ Poste Flutter│  ...  │ Tablette/mobile Flutter (soins)│  PWA (navigateur)
 │ SQLite chiffré │ │ SQLite       │       │ SQLite chiffré, hors ligne    │  en ligne d'abord
 │ + boîtier MECeF│ │ + outbox     │       └───────────────────────────────┘
 └────────────────┘ └──────────────┘
```

**Principes**
1. **Le poste est autonome** : il écrit d'abord dans sa base locale et dans une **boîte d'envoi** (outbox) ; la synchronisation est un arrière-plan. Serveur arrêté, la caisse, l'accueil et la consultation continuent.
2. **Journal d'opérations, pas copie de tables** : identifiants UUIDv7 produits par le poste, clé d'idempotence par opération, horloge logique hybride, version par fiche, curseur de tirage par séquence serveur. Rejouer deux fois ne duplique rien.
3. **Cinq familles de fusion, déclarées par écriture** : (a) *ajout seul* (constantes, administrations, notes) — union, jamais de conflit ; (b) *dernier geste par champ* pour les champs sans enjeu ; (c) *invariant arbitré par le serveur* (stock RG-03, lit occupé, solde de caisse) — refus **nommé** et file de résolution ; (d) *numéros* — plages réservées par poste (codes patient, pièces), numéro fiscal toujours issu du **boîtier MECeF** ; (e) *référentiels* — le serveur seul écrit, les postes lisent. Aucune suppression ne se propage : **archivage** (RG-14).
4. **Beaucoup de dossiers** : le serveur porte tout (PostgreSQL : index B-tree + `pg_trgm` pour la recherche par nom, pagination côté serveur, journaux partitionnés par année). Le poste réplique **toutes les identités** (légères) et le **jeu chaud clinique** (hospitalisés, vus depuis 24 mois, rendez-vous à venir, dossiers ouverts) ; le reste se tire **à la demande** quand le serveur répond. Hors ligne, un dossier hors du jeu chaud est signalé « non disponible hors ligne », jamais affiché vide. Pièces et clichés : fichiers à part, tirés à la demande.
5. **Temps réel** : WebSocket (Reverb) pour *prévenir* qu'une collection a changé (aucun contenu dans l'événement), sondage de repli toutes les 3 s (déjà éprouvé à la maquette).
6. **Soins en salle** : l'infirmier utilise de préférence **l'application Flutter mobile/tablette** (même code que le poste, base locale, hors ligne). La **PWA** sert aux accès sans installation ; elle est **en ligne d'abord** : file d'envoi limitée, **aucune donnée de santé en cache lisible**. Serveur arrêté, le tableau de bord de la PWA ne s'affiche pas : c'est la limite du navigateur, assumée.
7. **Serveur** : un seul serveur sur onduleur, sauvegarde chiffrée quotidienne + copie hors site, restauration à blanc ; **recommandé** : second serveur à chaud (réplication PostgreSQL en flux) avec bascule manuelle documentée, pour que les PWA et mobiles ne dépendent pas d'une seule machine.
8. **Sécurité** : HTTPS sur le réseau local par une **autorité de certification interne** (une PWA exige un contexte sécurisé ; `localhost` ne s'applique pas aux autres appareils) ; appareils enregistrés et révocables ; jetons courts ; RBAC appliqué **par le serveur** depuis la matrice JSON unique, puis par le client ; SQLCipher dont la clé est dans le coffre du système ; journal d'audit côté serveur (RG-12).
9. **Une seule base d'interface : Flutter, y compris pour le web** (*corrige la version du 27/10 matin, qui proposait Vue + Inertia*). Les 305 écrans de la maquette doivent être portés **une fois**. Flutter compile aussi en **web installable (PWA)** : le panneau d'administration (M14, CFG, M13… sont déjà des écrans de la maquette) et l'accès distant sont le **même code** que le poste, avec le même thème et les mêmes droits. Cela supprime Vue **et** Livewire du périmètre d'interface : Laravel devient une **API pure**. Réserves à vérifier au banc : poids du premier chargement, tableaux denses dans le navigateur, accessibilité ; le chiffrement de base locale (SQLCipher) n'existe pas dans le navigateur, donc la version web est **en ligne d'abord**. **Repli** si le banc échoue : une PWA Vue **réduite** (une vingtaine d'écrans : tableau de bord de salle, tâches, constantes, consultation), jamais les 305 écrans.
10. **Contre les écarts et les inventions** : le contrat est **engendré**, jamais recopié — spécification OpenAPI produite par Laravel, client Dart produit depuis elle ; tables locales dérivées du dictionnaire de données ; thème dérivé des jetons de la maquette ; matrice RBAC lue depuis **un** JSON ; vecteurs de tests tirés de la maquette ; captures de référence comparées en CI. Un agent de codage travaille sur ces artefacts, pas sur sa mémoire, et toute règle sans source est marquée « à valider ».

## Accès hors du réseau de la clinique (exigence de la Direction)

La PWA doit marcher **hors du réseau local**. C'est le point le plus sensible de l'architecture : il expose des données de santé à Internet. Recommandation :

- **Aucun port ouvert sur le serveur de la clinique.** Le serveur établit une liaison **sortante** vers un point d'entrée (passerelle) ; seul ce point est joignable d'Internet.
- La passerelle impose **authentification forte (second facteur)**, limitation de débit, journalisation, et **appareil enregistré** ; les sessions distantes sont courtes.
- **Périmètre réduit en distant** : par défaut lecture de tableaux de bord et de dossiers de ses propres patients, saisies ciblées ; pas de caisse, pas de comptabilité, pas d'export en masse. Le périmètre se règle **par rôle** dans la matrice.
- **Limite physique** : l'accès distant dépend de la connexion Internet de la clinique **et** de son serveur. Si l'un tombe, la PWA distante ne fonctionne pas ; seule l'application installée (poste, tablette) reste autonome. Un **réplica en nuage** de lecture seule est possible plus tard ; il change le modèle de risque et exige une décision de la Direction.
- Décision à prendre avant tout code : passerelle maison (VPS) ou service tiers, et hébergement des données (**cadre légal de protection des données de santé** à vérifier — je ne suis pas juriste).

## Reprise de `sigh_web/` (décision de la Direction : reprendre)

`sigh_web/` (Laravel 12 + Inertia/Vue, 288 pages Vue, ~70 000 lignes de PHP, base `sigh_cnt` de 173 tables) **n'est pas dans ce dépôt et je ne l'ai jamais vu**. Je ne peux ni l'auditer ni garantir qu'il se reprend. Marche à suivre :

1. L'**importer sur une branche dédiée** (sans `.env`, `vendor/`, `node_modules/`, `storage/`, sauvegardes) — il n'est sous aucun contrôle de version aujourd'hui.
2. **Audit en une passe** (livrable `docs/architecture/AUDIT-SIGH-WEB.md`) : version des dépendances, migrations rejouables sur base vide, **écart avec `DICTIONNAIRE-DONNEES.md`** (139 tables de la maquette contre 173), tests qui passent, RBAC existant contre la matrice, modules couverts parmi les 16.
3. **Règle de reprise** : on garde ce qui passe l'audit (migrations, modèles, services, authentification) **comme base de l'API** ; les **pages Vue ne sont pas reprises comme interface cible** (leur fidélité à la maquette est inconnue) mais peuvent servir de **repli PWA réduit** ; tout ce qui contredit la maquette ou une règle de gestion est corrigé **vers la maquette**, jamais l'inverse.
4. Le mot de passe de base commité dans le prototype et tout secret présent dans `sigh_web/` sont à **changer** avant import.

**Limites assumées** : serveur arrêté, deux postes ne voient pas les saisies l'un de l'autre jusqu'au retour (pas de synchronisation de poste à poste en première version) ; un invariant partagé (dernier lot, dernier lit) peut produire un conflit visible au retour — c'est voulu, la maquette de ce comportement est le banc d'ADR-0003.

## Révision du 29/10/2026 — contraintes d'hébergement : cPanel mutualisé, ni Redis ni WebSocket

**Contraintes de la Direction** : serveur en ligne sur **cPanel mutualisé** (tâches `cron` seulement, pas de démon), **ni Redis ni WebSocket**, panneau d'administration en Laravel + Blade + Livewire + Alpine, PostgreSQL, serveur local sur onduleur supervisé, restauration possible depuis le web si les postes tombent. *Cette section corrige la section « Architecture recommandée » : le temps réel par WebSocket et Reverb est retiré, Livewire revient pour le panneau (il fonctionne sur hébergement mutualisé), Flutter reste l'interface de tous les écrans métier.*

### Trois niveaux, un seul protocole

```
 Poste / tablette Flutter ──(réseau local)──► CONCENTRATEUR LOCAL (PC sur onduleur)
   SQLite chiffré + outbox                      Laravel + PostgreSQL + planificateur, supervisé
        │                                              │  même protocole, le concentrateur
        └──(secours : Internet)──────────┐             │  se comporte comme un poste
                                         ▼             ▼
                                   SERVEUR EN LIGNE (cPanel) : relais + coffre + panneau
                                   Laravel + Blade + Livewire + Alpine · cron · sauvegardes chiffrées
```

- **Le concentrateur local est l'autorité d'exploitation courante** : la clinique ne doit pas dépendre de la connexion Internet pour que les postes se voient entre eux.
- **Le serveur en ligne reçoit le journal** du concentrateur (même protocole d'envoi/réception que les postes, donc un seul code) : il sert de **coffre**, de **relais** et de **panneau superadmin**.
- **Une seule autorité à la fois** (pas de cerveau partagé) : bascule explicite par le superadmin vers le serveur en ligne si le concentrateur est perdu ; au retour, le concentrateur se resynchronise depuis le serveur en ligne avant de reprendre.
- **Secours des postes** : si le concentrateur est arrêté **et** qu'Internet répond, un poste synchronise directement avec le serveur en ligne (liste d'adresses ordonnée dans sa configuration).

### Hébergement mutualisé : ce qu'il impose

| Fonction | Choix | Pourquoi |
|---|---|---|
| Temps réel | **Interrogation courte avec curseur** (réponse vide très légère), 3 s sur le réseau local, 30 s en ligne ; **FCM** (notification poussée) pour réveiller un mobile | Pas de démon : WebSocket impossible ; flux serveur et longue interrogation **bloquent un processus PHP** par client, ce que le mutualisé ne supporte pas |
| Files de tâches | `queue:work --stop-when-empty` lancé par `cron` chaque minute, pilote **base de données** | Pas de Redis ni de superviseur de processus |
| Planification | `php artisan schedule:run` chaque minute | Seul mécanisme disponible |
| Cache, sessions | fichier ou base de données | Redis inutile à cette échelle |
| Verrous | verrous consultatifs PostgreSQL (`pg_advisory_lock`) | remplacent les verrous Redis |
| Lots de synchronisation | petits lots, pagination, durée < 30 s | limites d'exécution et de mémoire du mutualisé |

### Réserve de sécurité (à décider)

Un hébergement **mutualisé** ne permet ni de maîtriser le chiffrement du disque, ni d'isoler les locataires, ni d'installer ce qu'on veut. Deux niveaux d'usage :
1. **Relais + coffre + panneau** : les sauvegardes et snapshots y sont **chiffrés avant envoi, avec une clé que seule la clinique détient** ; le serveur ne voit pas le clair. Acceptable en mutualisé.
2. **Accès distant en clair par la PWA** (données de santé lisibles en ligne) : **déconseillé en mutualisé** ; il faut un **VPS** (coût faible, contrôle complet). À arbitrer avec le cadre légal de protection des données de santé.

À vérifier avant toute décision (cPanel) : PostgreSQL disponible ? (sinon le serveur en ligne ne garde que le **journal d'opérations et des instantanés chiffrés**, stockés en MySQL, sans schéma relationnel) ; version de PHP (Laravel 12 exige 8.2 ou plus) ; accès SSH ; intervalle minimal de `cron` ; quota disque et durée maximale d'exécution.

### Réponses de la Direction (29/10/2026, suite) et conséquences

- **PostgreSQL est disponible sur le cPanel** → PostgreSQL **partout** (poste : SQLite ; concentrateur et serveur en ligne : PostgreSQL). Pas de MySQL : un seul dialecte pour les migrations.
- **PHP ≥ 8.2, cron toutes les minutes, pas d'accès SSH.** Conséquences de déploiement : `composer install --no-dev --optimize-autoloader` et la compilation des ressources se font **sur le poste de développement** et le dossier est téléversé (Gestionnaire de fichiers ou Git du cPanel) ; la racine web pointe sur `public/` ; les commandes ponctuelles (`migrate --force`, vidage de cache) passent par une **tâche cron à usage unique** ou par un bouton protégé du panneau superadmin, jamais par un terminal ; le fichier `.env` n'est pas dans le dépôt ; une **sauvegarde automatique précède chaque migration**.
- **La PWA est retirée de la première version.** Elle n'apportait que l'accès sans installation (iPhone, ordinateur d'un tiers). Les utilisateurs mobiles installent l'application Flutter (Android) ; le panneau d'administration est en Livewire. Un navigateur n'a plus de rôle métier, donc plus de donnée de santé en cache de navigateur à protéger. *Cette décision remplace la section « Accès hors du réseau de la clinique » pour ce qui concerne la PWA.*
- **Accès hors de la clinique : par l'application mobile, et seulement sur des agrégats par défaut.** Le serveur en ligne reçoit du concentrateur des **indicateurs** (recettes, occupation, ruptures, retards de synchronisation) **sans nom de patient** ; un responsable à l'extérieur voit son tableau de bord, pas des dossiers. Cela permet de rester sur un hébergement mutualisé. Tout accès distant à des dossiers nominatifs est une **décision distincte** (VPS + cadre légal) et n'est pas dans la première version.

### Supervision du concentrateur local

Machine dédiée (**recommandé : mini-PC Linux sur onduleur**, pas un poste bureautique Windows) : redémarrage automatique après coupure (réglage du BIOS), mise en veille interdite, arrêt propre commandé par l'onduleur (NUT), disque de sauvegarde distinct, PostgreSQL et PHP lancés comme **services système avec redémarrage automatique**. Un module `supervision` (commandes Artisan planifiées toutes les 30 s) contrôle : base joignable, espace disque, âge de la dernière sauvegarde, retard de synchronisation **par poste**, tâches en échec, taux d'erreurs, expiration du certificat, état de l'onduleur ; il écrit dans une table d'événements, alimente l'écran « Supervision », prévient l'administrateur (courriel / SMS / FCM) et envoie un **battement de cœur** chaque minute au serveur en ligne, qui **alerte si le battement manque plus de 5 minutes**.

### Les trois « limites assumées » : corrections

1. **Deux postes qui ne se voient pas, concentrateur arrêté** → réduire la probabilité (onduleur, redémarrage automatique, **second PC de secours** à chaud, procédure de bascule écrite) ; puis, en version 2, **synchronisation locale de poste à poste** avec le **même journal d'opérations** (un poste désigné relaie) — plus tard, car elle double la complexité.
2. **Dernier lot sorti deux fois** → **un seul écrivain par zone** : le stock d'un magasin n'est écrit que par le poste qui en est responsable ; quand deux postes doivent sortir du même stock, le concentrateur leur **alloue un quota par article** (bail) que le poste consomme hors ligne. Sans conflit ni stock négatif ; le bail se renouvelle à la reconnexion. Même principe pour les lits (réservation par service).
3. **Règles en double** → les règles sont d'abord des **données** (tarifs, taux, grilles : un fichier, deux lecteurs) ; la logique restante est petite et testée par **les mêmes vecteurs JSON** dans PHPUnit et dans `dart test` ; le poste envoie son résultat calculé et le serveur **recalcule** : un écart est journalisé (indicateur « divergences » à l'écran de supervision) et le montant du serveur fait foi, affiché comme « montant ajusté ».

### À ne pas recopier d'un autre projet

Le guide de synchronisation fourni (appairage, curseurs, « renvoyer vers tous les postes », réinitialisation) est un **bon patron**, mais il vient d'une autre application (il nomme des « unités d'hébergement » et des « véhicules » qui ne sont pas des objets de SIGH). Adaptations obligatoires :
- **« Suppression synchronisée » → archivage synchronisé** (RG-14) : aucune suppression physique, jamais ; référentiels (chambres, lits, ambulances) archivés, jamais supprimés.
- **Appairage par UUID du poste** (le nom est une étiquette, pas une clé) ; jeton à usage unique, code court, expiration 15 min ; jeton d'appareil à rotation, stocké **haché**.
- **Réinitialisation de production : interdite par défaut.** La marque de réinitialisation avec purge locale n'a de sens que sur un environnement de test ; en production, elle exige double confirmation, sauvegarde préalable obligatoire et trace d'audit — ou n'existe pas.
- **Sauvegarde du poste avant migration de sa base et avant désinstallation** ; les opérations non envoyées ne sont jamais perdues en silence (export chiffré).

## Révision du 29/10/2026 (3) — le poste mère : le concentrateur est une application Flutter, pas Laravel

**Demande de la Direction** : le logiciel **desktop Flutter installé sur le serveur local** est le **poste mère** (géré par la DAF ou l'administrateur). Il reçoit toute la synchronisation, la redistribue aux autres postes desktop (**postes fileuls**), l'enregistre dans le PostgreSQL local **et** dans le PostgreSQL en ligne, et reçoit aussi les **applications mobiles** (version minimale pour les salles de consultation et les **consultations à domicile**). Le mécanisme est **automatique** et reprend seul après coupure du serveur local ou d'Internet.

**Effet sur l'architecture — cette révision remplace les sections précédentes là où elles disent le contraire :**

```
 Mobile Flutter (minimal)     Poste fileul Flutter        Poste fileul Flutter
   SQLite chiffré               SQLite chiffré              SQLite chiffré
        └──────────────┬───────────────┴──────────────────────────┘
                       ▼  réseau local (protocole P1)
            POSTE MÈRE (PC sur onduleur) : service Dart + PostgreSQL local + console DAF/admin
                       │  protocole P2 : enveloppes chiffrées de bout en bout
                       ▼  (Internet quand il est là, reprise automatique)
            RELAIS EN LIGNE (cPanel) : Laravel + Livewire + PostgreSQL + cron
            coffre chiffré, indicateurs sans nom de patient, panneau superadmin minimal
```

1. **Toutes les règles métier vivent en Dart**, dans `packages/domaine`, exécutées par le poste fileul, le mobile **et** le poste mère. **Il n'y a plus de règle en double PHP/Dart** : c'était le principal risque de la version Laravel-autorité, il disparaît. C'est la logique d'ADR-0003 (hub en Dart) ; le relais en ligne en Laravel n'y ajoute aucune règle.
2. **Le poste mère = un service + une console.** Le **service** (serveur HTTP local, accès PostgreSQL, moteur de synchronisation) tourne en arrière-plan, **indépendamment de toute session** ouverte et redémarre seul ; la **console** (même code que les autres écrans) sert la DAF ou l'administrateur : supervision, appareils, jetons d'appairage, conflits, « À traiter », journaux, sauvegardes, restauration. Fermer la console n'arrête pas la synchronisation. À valider au banc : exécution comme service Windows et comme service Linux.
3. **Le relais en ligne est opaque.** Il stocke des **enveloppes chiffrées de bout en bout** (clé de clinique détenue par les appareils de la clinique, jamais par le relais) : le PostgreSQL en ligne reçoit bien tout, mais **chiffré** ; il ne peut ni lire un dossier ni appliquer une règle. Cela rend l'hébergement mutualisé acceptable et permet la restauration depuis le web. Les **indicateurs** (sans nom de patient) sont envoyés **en clair** à part, pour le tableau de bord distant.
4. **Consultations à domicile** : le mobile **précharge avant le départ** (sur le réseau local) un lot minimal pour les patients de la tournée du jour, le garde chiffré, saisit hors ligne, et synchronise au retour sur le réseau local **ou**, en route, par le relais (enveloppes chiffrées). Un appareil révoqué perd son accès au prochain contact ; l'effacement à distance n'est donc **pas immédiat** si l'appareil est hors réseau (limite à connaître).
5. **Une seule autorité à la fois** : le poste mère. Le relais n'est jamais une autorité ; si le poste mère est perdu, un **nouveau poste mère** se reconstruit depuis le relais (tirage des enveloppes + clé de clinique) ou depuis une sauvegarde.
6. **Rôle de Laravel (cPanel)** réduit à : panneau superadmin minimal (Blade, Livewire, Alpine), stockage opaque des enveloppes, indicateurs, battement de cœur, rétention des sauvegardes, notifications poussées (FCM), tâches `cron`. **Aucune règle de gestion, aucun écran métier.**
7. **Clé de clinique** : sans elle, sauvegardes et relais sont irrécupérables. Génération à l'installation du poste mère, **copie papier sous scellé** détenue par la Direction, procédure de rotation. Risque de perte à traiter comme un risque de premier rang.

**Contrepartie assumée** : la console du poste mère est un point de défaillance unique pour l'administration locale. Atténuations : onduleur, redémarrage automatique, second poste mère à froid (installé, appairé au relais, non autoritaire), restauration à blanc trimestrielle.

La spécification détaillée du protocole est dans [`docs/specs/SPEC-protocole-synchronisation.md`](../../specs/SPEC-protocole-synchronisation.md).

## Banc de validation avant acceptation

1. Synchronisation bidirectionnelle hors ligne sur deux postes Flutter : zéro doublon de code patient, conflit visible sur stock (critères 1–2 d'ADR-0003).
2. **Vecteurs de tests** : 100 % identiques maquette ↔ Laravel ↔ Dart sur les moteurs exposés (`PR.repartir`, `PR.encaisser`, `emettreAvoir`, `exercice`…).
3. Boîtier MECeF + impression 80 mm / A4 / CR80 depuis Flutter (critères 3–4 d'ADR-0003).
4. Performance : liste de 20 000 lignes < 1 s côté poste ; API p95 < 500 ms avec 15 postes + 5 téléphones.
5. PWA : installation, mise à jour du service worker, file d'envoi, **aucune donnée de santé en cache clair**.
6. Reprise : arrêt brutal d'API et de poste en pleine écriture, restauration depuis sauvegarde.

**Seuil de bascule** : si les critères 1, 2 ou 3 échouent de façon non corrigeable en deux semaines, retour à ADR-0003 (hub Dart).

## Questions ouvertes

- **Q1 (Direction)** — *Répondu : la PWA doit fonctionner hors du réseau de la clinique* → section « Accès hors du réseau ». Reste à décider : passerelle, hébergement, périmètre distant par rôle.
- **Q2 (ingénierie)** — *Répondu : reprendre.* Reste à **fournir `sigh_web/`** (branche dédiée) pour l'audit.
- **Q3 (ingénierie)** — *Recommandation révisée : Flutter pour tous les écrans, web compris ; ni Livewire ni Vue (sauf PWA réduite de repli).* À confirmer après le banc web.
- **Q4 (Direction)** — Les exigences non fonctionnelles génériques de la demande (« 100 000 utilisateurs simultanés », 99,99 %) sont des chiffres de gabarit : la clinique compte ~30 agents et ~15 postes. Quels objectifs retient-on réellement ? (proposition dans le plan)
- **Q5 (fournisseur / DGI)** — Protocole du boîtier MECeF (inchangé depuis ADR-0003).
