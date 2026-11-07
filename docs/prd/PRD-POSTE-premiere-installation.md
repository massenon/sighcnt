# PRD — Poste : première installation, activation de la mère et rejoindre une clinique
Statut : arrêté le 02/11/2026 par la Direction (Q1 à Q7) ; mis en œuvre le 02/11/2026, limites en `ECARTS-MAQUETTE.md` E2100 à E2121 ; Q2 et Q6 arbitrées aussi le 02/11/2026 (voir §10) ; plan : `docs/plans/PLAN-poste-premiere-installation.md`
Sources : demande de la Direction du 02/11/2026 ; `docs/specs/SPEC-protocole-synchronisation.md` §3 (appairage, EF-SYNC-16) ; `docs/architecture/adr/ADR-0005-*` ; `apps/poste/lib/mere/activation.dart` ; `apps/poste/lib/core/identifiants.dart` ; `CLAUDE.md` (RG-12, RG-13, RG-14, arbitrage « connexion par défaut » du 01/11/2026).

## 1. Problème
Aujourd'hui le poste Flutter démarre sur l'écran de connexion avec un jeu de démonstration en mémoire. Rien n'accompagne une VRAIE première installation : pas de création du premier compte, pas d'ordre imposé entre configuration, activation de la mère, appairage du relais web, des postes fileuls et des mobiles. Constat de terrain du 01-02/11/2026 : (a) aucun compte ne peut se connecter sur un poste neuf (aucun mot de passe défini) ; (b) l'installateur ne sait pas par quoi commencer ; (c) un second poste ne devrait pas avoir à refaire la configuration. S'y ajoutent deux défauts d'interface sur Windows : la barre des tâches est masquée (plein écran au démarrage) et le logo ne se voit pas.

## 2. Objectifs et non-objectifs
Objectifs (un critère de recette chacun) :
- O1. Un poste sans aucune donnée d'installation propose UNIQUEMENT deux chemins : « Première installation de la clinique » ou « Rejoindre une clinique existante ». Critère : aucun écran métier n'est atteignable avant l'un des deux.
- O2. La première installation crée le premier compte (administrateur système) avec un identifiant et un mot de passe CHOISIS par la personne, puis ouvre le tableau de bord avec une liste de configurations obligatoires. Critère : zéro mot de passe provisoire ni mot de passe commun.
- O3. Une configuration faite sur la mère n'est JAMAIS ressaisie sur un fileul ni sur un mobile. Critère : un fileul appairé affiche les mêmes référentiels, entête, modules actifs et droits que la mère, sans écran de configuration.
- O4. L'ordre est contraint par les dépendances (§4) et chaque étape dit ce qu'elle débloque. Critère : une étape dont la précédente manque est visible, non cliquable, avec son motif.
- O5. Barre des tâches visible par défaut, logo visible, ou cause nommée à l'écran. Critère : voir §5 EF-INST-10/11.
Non-objectifs : installeur signé et packaging (tâche à part), persistance chiffrée SQLCipher du poste (chantier à part), portail patient et cloud d'usage courant (CDCT §4.3), reprise des données papier.

## 3. Utilisateurs et rôles
| Rôle | Fait | Ne doit PAS voir (RG-13) |
|---|---|---|
| Installateur / administrateur système (premier compte) | tout l'assistant ; crée les autres comptes ; active la mère | rien d'interdit : son poste EST l'accès complet |
| Direction / DA | lit les configurations, valide ce qui est de son ressort | l'assistant d'installation (fermé après sa clôture) |
| Autres agents | se connectent avec leur compte | l'assistant, la console d'appairage |
| Poste fileul (machine) | rejoint, charge, copie | aucun écran de configuration locale |

Après la clôture de l'assistant, l'écran d'installation est ABSENT du ruban pour tout rôle sauf administrateur système (une commande interdite est absente, pas grisée).

## 4. Parcours
Poste « première installation » (devient la mère) :
1. Détection : aucun paramètre d'installation, aucun compte. Écran d'accueil à deux choix.
2. « Première installation » : nom du poste, création du compte administrateur système (identifiant, nom, mot de passe selon la politique existante, confirmation). Naît : fiche `utilisateurs` (role `admin`), haché Argon2id, entrée de journal « Installation initiale » (RG-12).
3. Ouverture directe du tableau de bord, avec la **modale « Configurations à faire avant l'utilisation »** (liste d'étapes cochables, fermable, rouvrable depuis une pastille).
4. Étape A, bloquante : **activation de la mère** = adresse du relais web, secret de la mère, clé de clinique (16 caractères au moins, séquestre papier sous scellé, SPEC §158). Le relais refuse une seconde mère. Naît : service de synchronisation, déclaration au relais, mode mère.
5. Étape B : configurations de la clinique (§5 EF-INST-04), saisies sur la mère APRÈS l'étape A : chacune est alors une opération de journal qui part vers le relais et les fileuls sans geste supplémentaire.
6. Étape C : comptes des autres agents (identifiant, rôle, fonction, secteur ; mot de passe provisoire généré, affiché une seule fois, changement obligatoire).
7. Étape D : appairage des postes fileuls et des mobiles : la console émet un code court (8 caractères, 15 min, usage unique), avec le profil et la fonction pour un soignant.
8. Clôture : la liste est validée, l'assistant se ferme, la date et l'auteur sont journalisés.

