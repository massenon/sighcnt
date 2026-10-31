# Modules complémentaires du poste mère

> Décision de la Direction du 30/10/2026 : **il n'existe pas de projet « mère » séparé du projet « fileul »**. Il y a **une seule application Flutter desktop** (`apps/poste`). Elle porte les **305 écrans** de la maquette. Sur le **serveur local de la clinique**, on **active le mode mère** : le même exécutable démarre en plus le service de synchronisation et affiche les **modules complémentaires** listés ci-dessous.
>
> **mère = les 305 écrans du fileul + les écrans de ses modules complémentaires.**

## 1. Ce que « activer le mode mère » veut dire

| Aspect | Décision |
|---|---|
| Où | Sur la machine serveur uniquement (un seul poste mère par clinique). |
| Comment | Réglage **à l'exécution** (assistant de première mise en service, puis page *Poste mère → Service*), pas une compilation différente. *État actuel du code : le mode se choisit encore par `--dart-define=SIGH_MODE` — à remplacer, tâche T9.* |
| Garde-fou | Un seul poste peut être mère : l'activation exige le **secret de la mère** (relais) et la **clé de clinique** ; si une autre mère est déjà déclarée active, l'activation est refusée en la nommant. |
| Ce qui démarre | Le service HTTP de synchronisation (`packages/sync_dart`), PostgreSQL local, le planificateur, la sauvegarde nocturne, la réplication chiffrée vers le relais. |
| Ce qui s'affiche en plus | Le groupe de menu **« Poste mère »** (les modules ci-dessous), réservé aux rôles `admin` et `da`. |
| Retour en fileul | Désactivation explicite (arrête le service, conserve les données) ; la bascule vers une autre machine passe par **restauration** (module M-07), jamais par copie de fichiers. |

Les écrans du fileul fonctionnent à l'identique sur la mère : la mère **est aussi un poste de travail** (la DAF y encaisse, y compte, y signe).

## 2. Liste des modules complémentaires

Légende : ✅ écran déjà écrit et testé · 🟡 service existant, écran à écrire · ⬜ ni l'un ni l'autre.

### A. Exploitation de la synchronisation

| Id | Module | Contenu | Service | Écran |
|---|---|---|---|---|
| M-01 | **Supervision** | Santé globale ; contrôles : base, disque, sauvegarde, relais, postes silencieux, dérive d'horloge, intégrité, conflits, erreurs internes. « Inconnu » ne rassure jamais. | ✅ | ✅ |
| M-02 | **Appareils et appairage** | Liste des postes et mobiles (dernier contact, retard, dérive) ; code d'appairage à usage unique ; code mobile + **clé de clinique en QR** ; révocation ; déblocage d'un appareil bloqué. | ✅ | ✅ (QR de la clé : ⬜) |
| M-03 | **Conflits et doublons** | Conflits de champ (garder A / B), « doublon possible » (classer), historique des décisions. | ✅ | ✅ |
| M-04 | **« À traiter » consolidé** | Toutes les opérations refusées, tous appareils confondus, avec la cause nommée et le geste de correction ; relance ciblée. | 🟡 | ⬜ |
| M-05 | **Journal des opérations** | Explorateur par séquence (`seq`), par appareil, par fiche ; curseurs par appareil ; **« Renvoyer vers tous »** (resync) avec accusés par poste. | 🟡 | ⬜ |
| M-06 | **Plages de numéros et baux de stock** | Plages de codes patients allouées par appareil (consommation, épuisement, numéros PROV- à réconcilier) ; baux de stock par article (alloué / consommé / restitué). | 🟡 | ⬜ |
| M-07 | **Lots de tournée (mobiles)** | Composer le lot du jour d'un soignant (dossiers), durée de validité, suivi des expirations, ce qui reste à envoyer sur le téléphone. | 🟡 | ⬜ |

### B. Sécurité et continuité

| Id | Module | Contenu | Service | Écran |
|---|---|---|---|---|
| M-08 | **Journal technique** | Évènements de la mère (erreurs, alertes, démarrages), filtrables, exportables. | ✅ | ✅ |
| M-09 | **Sauvegardes et restauration** | Sauvegarde à la demande, planning, conservation, **vérification de restauration** (test à blanc) ; restauration depuis le journal du relais avec la clé de clinique ; remplacement de la mère par une autre machine (reprise après sinistre). | 🟡 (sauvegarde ✅, restauration CLI ✅) | ⬜ |
| M-10 | **Clé de clinique** | Génération, empreinte de contrôle, **export papier sous scellé** (détenteur à désigner), QR d'appairage mobile, rotation. La clé n'est jamais envoyée au relais. | 🟡 | ⬜ |
| M-11 | **Intégrité et altérations** | Enveloppes altérées ou manquantes (authentification GCM, trous de rang), appareils bloqués, décision de l'administrateur. | ✅ (alertes) | 🟡 (liste dans Supervision) |
| M-12 | **Réinitialisation de production** | Fenêtre d'ouverture, second profil de confirmation, sauvegarde préalable, incrément d'époque, export des opérations non envoyées. | ✅ | ✅ (Maintenance) |

