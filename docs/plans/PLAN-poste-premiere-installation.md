# PLAN — Poste : première installation, activation de la mère, rejoindre une clinique
Source : `docs/prd/PRD-POSTE-premiere-installation.md` (Q1, Q2, Q3, Q4, Q5, Q6, Q7 arbitrées le 02/11/2026) ; `docs/specs/SPEC-protocole-synchronisation.md` §3 · Estimation : 9 étapes de moins d'une demi-journée chacune, hors recette sur Windows · Branche : `claude/sighcnt-monorepo-offline-first-i0v3v9`

## Résultat attendu
- Un poste vide propose « Première installation » ou « Rejoindre une clinique » ; la première crée le compte administrateur (mot de passe choisi, code de secours), ouvre le tableau de bord avec la modale des configurations, et la clôture exige un second administrateur.
- Un fileul se rattache par code d'appairage, reçoit configurations et comptes, ne propose aucune configuration modifiable.
- Prouvé par : tests Dart du poste (assistant, code de secours, réinitialisation), vecteurs du domaine (code de secours, verrou 5 essais), banc de synchronisation à deux postes (diffusion d'une configuration) ; la recette sur Windows reste à faire par la Direction.

## Existant à réutiliser (inventaire fait le 02/11/2026)
- `lib/core/identifiants.dart` : `ServiceIdentifiants` (Argon2id, verrou, `definir`, `verifier`, `amorcerAdministrateur`). Réutilisé ; `amorcerAdministrateur` (mot de passe provisoire aléatoire) est REMPLACÉ pour la première installation par la saisie de l'installateur, et gardé seulement en repli de développement.
- `lib/modules/auth/acc_ecrans.dart` : `EcranConnexion`, `EcranMotDePasseOublie`, `EcranReinitialisation`, `EcranVerrou` (écrans autonomes, sans coquille). Les nouveaux écrans suivent le même modèle (`EcranAutonome`).
- `lib/mere/activation.dart` (`ActivationMere.activer`, refus nommés `relais_invalide`, `secret_requis`, `cle_invalide`, `relais_injoignable`) et `lib/mere/console.dart` (console de la mère, émission des codes d'appairage). Aucune seconde implémentation de l'activation.
- `lib/core/parametres_poste.dart` (`ParametresPoste`, `StockageParametres`) : porte l'état local du poste ; on y ajoute l'état d'installation.
- `lib/modules/m14/mot_de_passe.dart` (génération du mot de passe provisoire affiché une fois, politique), `m14/utilisateurs.dart` : la réinitialisation par un administrateur existe en partie ; l'étape 5 la complète (14 caractères, 24 h).
- Écrans de configuration déjà portés : `cfg-entetes`, `cfg-modules`, `cfg-tarifs`, `cfg-natures-facture`, `cfg-comptabilite`, `mecef-config`, `m14-roles`, `m14-utilisateurs`. La modale renvoie vers eux, aucun écran de saisie nouveau.
- Pas de « code de secours » dans le poste aujourd'hui (recherche faite) : à créer.

## Étapes
### Étape 1 — Fixer les règles pures du code de secours et de la réinitialisation (domaine) [FAITE 02/11/2026]
- Fichiers : `packages/domaine/lib/src/securite/` (nouveau `sec_secours.dart`), export dans `sigh_domaine.dart`, vecteurs `packages/domaine/test/vecteurs/` + test.
- Ce qu'on fait : génération du code de 25 caractères sans caractères ambigus, empreinte, compteur de 5 essais et blocage 15 minutes, politique du mot de passe temporaire (14 caractères, 24 h) et du nouveau mot de passe (8 caractères au moins, différent du temporaire et de l'ancien). Fonctions pures, horloge injectée.
- Pièges à éviter : ne pas recopier la politique de mot de passe (réutiliser `accControlerNouveauMotDePasse`) ; le message de refus est identique que le compte existe ou non ; l'aléa est injecté pour que le test le rejoue.
- Vérification : `cd packages/domaine && dart test test/securite_secours_test.dart` → vert.
- Peut être livrée seule : oui.

### Étape 2 — État d'installation du poste (local, non synchronisé) [FAITE 02/11/2026]
- Fichiers : `lib/core/parametres_poste.dart`, `lib/core/etat_installation.dart` (nouveau).
- Ce qu'on fait : `EtatInstallation` (`non_installe`, `installe`), étapes cochées A à D, date et auteur de clôture ; stocké dans les paramètres du poste, jamais dans le magasin partagé. Détection « poste vide » = aucun paramètre d'installation ET aucun compte.
- Pièges à éviter : un poste qui a déjà des comptes (jeu de démonstration, test) ne doit pas retomber sur l'assistant ; `SIGH_CONNEXION=non` et les tests existants gardent leur chemin.
- Vérification : `flutter test test/installation_etat_test.dart` → vert ; `flutter test test/demarrage_poste_test.dart` → inchangé.
- Peut être livrée seule : oui.

### Étape 3 — Écran d'accueil à deux choix et première installation (création du compte administrateur)
- Fichiers : `lib/modules/auth/ins_ecrans.dart` (nouveau), `lib/modules/auth/acc_registre_sessions.dart` (routage), `lib/main.dart` (route de démarrage).
- Ce qu'on fait : écran autonome à deux choix ; formulaire du premier compte (identifiant, nom, mot de passe + confirmation, politique affichée) ; `ServiceIdentifiants.definir` sans changement obligatoire ; entrée de journal « Installation initiale » (RG-12) ; ouverture de session puis tableau de bord.
- Pièges à éviter : aucun mot de passe en clair écrit ni journalisé ; le provisoire aléatoire de `main.dart` n'est plus posé sur un poste vide installé de cette façon ; l'écran est absent dès que l'état est `installe` (adresse directe incluse, comme `/403`).
- Vérification : `flutter test test/installation_ecrans_test.dart` → vert (sondes : hash seul en base, journal, route fermée après installation).
- Peut être livrée seule : oui.

### Étape 4 — Code de secours à la création du compte, et chemin « J'ai perdu mon mot de passe administrateur »
- Fichiers : `ins_ecrans.dart` (affichage du code avec « Copier » et « Imprimer », case « je l'ai rangé » bloquante), `acc_ecrans.dart` (lien et écran de récupération), `core/identifiants.dart` (stockage de l'empreinte, consommation, nouveau code).
- Ce qu'on fait : le code s'affiche UNE fois ; l'empreinte seule est gardée ; l'écran de récupération prend identifiant, code, nouveau mot de passe ; le code est consommé et un nouveau est affiché ; 5 essais faux bloquent 15 minutes ; ne vaut que pour un compte administrateur. Message sans oracle d'existence du compte.
- Pièges à éviter : ne jamais écrire le code dans le journal ni dans `tentativesConnexion` ; l'impression passe par le gabarit A4 à entête unique (`P.etat` côté maquette, `impression/pdf.dart` côté poste) ; le poste dit avant de fermer l'écran du code que sans lui il n'y a aucun chemin d'urgence.
- Vérification : `flutter test test/installation_secours_test.dart` → vert (bon code, mauvais code ×5, blocage, rejeu du code consommé, compte non administrateur).
- Peut être livrée seule : oui (dépend des étapes 1 et 3).

### Étape 5 — Réinitialisation par un administrateur (compte utilisateur)
- Fichiers : `lib/modules/m14/utilisateurs.dart`, `m14/mot_de_passe.dart`, `core/identifiants.dart`.
- Ce qu'on fait : commande « Réinitialiser le mot de passe » (gardée par `K.commande`, absente sans droit) ; mot de passe temporaire de 14 caractères affiché une fois avec « Copier », valable 24 h ; changement obligatoire à la connexion suivante ; fermeture des sessions ouvertes du compte ; journal sans le mot de passe. Interdits : réinitialiser son propre compte par ce chemin, ou un super administrateur depuis un simple administrateur. Le lien « Mot de passe oublié ? » affiche « Contactez l'administrateur ».
- Pièges à éviter : `EcranMotDePasseOublie` existe, vérifier ce qu'il fait avant de le modifier (il ne doit promettre aucun e-mail) ; l'interdit d'auto-réinitialisation se contrôle au moteur, pas seulement par un bouton absent.
- Vérification : `flutter test test/installation_reinit_test.dart` et `flutter test test/identite_test.dart` → verts.
- Peut être livrée seule : oui.

### Étape 6 — Tableau de bord et modale « Configurations à faire »
- Fichiers : `lib/modules/auth/ins_modale.dart` (nouveau), tableau de bord de l'administrateur système, `lib/shell/` (pastille de réouverture).
- Ce qu'on fait : à la première ouverture du tableau de bord après installation, la modale s'ouvre seule ; étapes A (mère), B (liste des `cfg-*`), C (comptes dont le second administrateur), D (appairages) ; chaque ligne renvoie à l'écran existant, une étape dont la précédente manque est visible, non cliquable, avec son motif ; pastille pour la rouvrir ; ne se rouvre plus seule après la clôture.
- Pièges à éviter : le contenu de la liste B est celui des écrans `cfg-*` arbitré le 02/11 (Q7) ; ne pas ajouter de ligne sans écran existant ; utiliser les jetons de thème (fond de modale du design system), aucune couleur en dur.
- Vérification : `flutter test test/installation_modale_test.dart` → vert (ouverture automatique, ordre, ligne verrouillée avec motif, pastille).
- Peut être livrée seule : oui.

### Étape 7 — Activation de la mère en premier, reportable
- Fichiers : `ins_modale.dart`, `lib/mere/activation.dart` (réutilisé tel quel), `lib/mere/console.dart` (renvoi).
- Ce qu'on fait : l'étape A appelle `ActivationMere.activer` (relais, secret, clé de clinique) ; sur `relais_injoignable`, l'étape reste « reportée » avec le geste « réessayer » et la mention « mère non activée, rien n'est encore diffusé » ; les configurations saisies avant l'activation partent dans le journal à l'activation.
- Pièges à éviter : ne pas dupliquer la validation de l'activation ; la clé de clinique est affichée une fois pour séquestre papier (SPEC §158) ; le secret n'est pas conservé.
- Vérification : `flutter test test/mere_activation_test.dart` (existant) + `flutter test test/installation_activation_test.dart` → verts.
- Peut être livrée seule : oui.

### Étape 8 — Second administrateur obligatoire à la clôture, et clôture de l'assistant
- Fichiers : `ins_modale.dart`, `m14/utilisateurs.dart`, `core/etat_installation.dart`.
- Ce qu'on fait : la clôture est refusée tant qu'il n'existe pas au moins deux comptes administrateurs actifs, avec le motif nommé ; archivage seulement (RG-14) ; à la clôture, l'écran d'installation devient absent du ruban pour tout rôle sauf administrateur système ; date et auteur journalisés.
- Pièges à éviter : le contrôle se refait à l'archivage d'un administrateur après la clôture (on ne retombe pas sous deux sans le dire) ; le second administrateur reçoit son propre code de secours.
- Vérification : `flutter test test/installation_cloture_test.dart` → vert (un seul admin refusé, deux acceptés, archivage du second refusé).
- Peut être livrée seule : oui.

### Étape 9 — Rejoindre une clinique (fileul) et lecture seule des configurations
- Fichiers : `ins_ecrans.dart`, `lib/sync/moteur_fileul.dart`, `lib/modules/cfg/*` (lecture seule sur fileul), `lib/core/controleur_poste.dart`.
- Ce qu'on fait : saisie de l'adresse de la mère et du code d'appairage ; refus nommés (code expiré, déjà utilisé, mère injoignable, schéma incompatible, appareil déjà appairé) ; réception de l'instantané (configurations, comptes, droits) ; message « Configuration reçue de <mère>, version N » ; sur un fileul les écrans `cfg-*` sont en lecture seule et disent « réglé sur la mère » (droits résolus par le moteur, pas par un bouton masqué).
- Pièges à éviter : le haché Argon2id des comptes voyage avec l'instantané (Q3, arbitré) : à ajouter à la SPEC §3.7 ; un fileul doit refuser un schéma plus récent que le sien en le disant ; test de portée : créer les données APRÈS l'appairage.
- Vérification : `flutter test test/installation_fileul_test.dart` → vert ; `npm run banc:sync` à la racine → scénario de diffusion d'une configuration de la mère vers un fileul, hub coupé puis rétabli.
- Peut être livrée seule : non (dépend de l'activation et de l'instantané côté mère).

### Étape 10 — Documentation
- Fichiers : `docs/specs/SPEC-protocole-synchronisation.md` (§3.7 : le haché local est conservé), `docs/architecture/ECARTS-MAQUETTE.md`, `docs/guides/GUIDE-DEMARRAGE.md` (première installation), `docs/prd/PRD-POSTE-premiere-installation.md` (statut), `docs/prd/README.md`, `CLAUDE.md` (vague 71 : section de l'assistant).
- Ce qu'on fait : mettre à jour les statuts, consigner les écarts, retirer du guide l'usage de `SIGH_MDP_DEMO` hors développement.
- Vérification : `node --test` dans `packages/rbac` et `flutter test test/parite_ecrans_test.dart` → verts.
- Peut être livrée seule : oui.

## Schéma et données
- Pas d'incrément de `VERSION` de la maquette : aucun écran de la maquette ne change. Le code de secours et l'état d'installation sont des données LOCALES du poste (paramètres), non synchronisées.
- Seule donnée partagée nouvelle : l'empreinte du code de secours est une fiche du compte (collection `identifiants`, déjà locale au poste, haché Argon2id). Mesure à faire : taille de l'instantané de la mère avec les comptes (quota du poste).

## Synchronisation
- Configurations (`cfg-*`, `modulesActifs`, `rbac`) : fiche descriptive du référentiel ; un seul émetteur, la mère ; un fileul est en lecture seule.
- Comptes et hachés : fiches descriptives ; créés sur la mère ; archivés, jamais supprimés (RG-14).
- Code d'appairage : jeton à usage unique (8 caractères, 15 min).
- Invariants à vérifier au banc : une seule mère par clinique ; un code consommé ne se rejoue pas ; une configuration saisie avant l'activation part après elle.

## Persistance du poste (faite 02/11/2026, en fichiers)
Le magasin se range sur disque (`lib/donnees/persistance.dart`, `Magasin.brancherPersistance`). Fichiers en clair : voir E2104 à E2107 de `ECARTS-MAQUETTE.md`. La persistance chiffrée SQLCipher reste à faire avant des données réelles.

## Hors périmètre de ce plan
- Persistance chiffrée du poste (SQLCipher) : les fichiers actuels sont en clair ; préalable à toute donnée médicale réelle ; plan à part.
- Commande web de génération du code de secours : à vérifier dans `apps/web` avant de l'écrire dans un guide.
- Installeur signé et packaging.
- Contrôle de version de schéma complet entre mère et fileul : seule la détection d'incompatibilité est faite ici.

## Risques
| Risque | Signal précoce | Parade |
|---|---|---|
| Données en clair sur disque | audit de sécurité avant mise en service | SQLCipher avant toute donnée réelle ; ne pas déployer en clinique sur la persistance par fichiers |
| Code de secours perdu | demande de récupération sans code | écran qui le dit avant la fermeture ; case de confirmation bloquante |
| Divergence spec / décision sur les hachés | audit de la SPEC §3.7 | étape 10 |
| Régression du démarrage existant (tests, `SIGH_CONNEXION=non`) | `demarrage_poste_test` rouge | étape 2 : détection « poste vide » stricte |
| Fileul qui reçoit un schéma plus récent | erreur au chargement | refus nommé, geste « mettre à jour ce poste » |
| Bouton « Copier »/« Imprimer » non testé sur Windows | recette | recette Direction sur machine réelle |

## Définition de « fini »
`flutter analyze` sans erreur ; `flutter test` du poste, `dart test` du domaine, `npm run banc:sync` verts ; `parite_ecrans_test` à 100 % ; sondes : aucun mot de passe ni code en clair en base ni au journal ; recette Windows par la Direction (plein écran, logo, impression du code, appairage d'un second poste) ; CLAUDE.md et docs mis à jour.