Poste « rejoindre » (fileul) :
1. Saisie de l'adresse de la mère et du code d'appairage (ou QR). Pas d'autre configuration.
2. La mère consomme le code, émet les jetons, envoie l'instantané filtré (référentiels, configurations, comptes, droits).
3. Le fileul affiche la page de connexion ; l'agent se connecte avec son compte déjà créé sur la mère.
4. Le poste dit « Configuration reçue de <mère>, version de schéma N » ; si la version est incompatible, il refuse en le disant (« mettre à jour ce poste »).

Mobile : appairé par la mère uniquement (code + clé de clinique), jamais de configuration locale.

## 5. Exigences fonctionnelles
- **EF-INST-01** Détection de première exécution et écran à deux choix. Source : demande 02/11. Acceptation : sur données vides, ni connexion ni écran métier ; sur données existantes, l'écran n'apparaît pas.
- **EF-INST-02** Création du premier compte administrateur choisi par l'installateur ; aucun mot de passe en clair écrit, aucun compte « demo ». RG-12. Acceptation : sonde sur la collection d'identifiants (hash seul) et le journal.
- **EF-INST-03** Tableau de bord + modale de configurations à faire, avec progression. Acceptation : après création du compte, la modale s'ouvre sans clic ; fermée, une pastille permet de la rouvrir ; elle ne se rouvre pas seule après la clôture.
- **EF-INST-04** Contenu de la liste B (PROPOSITION À VALIDER, dérivée des écrans de configuration de la maquette, non d'un document) : identité et entête légal de la clinique (`cfg-entetes`), activités actives (`cfg-modules`), tarifs et natures de facture (`cfg-tarifs`, `cfg-natures-facture`), paramètres comptables et exercice (`cfg-comptabilite`), paramètres MECeF (`mecef-config`), rôles et droits (`m14-roles`), sauvegarde. Chaque ligne renvoie à l'écran existant : aucun écran nouveau de saisie.
- **EF-INST-05** Contrainte d'ordre : B, C et D exigent A. Si le relais est injoignable, A peut être reportée : le poste travaille en autonome, la liste dit « mère non activée, rien n'est encore diffusé » et les configurations saisies partent dans le journal dès l'activation. Acceptation : refus nommé `relais_injoignable` (déjà existant) affiché avec le geste « réessayer ».
- **EF-INST-06** Diffusion : une configuration saisie sur la mère atteint le relais, les fileuls en attente et les mobiles par le journal d'opérations. Les fileuls « en attente » (non encore appairés) la reçoivent dans l'instantané de leur appairage. Acceptation : scénario de banc à deux postes (SYNC).
- **EF-INST-07** Un fileul ne propose AUCUN écran de configuration modifiable : les écrans `cfg-*` y sont en lecture seule et le disent (« réglé sur la mère »). Source : demande 02/11 (« pas besoin de configurations »).
- **EF-INST-08** Rejoindre : refus nommés pour code expiré, code déjà utilisé, mère injoignable, schéma incompatible, appareil déjà appairé. Source : SPEC §3 et SYNC-R18.
- **EF-INST-09** Mot de passe oublié (arbitrage Q4, 02/11/2026). Le lien « Mot de passe oublié ? » de la connexion affiche « Contactez l'administrateur » : aucune réinitialisation par e-mail.
  1. Utilisateur : un administrateur ouvre « Comptes utilisateurs » et choisit « Réinitialiser le mot de passe ». L'application génère un mot de passe temporaire de 14 caractères, affiché UNE fois avec « Copier », valable 24 h. À la connexion suivante, changement obligatoire (8 caractères au moins, différent du temporaire et de l'ancien) ; les sessions ouvertes du compte sont fermées.
  2. Chaque réinitialisation est journalisée (qui, quel compte, quand ; jamais le mot de passe). Compte du poste et compte du web sont distincts : changer l'un ne change pas l'autre.
  3. Un administrateur ne réinitialise ni son propre compte par ce chemin, ni celui d'un super administrateur s'il est simple administrateur.
  4. Administrateur sans autre administrateur : « J'ai perdu mon mot de passe administrateur » demande identifiant, code de secours de 25 caractères et nouveau mot de passe ; le code est consommé et un nouveau est affiché UNE fois. Après 5 essais faux, le chemin est bloqué 15 minutes, avec le même message que le compte existe ou non. Le code ne vaut que pour un compte administrateur ; l'application n'en garde que l'empreinte.
  5. Le code est créé à la création du premier compte administrateur (« Copier » et « Imprimer »), à ranger au coffre. Au poste, SANS le code il n'existe aucun chemin d'urgence (volontaire) : la réinstallation supprimerait les saisies non synchronisées. Le poste le dit avant que l'installateur ferme l'écran du code.
  6. Côté web (relais), la génération passe par une commande d'exploitation ; son existence et son nom dans `apps/web` sont à vérifier avant de l'écrire dans un guide (non établi ici).