### C. Liaison avec le relais en ligne

| Id | Module | Contenu | Service | Écran |
|---|---|---|---|---|
| M-13 | **Relais** | État de la liaison, retard de réplication, dernier battement, secret de la mère (rotation), appairage mère ↔ relais, journal des échanges. | 🟡 | ⬜ |
| M-14 | **Indicateurs publiés** | Ce que la mère publie au relais (compteurs **sans aucun nom de patient**), fréquence, aperçu exact de ce qui part. | 🟡 | ⬜ |

### D. Plateforme locale

| Id | Module | Contenu | Service | Écran |
|---|---|---|---|---|
| M-15 | **Service et démarrage** | Activation/désactivation du mode mère ; démarrage automatique (service Windows / systemd) ; ports ; arrêt propre ; fichiers de configuration. | ⬜ | ⬜ |
| M-16 | **Base de données locale** | PostgreSQL : état, taille, version de schéma, migrations appliquées, vérification de parité (tables ↔ magasin). | 🟡 (parité ✅ dans la maquette) | ⬜ |
| M-17 | **Réseau local** | Adresse(s) de la mère, test d'accessibilité depuis un poste, certificat TLS du réseau local, pare-feu (aide). | ⬜ | ⬜ |
| M-18 | **Planificateur** | Les 6 tâches de la maquette (échéances fiscales, seuils de stock, péremptions FEFO, rendez-vous du lendemain, créances âgées, sauvegarde) : état, dernière exécution, exécution manuelle ; **elles lisent, n'écrivent pas les collections** (les postes réécrivent les leurs). | 🟡 (PHP → Dart) | ⬜ |
| M-19 | **Notifications serveur** | Alertes ouvertes routées **par rôle au serveur** (RG-13), résolution automatique quand la cause cesse, source de la cloche des postes. | 🟡 | ⬜ |

### E. Cycle de vie

| Id | Module | Contenu | Service | Écran |
|---|---|---|---|---|
| M-20 | **Assistant de première mise en service** | Identité de la clinique, premier administrateur, jeu de départ (essentiels ou démonstration), activation du mode mère, premier appairage. | ⬜ | ⬜ |
| M-21 | **Mises à jour et compatibilité** | Version de schéma et de l'application par poste ; refus nommé d'un poste trop ancien ; déploiement planifié. | ⬜ | ⬜ |
| M-22 | **Import de migration** | Import SAGE / classeurs / jeux de départ (`source`, `import_batch`, `validated_by`), jamais de saisie manuelle. | 🟡 | ⬜ |

**Bilan : 22 modules complémentaires — 5 écrans faits (M-01, M-02, M-03, M-08, M-12) ; 17 à écrire.**

## 3. Ce qui existe déjà dans les 305 écrans et NE DOIT PAS être dupliqué

La maquette porte déjà des écrans d'administration **qui lisent les services du serveur** : `m14-utilisateurs`, `m14-roles`, `m14-soignants`, `m14-sessions`, `m14-audit`, `m14-sauvegardes`, `m14-taches`, `cfg-systeme`. Ils font partie des 305 écrans et se portent comme les autres (tranche 6). Les modules ci-dessus sont ceux qui n'ont **aucun équivalent** dans la maquette parce qu'elle n'avait ni appareils, ni relais, ni journal d'opérations. Là où un écran de la maquette et un module de la mère se recouvrent (`m14-sauvegardes` ↔ M-09, `m14-taches` ↔ M-18, `m14-sessions` ↔ M-02), **le module de la mère étend l'écran du fileul** (un onglet de plus), il ne le remplace pas.

## 4. Services de la maquette que le mode mère remplace

| API PHP de la maquette | Devient, sur la mère |
|---|---|
| `api/magasin.php`, `api/crud.php` | Journal d'opérations + vue des fiches (`packages/sync_dart`) |
| `api/session.php`, `api/auth.php` | Appairage d'appareils + sessions d'agents (jetons serveur) |
| `api/evenements.php` | Sondage par curseur (journal) — pas de SSE |
| `api/notifications.php`, `api/cron.php` | Modules M-18 et M-19 |
| `api/projection.php`, `api/parite.php` | Module M-16 |
| `api/restaurer.php` | Module M-09 |
