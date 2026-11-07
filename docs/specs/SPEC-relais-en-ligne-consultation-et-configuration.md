# SPEC : Relais en ligne (option A), consultation à règles complètes, instantané de configuration et conservation intégrale

Statut : **proposé le 07/11/2026**, sous réserve de la décision Q1 du PRD (`docs/prd/PRD-RELAIS-en-ligne-consultation-et-configuration.md`). Cette spec décrit l'**option A** (relais opaque, règles dans le navigateur). Si la Direction retient B, cette spec est caduque et une ADR de renversement est écrite d'abord.
Règle de rédaction : pas de tiret cadratin comme ponctuation. Un refus se nomme (code, motif, geste) ; une commande interdite est absente ; « non calculable » n'est pas zéro.

## 1. Composants

| Composant | Rôle | Nouveauté |
|---|---|---|
| Mère (poste, mode mère) | autorité de la configuration et de l'état consolidé ; seule à publier la copie et les instantanés | publication quasi continue, instantané de configuration, archive froide |
| Relais (`apps/web`) | stocke et sert des enveloppes chiffrées ; ne connaît ni clé ni donnée | conservation intégrale, point d'accès instantanés, restauration assistée |
| Client de consultation web | déchiffre dans le navigateur, applique le domaine Dart et `rbac.json`, affiche | **nouveau** : Flutter web ou PWA, mêmes règles que le poste |
| `packages/domaine` | règles pures, vecteurs | compilé pour le web ; banc des vecteurs sur le web |

## 2. Contrats du relais (nouveautés, sens `copie` et `config`)

Toutes les enveloppes gardent la forme existante : AES-256-GCM, `aad = id|appareil|dir|n`, rang contigu `n`, le relais ne voit que `appareil`, `dir`, `n`, nonce, taille.