- **EF-INST-10** Barre des tâches : le poste démarre MAXIMISÉ (barre des tâches visible), comme les logiciels de bureautique ; le vrai plein écran est un choix de l'agent (F11 et bouton de la barre supérieure). Arbitré le 02/11/2026 (Q1) ; remplace le plein écran forcé du 01/11. Fait : `SIGH_PLEIN_ECRAN` vaut `non` par défaut.
- **EF-INST-11** Logo : l'application affiche le logo dans la barre, la connexion et le verrou ; en cas d'échec de lecture, le monogramme remplace le logo ET la cause est écrite à l'écran de diagnostic, pas seulement dans la console. L'icône de la fenêtre et de l'exécutable Windows est celle de la clinique, non l'icône par défaut de Flutter. Fait le 02/11/2026 : `assets/img/logo.png` (converti du JPEG) et `windows/runner/resources/app_icon.ico` (7 tailles, 16 à 256 px). À vérifier sur le poste Windows.

## 6. Données
- Nouvelle collection locale de paramètres d'installation (état : `non_installe`, `installe`, étapes cochées, date et auteur de clôture) : donnée locale du poste, NON synchronisée (elle décrit CE poste). L'état « configuration reçue de la mère » est, lui, tiré de l'instantané.
- Collections existantes réutilisées : `utilisateurs`, identifiants (haché Argon2id), `modulesActifs`, `rbac`, référentiels `cfg-*`, `tentativesConnexion`.
- Incrément de `VERSION` seulement si une collection partagée est ajoutée (à trancher au plan).

## 7. Hors ligne et synchronisation (obligatoire)
| Donnée | Famille de fusion | Si deux postes agissent sans hub |
|---|---|---|
| Configurations (référentiels, entête, modules, droits) | fiche descriptive du référentiel | un seul émetteur légitime : la mère ; un fileul ne les modifie pas (EF-INST-07). Un conflit éventuel est nommé, jamais écrasé en silence |
| Comptes utilisateurs | fiche descriptive | créés sur la mère ; archivés, jamais supprimés (RG-14) |
| Activation de la mère | état local du poste + déclaration au relais | « une seule mère » tenue par le relais ; une seconde est refusée en le disant |
| Code d'appairage | jeton à usage unique (mère) | expire en 15 minutes ; rejeu refusé |
| État de l'assistant | local, non synchronisé | chaque poste a le sien |
Écran en suspens : un fileul sans mère joignable affiche « Hors ligne depuis N min », travaille sur sa copie, et le dit.

## 8. Impression et états
Aucune pièce imprimée, hormis (proposé) une fiche « Clé de clinique et identifiants d'installation » à imprimer et sceller, sans le mot de passe de l'administrateur. Format A4 avec l'entête officiel unique.

## 9. Ce qui n'est pas documenté / pas établi
- Le contenu exact de la liste B est une PROPOSITION : aucun document de cadrage ne fixe l'ordre de mise en service. À valider par la Direction.
- La cause du logo absent n'a pas été reproduite (pas de Windows ni de SDK Flutter dans l'environnement de rédaction) : le JPEG d'origine était valide. La Direction a demandé la conversion en PNG et en ICO, faite le 02/11/2026. Si le logo manque encore, la console de `flutter run` porte la ligne « Logo de la clinique illisible ».
- Politique de mot de passe de l'installateur, durée de conservation du séquestre papier de la clé de clinique : reprises de la SPEC, non rouvertes.
- Écart à lever : la SPEC dit « le mot de passe n'est jamais conservé, la mère vérifie à chaque synchronisation » alors que le poste vérifie un haché Argon2id local. Voir Q3.

## 10. Arbitrages
Rendus par la Direction le 02/11/2026 :
- Q1 Plein écran : démarrage MAXIMISÉ, barre des tâches visible, plein écran à la demande (F11). Arbitré.
- Q3 Mots de passe sur un fileul : le haché Argon2id local est CONSERVÉ et répliqué (travail hors ligne). Arbitré. Écart à reporter dans la SPEC §3.7 (« jamais conservé »), à corriger par ADR ou mise à jour de la spec.
- Q4 Mot de passe oublié : parcours EF-INST-09. Arbitré.
- Q5 Compte de l'installateur distinct du super administrateur du panneau web : OUI. Arbitré.
- Q7 Liste de configurations : celle des écrans `cfg-*` de la maquette (EF-INST-04). Arbitré.

- Q2 Ordre : la mère est activée AVANT les configurations ; l'activation est reportable si le relais est injoignable. Arbitré.
- Q6 Second administrateur : OBLIGATOIRE avant la clôture de l'assistant ; archivage seulement (RG-14). Arbitré.

Aucune question ouverte.