- `dir = copie` : lots de copie (existant). **Cadence** : un lot par 5 secondes au plus (au lieu de 30), reprise sur échec, jamais de perte (rang contigu).
- `dir = config` (**nouveau**) : instantané de configuration. Contenu chiffré : `{version, creeLe, auteur, collections: {nom: [fiches]}, empreinte}`. Le relais ne voit ni les noms de collections, ni leur nombre. Une nouvelle version à chaque changement de la configuration ; **toutes les versions sont conservées**.
- `GET /releve?dir=copie|config&apres=n` : lecture ordonnée ; `GET /compteur` : rang courant par sens et date du dernier dépôt de la mère (sert à l'âge de la donnée).
- **Archivage** : `POST /mere/archiver {avantRang, motif}` (clé d'appareil de la mère, rôle admin à la console) déplace les enveloppes antérieures vers l'**archive froide** (fichiers compressés, hors du chemin de lecture). **Jamais de suppression** ; `POST /mere/desarchiver` annule. Le contrôle de rangs contigus s'étend à l'archive.
- Aucun endpoint ne rend un contenu déchiffré. Le relais n'embarque **aucune règle métier**.

## 3. Instantané de configuration

**Périmètre « sans exception » (v1).** Toute collection de `S.COLLECTIONS_ESSENTIELLES` (paramétrage, référentiels, comptes, droits, modules, catalogues, règles datées, modèles) **plus** : matrice RBAC (`rbac`), modules actifs, configuration fiscale par versions (`identiteLegale`, `obligationsFiscales`, `historiqueObligations`), identité et branding, paramètres de notifications et de rappels, réglages SMS et SMTP **non secrets**, plages de codes allouées, personnel (sans salaire, voir `CHAMPS_DE_TEST_CONSERVES`), organigramme, tarifs, actes, catalogues de laboratoire et d'imagerie, régimes et grille des primes datés, barème NS 131.
**Secrets** (Q3) : hachés de comptes et empreinte du code de secours **dans** l'instantané, chiffrés ; mots de passe SMTP et clés des fournisseurs SMS **jamais** dans l'instantané (ils restent au coffre du relais, qui en a l'usage, chiffrés par la clé d'application).
**Famille R** : la configuration ne descend jamais aux mobiles (RG-13) ; le journal de chaque appareil mobile reste inchangé.
**Déclencheur** : la mère dépose un instantané à chaque écriture d'une collection du périmètre, au plus un par 5 secondes (regroupement), plus un instantané complet quotidien.
**Empreinte** : SHA-256 de la sérialisation canonique ; chaque instantané porte l'empreinte du précédent (chaîne), pour détecter une version manquante sans clé.

## 4. Restauration depuis le relais seul

Procédure de la console de la mère neuve (admin et DA, clé de clinique et code de secours) :
1. Contact du relais, appairage comme mère de remplacement (la garde « une seule mère » reste : l'ancienne est révoquée explicitement, motif obligatoire).
2. Lecture du **dernier instantané de configuration** puis du **journal de chaque famille sans exception**, dans l'ordre global `[nOps, hlc, appareil, idOp]` (spec de synchronisation).
3. Reconstruction de l'état ; calcul de l'empreinte ; comparaison avec l'empreinte publiée.
4. Refus nommés : `CLE_INCORRECTE` (échec d'authentification GCM), `RANG_MANQUANT` (trou dans une chaîne, avec le rang), `EMPREINTE_DIVERGENTE` (état rejoué différent), `MERE_ACTIVE` (une mère encore active sans révocation).
5. Sauvegarde préalable automatique de l'état local (non désactivable) ; journalisation RG-12.

## 5. Client de consultation web

- **Accès** : connexion nominative (compte et rôle renvoyés par le relais) ; clé de clinique saisie (v1 superadmin) ou fournie enveloppée par compte (P1) ; la clé vit **en mémoire de l'onglet seulement**, effacée après inactivité (CSP sans script externe, pas de `localStorage`).
- **Règles** : le client importe le domaine Dart compilé pour le web ; chaque écran consultable déclare sa fiche (`docs/architecture/ecrans/<id>.json`) ; les droits viennent de `rbac.json` (même fichier que le poste) ; RG-13 est appliqué avant tout rendu (les collections hors droit du rôle ne sont **pas même reconstruites** en mémoire).
- **Âge** : bandeau permanent : « mise à jour il y a N s » (compteur du relais) ; si la mère n'a rien déposé depuis plus de 60 s : « source injoignable depuis HH:MM » (ton attention) ; aucun état « en ligne » sans cette mesure.
- **Rafraîchissement** : sondage du compteur toutes les 5 secondes avec ETag ; relève des seuls rangs nouveaux ; jamais de rechargement complet.
- **Lecture seule** : aucune commande d'écriture n'existe dans le client (absentes, pas grisées).
- **Journal** : ouverture, écran consulté, export, déconnexion : RG-12, sans contenu.

## 6. Fichiers et zones touchés (aperçu)

`apps/web` (contrôleurs relais, migration des archives, console, tests), `apps/poste/lib/sync` (publication, instantané, restauration), `packages/sync_dart` (`copie_mere.dart`, `pont_pair.dart`), `packages/domaine` (compilation web, vecteurs), nouveau `apps/consultation` (client web), `docs/architecture` (parité du client).

## 7. Sondes (banc)

1. **Parité web** : les vecteurs du domaine rejoués dans le client web (navigateur sans tête) : zéro divergence ; mutation d'une règle du domaine fait échouer le client.
2. **Opacité** : base du relais interrogée : aucune donnée ni nom lisible (entropie), y compris pour les enveloppes `config`.
3. **Conservation** : N instantanés puis archivage puis désarchivage : aucun rang manquant, chaîne intacte.
4. **Restauration** : état source, mère neuve, empreinte identique ; mutation d'une enveloppe : `EMPREINTE_DIVERGENTE` ou `CLE_INCORRECTE` nommé.
5. **Âge** : mère arrêtée : bandeau « source injoignable » ; mère relancée : retour à la normale sans doublon.
6. **RBAC** : rôle sans droit : écran absent, collection non reconstruite, adresse directe refusée.
7. **Cadence** : un lot toutes les 5 secondes au plus sous charge ; aucune perte à la coupure (reprise).
8. **Quota** : mesure de la croissance par jour d'activité simulée ; alerte avant saturation.

## 8. Ce qui ne peut pas être vérifié ici

L'espace réel de l'hébergement mutualisé, la latence réseau réelle depuis le Bénin, le comportement du navigateur des consultants, et le compilateur web du domaine tant que le banc des vecteurs n'a pas tourné sur le web.
