# SPEC — Protocole de synchronisation : poste mère, postes fileuls, mobiles et relais en ligne

| | |
|---|---|
| **Statut** | brouillon 29/10/2026 — conditionné à l'acceptation d'ADR-0005 (révision 3) · **banc de référence : `packages/sync/banc/` (SYNC-R1→R5, R7, R9, R12, R14, R16→R21 : 72 vérifications vertes)** |
| **Sources** | `PRD-SOCLE-synchronisation-bidirectionnelle` (EF-SYNC-01→20, familles A–D), `PLAN-synchronisation-bidirectionnelle`, ADR-0001, ADR-0005, `DICTIONNAIRE-DONNEES.md`, `CLAUDE.md` (RG-01→14) |
| **Ce document ne remplace pas le PRD** | il fixe **comment** (acteurs, messages, états, écrans). Les exigences restent celles du PRD ; chaque section cite la référence EF-SYNC qu'elle réalise. |
| **Valeurs numériques** | marquées *(proposé)* : aucune n'est tirée d'un document de cadrage ; à valider au banc |

## 1. Acteurs et protocoles

| Acteur | Rôle | Base | Autorité ? |
|---|---|---|---|
| **Poste mère** | Service Dart + console. Reçoit, ordonne, applique les règles, redistribue, écrit le PostgreSQL local, pousse vers le relais | PostgreSQL local | **Oui, la seule** |
| **Poste fileul** | Application desktop complète (tous les modules autorisés) | SQLite chiffré | Non |
| **Mobile** | Application minimale : consultation, constantes, **consultation à domicile**, et **module Réception de secours** (§11). **Jamais sur le réseau local** : il passe toujours par le relais | SQLite chiffré | Non |
| **Relais en ligne** | Laravel sur cPanel : stockage opaque, indicateurs, panneau superadmin, cron | PostgreSQL en ligne | Non, jamais |

| Protocole | Entre | Transport | Contenu |
|---|---|---|---|
| **P1** | fileul / mobile ↔ mère | HTTPS sur le réseau local | opérations **en clair** (réseau interne) |
| **P2** | mère ↔ relais | HTTPS sortant depuis la mère | **enveloppes chiffrées de bout en bout** ; la mère est le seul client du relais en fonctionnement normal |
| **P3** | mobile ↔ relais (**seule voie du mobile**, données mobiles ou Wi-Fi extérieur) | HTTPS | enveloppes chiffrées uniquement, **par boîte aux lettres d'appareil** ; la mère les relève et y dépose ce qui est destiné au mobile |

**Règle de topologie** : un poste synchronise avec **un seul** point à la fois ; la liste d'adresses de sa configuration est ordonnée (mère locale, puis relais). Un fileul n'utilise le relais que si la mère est injoignable *et* que sa configuration l'y autorise ; **un mobile n'utilise que le relais**. Aucune autorité n'existe en dehors de la mère.

## 2. Identités

- **UUID d'appareil** : tiré à la première ouverture, jamais modifié, jamais réutilisé. **Le nom du poste est une étiquette**, pas une clé (une réinstallation donne un nouvel UUID ; le nom peut être repris).
- **UUID de mère** et **marque d'époque** (`epoch`) : entier incrémenté **uniquement** par une restauration ou une bascule d'autorité décidées par un administrateur. Chaque opération porte l'époque de l'appareil ; une époque inconnue est **refusée** (voir §10) pour que d'anciennes données ne ressuscitent pas.
- **Identifiants de fiche** : UUID v7 créés par l'appareil. Les **numéros métier** (code patient RG-01, pièces, code d'analyse) sont **distincts** de l'identifiant technique (§8).

## 3. Appairage (EF-SYNC-16)

1. L'administrateur ouvre, **sur la console de la mère**, « Appairer un appareil » : choix du rôle, de l'étiquette, du périmètre. La mère génère un **code court à usage unique** *(proposé : 8 caractères, sans caractères ambigus, valable 15 min)*.
2. Sur l'appareil neuf : saisie du code + adresse de la mère (ou balayage d'un QR). L'appareil envoie son **UUID**, sa plateforme, sa version.
3. La mère **consomme le code** (il ne sert qu'une fois), crée la fiche appareil, émet un **jeton d'appareil** et un **jeton de renouvellement**. Le jeton n'est jamais conservé en clair côté mère : seul son **haché** l'est.
4. **Rotation** *(proposé : jeton d'accès 24 h, renouvellement 30 jours, roulant)* ; un renouvellement rejoué après usage **révoque** l'appareil (vol de jeton présumé).
5. **Table `appareils`** : UUID, étiquette, rôle, plateforme, version, état (`en_attente` · `actif` · `suspendu` · `révoqué`), dernier contact, dernier `seq` acquitté, retard, version du schéma local, empreinte de la clé publique.
6. **Révocation** par la console : au prochain contact l'appareil reçoit **401** `appareil_revoque`, **suspend** sa synchronisation, conserve ses données locales (il ne les purge pas seul), affiche l'état et propose « se reconnecter » (nouvel appairage).
7. **Mot de passe** : jamais conservé. Un **code PIN local** rouvre la session hors ligne ; l'authentification utilisateur est vérifiée par la mère à chaque synchronisation.
8. **Appairage au relais** : la mère est appairée au relais (code émis depuis le panneau en ligne, saisi sur la console). **Un mobile est appairé par la mère** : le code est émis sur la console, saisi sur le téléphone **avec la clé de clinique** (QR affiché sur la console, à scanner), puis la mère déclare l'appareil au relais et lui ouvre sa boîte aux lettres.

## 4. Le journal d'opérations (EF-SYNC-01, 05)

**Une opération** = un geste d'écriture. Champs : `id` (UUID v7), `appareil`, `utilisateur`, `epoch`, `hlc` (horloge logique hybride), `collection`, `fiche`, `type` (`creer` · `modifier` · `archiver` · `restaurer`), `champs` (valeurs **par champ** modifié), `version_base` (version de fiche vue par l'appareil), `famille`, `cle_idempotence` (= `id`), `schema` (version du dictionnaire).

- **Jamais de suppression physique** : « supprimer » produit `archiver` ; un appareil n'applique ni n'émet de suppression (RG-14, EF-SYNC-08). Les référentiels de structure (chambres, lits, ambulances) s'archivent mais ne disparaissent jamais de l'historique.
- **`seq`** : la mère attribue un numéro de séquence croissant, sans trou, **à l'acceptation**. Il est la **seule** référence d'ordre du serveur ; l'horloge murale d'un poste n'est jamais l'ordre (EF-SYNC-20).
- **Application locale d'abord** : l'écriture est visible immédiatement chez l'émetteur et placée dans la file (EF-SYNC-02).

### Les quatre familles du PRD, et les cinq règles déjà présentées à la Direction

| Famille PRD | Règle | Correspond à… |
|---|---|---|
| **A. Fiche descriptive** | fusion par champ ; même champ des deux côtés → conflit nommé | « dernier geste » (champs sans enjeu) **et** « référentiels » (la mère seule écrit : un poste ne modifie pas un référentiel, il le demande) |
| **B. Journal append-only** | union, jamais de modification | « ajout seul » |
| **C. Pièce émise immuable** | aucune fusion ; correction = nouvelle pièce liée | factures normalisées, avoirs, écritures validées, comptes rendus validés |
| **D. Agrégat à invariant** | la mère **rejoue et vérifie** ; l'opération qui viole l'invariant est refusée **en le nommant** | « invariants » (stock, lit, exercice clos) **et** « numéros » (plages réservées, §8) |

Chaque collection du dictionnaire porte **une** famille ; une collection sans famille est refusée à la génération du schéma (EF-SYNC-06).

## 5. Envoi : poste → mère (EF-SYNC-03, 04)

1. **On reçoit toujours avant d'envoyer** : un appareil effectue un tirage (§6) avant tout envoi.
2. **File persistée** (SQLite) : survit à la fermeture, au redémarrage, à la coupure de courant. États d'une opération : `en_attente` → `envoyée` → `acceptée` | `fusionnée` | `refusée`.
3. **Lot** : jusqu'à *(proposé)* 200 opérations, **dans l'ordre de la file**, envoyées en une requête ; la mère les traite **dans une seule transaction**.
4. **Idempotence** : un lot renvoyé (réponse perdue) ne crée aucun doublon — la mère reconnaît `id` et renvoie le résultat déjà calculé.
5. **Accusé** : la mère répond **pour chaque opération** : `acceptée(seq)` · `fusionnée(seq, détail)` · `refusée(code, motif lisible, geste de correction)`. L'appareil marque « envoyée » **seulement après l'accusé**.
6. **Refus** : il devient une ligne de l'écran **« À traiter »** de l'appareil (cause nommée, geste proposé : corriger, abandonner, demander arbitrage). Une opération refusée **bloque** les opérations qui en dépendent (même fiche) et **ne bloque pas** les autres.
7. **Reprise** : coupure en cours de lot → au retour, renvoi du même lot. Réessais avec *(proposé)* attente croissante 2 s → 5 min, **sans abandon** : un appareil n'abandonne jamais une opération ; l'administrateur voit l'âge de la plus ancienne.
8. **Pastille** permanente : synchronisé · en cours · en retard (âge) · hors ligne · **suspendu** (révoqué) · **à traiter (n)** (EF-SYNC-14).

## 6. Réception : mère → postes (EF-SYNC-05, 12, 17)

- **Curseur par appareil**, donné par le serveur (`seq`), **jamais par l'horloge du poste**. Requête : « tout après `seq` = N », par **pages** *(proposé : 500 opérations)*.
- **Filtre de lecture appliqué par la mère** : un appareil ne reçoit que les collections et fiches que son rôle peut lire (RG-13, EF-SYNC-12) ; le **périmètre** d'un mobile est plus étroit encore (§11).
- **Un dossier accepté reste visible en continu** : tant qu'une opération acceptée par la mère n'est pas revenue dans le flux (`seq` > curseur), l'appareil la **superpose** à son état confirmé, avec le numéro réel attribué par la mère ; sans cela, un dossier créé disparaît de l'écran entre l'accusé et le tirage suivant (défaut relevé par le banc, SYNC-R21).
- **La mère refuse tout envoi d'une époque inconnue**, que l'appareil ait tiré ou non avant d'envoyer (§10).
- **Jamais d'écrasement d'une saisie en attente** : l'appareil applique les opérations reçues, puis **rejoue par-dessus** ses opérations locales non envoyées (rebase) ; si l'une devient impossible (fiche archivée, champ modifié ailleurs), elle devient un conflit nommé, pas un écrasement.
- **Appareil neuf ou réinstallé** : appairage, puis **instantané** (filtré par rôle), puis flux (EF-SYNC-17). Un instantané se reconstruit depuis le journal.
- **Données chaudes** (EF-SYNC-17) : toutes les **identités** des patients, plus les dossiers hospitalisés, vus depuis 24 mois *(proposé)*, rendez-vous à venir ; le reste **à la demande** quand la mère répond ; hors ligne, un dossier absent affiche **« non disponible hors ligne »**, jamais un écran vide.
- **Fichiers** (scans, clichés, GED) : synchronisés **à part**, par empreinte SHA-256, métadonnées d'abord, binaire ensuite avec reprise (EF-SYNC-18).

## 7. Propagation automatique et « Renvoyer »

- **La mère ne contacte jamais un poste** : elle dépose l'information, l'appareil vient la chercher.
- **Réseau local** : interrogation **toutes les 3 s** *(proposé ; déjà éprouvé à la maquette, délai mesuré < 8 s)* avec réponse vide très légère quand rien n'a changé ; un flux serveur (SSE) peut s'y ajouter plus tard sans changer le protocole. Le **relais** n'est interrogé que toutes les *(proposé)* 30 s.
- **L'événement ne porte jamais de contenu** : seulement « collection X a changé, `seq` N ».
- **Le relais ne contacte jamais la mère** (elle est derrière le routeur de la clinique, aucun port n'est ouvert) : **c'est la mère qui vient relever le relais** toutes les *(proposé)* 10 à 15 s, par une requête très légère (« y a-t-il du nouveau depuis `seq` N ? »). Du point de vue de l'utilisateur, la remontée d'un mobile vers la mère est **automatique** ; le délai est celui de cette relève, auquel s'ajoute celui de la distribution aux fileuls (3 s).
- **Réveil des mobiles** : notification poussée (FCM) **sans donnée de santé** (« une mise à jour est disponible ») ; sans elle, le mobile relève sa boîte à l'ouverture et à intervalle. FCM n'existe pas sur le desktop : **la mère et les fileuls n'en dépendent jamais**.
- **« Renvoyer vers ce poste » / « vers tous »** (console) : la mère pose une **demande de resynchronisation** (marque datée) ; chaque appareil la voit au prochain tirage, effectue un **tirage complet** de son périmètre et l'**acquitte** ; la console montre qui a acquitté et qui est en retard.

## 8. Invariants (famille D — EF-SYNC-09, 10, 13)

| Objet | Mécanisme |
|---|---|
| **Stock (RG-03)** | **Un seul écrivain par zone** : le stock d'un magasin n'est écrit que par le poste qui en est responsable. Quand deux postes doivent sortir du même stock, la mère leur alloue un **quota par article (bail)**, consommable hors ligne, renouvelé à la reconnexion. Jamais de stock négatif ; une sortie hors bail est refusée en nommant l'article |
| **Lit occupé** | réservation par service ; une admission sur un lit déjà occupé est refusée à l'arrivée et devient une tâche |
| **Numéros (RG-01 et pièces)** | plages réservées **par poste** ; plage épuisée hors ligne → **numéro provisoire** réconcilié à l'arrivée sans modifier un numéro déjà attribué |
| **Numéro fiscal (MECeF)** | issu **toujours du boîtier**, branché à la **caisse** ; la file MECeF est distincte du journal d'opérations ; la facture se synchronise **après** certification |
| **Exercice clos** | une écriture dans un exercice clos est refusée au moteur de la mère |
| **Équilibre comptable (RG-10)** | une pièce déséquilibrée est refusée à l'arrivée |

## 9. Conflits (EF-SYNC-15)

- **Détection** : même champ modifié sur deux appareils depuis la même `version_base` ; opération sur fiche archivée ; violation d'invariant ; schéma incompatible.
- **Jamais de « dernier gagne » muet** sur une fiche descriptive : soit fusion par champ (champs différents), soit **conflit nommé**.
- **Enregistrement** : table `conflits` — fiche, versions A et B, auteurs, heures, famille, état (`ouvert` · `tranché`), décision, décideur, date.
- **Écran « Conflits à régulariser »** sur la **console de la mère** (l'arbitre est la DAF ou l'administrateur) : filtre par famille et par poste, vue côte à côte, décisions *garder A*, *garder B*, *fusionner champ par champ*, *refaire par une nouvelle pièce*. **Les conflits financiers** (pièces C, soldes de caisse) exigent le rôle de la DAF et laissent une trace d'audit (RG-12).
- **La décision est une opération** : elle se synchronise comme toute autre et réaligne l'appareil perdant.
- **Les conflits ne vont pas au relais en clair** : ils contiennent des données de santé ; le panneau en ligne n'en montre que le **nombre** et l'âge.

## 10. Marque d'époque, réinitialisation, restauration

- **Réinitialisation en production : autorisée** (décision de la Direction du 29/10/2026 : on doit pouvoir tester en production puis revenir à un état neuf). **Vider comme neuf en gardant ce qui fait fonctionner le logiciel.** Garde-fous retenus, parce que le geste est **irréversible pour l'exploitation** :
  - **Interrupteur fermé par défaut**, comme à la maquette : l'administrateur ouvre une **fenêtre limitée** *(proposé : 24 h)* ; fermé, la commande est **absente**, pas grisée.
  - **Double confirmation** (saisie du nom de la clinique) **et** accord d'un **second profil** (DAF ou Direction) — le geste ne repose pas sur une seule personne.
  - **Sauvegarde préalable automatique et non désactivable**, conservée *(proposé : 30 jours)* : elle **permet de défaire** par la procédure de restauration ci-dessous.
  - **Ce qui est conservé** : la liste `COLLECTIONS_ESSENTIELLES` de la maquette (paramétrage, référentiels, comptes, droits RBAC, modules actifs, catalogues du laboratoire et de l'imagerie, tarifs et grilles, règles datées, modèles). **Ce qui est vidé** : l'activité (patients, consultations, factures, stocks mouvementés, écritures, journaux d'activité). La liste est **une donnée du dictionnaire**, pas du code.
  - **Trace** : l'événement est la première entrée du journal neuf (RG-12) avec auteur, second profil, date, empreinte de la sauvegarde.
  - **Propagation** : la réinitialisation incrémente `epoch`. Chaque appareil, à son prochain contact, **exporte ses opérations non envoyées dans un fichier chiffré** (elles ne ressuscitent pas), purge ses données d'**activité**, **garde** ses essentiels, puis tire le nouvel état. Le relais retient la sauvegarde préalable et **ignore** les enveloppes d'époque antérieure. La console affiche qui a acquitté.
  - **Mobile** : il est purgé au prochain contact ; tant qu'il est hors réseau il garde son lot chiffré (limite §11).
- **Marque d'époque** : toute restauration ou bascule incrémente `epoch`. Un envoi portant une époque **inconnue** reçoit **409** `epoch_inconnue` ; l'appareil **ne purge pas** : il entre en état « à resynchroniser », **exporte ses opérations non envoyées dans un fichier chiffré**, puis effectue un tirage complet et propose de **rejouer** les opérations exportées sous contrôle (elles passent par les règles normales : certaines seront refusées en nommant la cause).
- **Restauration depuis le web** (poste mère perdu) : (1) installer le logiciel sur la nouvelle machine, mode mère ; (2) saisir le code émis par le panneau en ligne ; (3) saisir la **clé de clinique** (séquestre papier) ; (4) tirer l'instantané et les enveloppes depuis le relais, déchiffrer, rejouer dans PostgreSQL ; (5) `epoch + 1` ; (6) les fileuls se resynchronisent. **Perte maximale** = ce qui n'a pas atteint le relais (le retard est visible à tout moment sur la console).
- **Restauration d'un poste fileul** : réinstallation → appairage → tirage complet. Le **sort des données non synchronisées** est annoncé **avant** la désinstallation ; « sauvegarde automatique » = export chiffré de la file.
- **Sauvegarde automatique avant migration** : avant toute migration de la base locale (poste, mobile, mère), copie horodatée du fichier SQLite / dump PostgreSQL ; échec de migration → retour à la copie et signalement ; conservation des *(proposé)* 3 dernières.

## 11. Mobile minimal : consultations à domicile et réception de secours

**Principe (décision du 29/10/2026)** : le mobile n'est **pas** relié au réseau local. Il échange **uniquement par le relais**, toujours chiffré ; le relais conserve les enveloppes, la mère les relève automatiquement (§7) et les distribue aux fileuls ; la mère dépose dans la **boîte aux lettres** du mobile ce qui le concerne.

**Deux profils sur la même application :**

| Profil | Pour qui | Contenu |
|---|---|---|
| **Soignant** | consultation à domicile, salle de consultation | agenda du jour, dossier en lecture, constantes, notes de consultation, prescription selon droits |
| **Réception de secours** | agent d'accueil, **quand les postes fileuls sont hors service** (coupure de courant) | module **Réception** : ouvrir un dossier patient, rendez-vous, file d'attente, constantes d'accueil, pièces d'identité. **Ni caisse, ni comptabilité, ni stock** |

*(Périmètre à valider écran par écran avec la spec du module Réception — il reprend les écrans de M1/M2 déjà classés « Accueil » à la maquette.)*

- **Lot préparé par la mère** : la mère prépare un **lot chiffré** (la tournée du jour pour le soignant ; les rendez-vous du jour et les patients récents pour la réception) et le dépose dans la boîte de l'appareil, **la veille ou le matin**, quand elle peut joindre le relais. Le mobile le télécharge dès qu'il a une connexion, puis **travaille hors ligne**. Le lot est **daté** et **expire** *(proposé : 48 h)*. Un patient hors périmètre n'est jamais préchargé.
- **Réception sans fichier complet des patients** *(proposé)* : un téléphone ne porte **pas** les 18 000 identités (un téléphone perdu serait une fuite massive). Conséquence à assumer : un patient **inconnu du lot** peut être enregistré en double. La mère détecte à l'arrivée un **homonyme probable** (nom, naissance, téléphone) et crée un **conflit nommé « doublon possible »** arbitré à la console ; le code patient n'est jamais modifié (RG-01), la fusion est une opération.
- **Numéros** : le mobile reçoit une **plage de numéros** (codes patient, pièces) comme un poste ; plage épuisée → numéro provisoire réconcilié.
- **Protection** : base chiffrée (clé dans le coffre du système), **PIN/biométrie obligatoires**, verrouillage à l'inactivité, aucune sauvegarde dans le nuage de l'appareil, capture d'écran désactivée sur les dossiers *(selon la plateforme)*. Le profil « Réception de secours » est enrôlé **explicitement** par la console.
- **Si la connexion mobile manque aussi** : le mobile continue hors ligne, file persistante, envoi dès qu'une connexion existe — même mécanisme que partout.
- **Conflit possible** : dossier modifié au cabinet pendant la visite → règle de la famille concernée.
- **Révocation / perte** : effet **au prochain contact** ; effacement local à ce moment. Hors réseau, l'appareil garde ses données chiffrées : **c'est la limite à connaître** et la raison du lot restreint et expirant.
- **Dépendance** : si Internet de la clinique ou la mère sont hors service, ce que le mobile envoie **s'accumule au relais** et la mère le relève au retour. Le mobile n'attend pas la mère pour travailler.

## 12. Chiffrement de bout en bout vers le relais (P2/P3)

- **Enveloppe** : `{ id, appareil, seq_local, epoch, taille, charge_chiffrée, nonce, empreinte }` ; **tout le contenu métier, y compris le nom de la collection**, est dans la charge chiffrée. Le relais ne voit que : appareil, date, taille.
- **Algorithme** : chiffrement authentifié moderne *(à arrêter par une revue de sécurité — par exemple AES-256-GCM ou XChaCha20-Poly1305)*, clé de clinique dérivée, jamais envoyée au relais.
- **Clé de clinique** : générée à l'installation de la mère ; **séquestre papier sous scellé** (Direction) ; distribuée aux appareils à l'appairage par canal protégé ; **rotation** documentée ; **perte = sauvegardes et relais irrécupérables**.
- **Indicateurs** (en clair, sans nom de patient) : agrégats de recettes, occupation, ruptures, retards de synchronisation ; format fixe, liste de champs **fermée** (aucun champ libre).
- **Intégrité** : empreinte par enveloppe ; chaîne d'empreintes par appareil pour détecter une enveloppe retirée ou rejouée.

## 13. Panneau superadmin en ligne (Laravel + Blade + Livewire + Alpine) et console de la mère

| Fonction | **Panneau en ligne** (minimal) | **Console de la mère** |
|---|---|---|
| Appareils et jetons (appairer, expirer, révoquer, rotation) | oui (relais et mobiles en route) | **oui — source** |
| Table des postes et supervision (dernier contact, retard, version) | oui (vue réduite) | oui |
| Journaux techniques (erreurs, accès, tâches) | oui, **sans donnée de santé** | oui, complets |
| Conflits et « À traiter » | **nombre et âge seulement** | **oui — arbitrage** |
| « Renvoyer vers ce poste / vers tous » | oui (demande au relais, relayée à la mère) | oui |
| Sauvegardes (rétention, téléchargement chiffré) et restauration | oui (déclenche l'assistant de §10) | oui |
| Battement de cœur de la mère | **oui, alerte si > 5 min d'absence** *(proposé)* | — |
| Indicateurs de pilotage | oui | oui |
| Audit | oui (journal de l'administration) | oui (complet, RG-12) |

Les écrans du panneau en ligne ne chargent **que** des données non nominatives ; tout écran qui devrait montrer un dossier est **sur la console de la mère**.

## 14. Codes d'erreur et comportements

| Code | Sens | Comportement de l'appareil |
|---|---|---|
| 401 `appareil_revoque` | jeton révoqué ou renouvellement rejoué | suspend, conserve les données, propose de se réappairer |
| 401 `jeton_expire` | jeton d'accès expiré | renouvelle silencieusement, sinon redemande l'authentification |
| 403 `droit_refuse` | rôle sans droit sur la collection | opération en « À traiter », jamais rejouée telle quelle |
| 409 `epoch_inconnue` | époque inconnue de la mère | §10 : pas de purge, export puis tirage complet |
| 409 `version_conflictuelle` | même champ modifié ailleurs | conflit nommé |
| 422 `invariant_viole` | stock, lit, exercice clos, équilibre | « À traiter » avec motif et geste |
| 426 `schema_incompatible` | version de schéma trop ancienne | demande la mise à jour, **n'envoie rien** |
| 429 / 503 | surcharge / indisponibilité | attente croissante, sans abandon |

## 15. Paramètres *(tous proposés, à valider au banc)*

| Paramètre | Valeur |
|---|---|
| Interrogation réseau local / relais | 3 s / 30 s |
| Taille de lot d'envoi / de page de réception | 200 / 500 opérations |
| Code d'appairage | 8 caractères, 15 min, usage unique |
| Jeton d'accès / renouvellement | 24 h / 30 jours roulants |
| Attente entre réessais | 2 s → 5 min |
| Dérive d'horloge signalée | > 2 min (EF-SYNC-20) |
| Relève du relais par la mère | 10–15 s |
| Relève de la boîte du mobile | à l'ouverture, puis 60 s en usage *(sur données mobiles, à ajuster)* |
| Expiration du lot mobile | 48 h |
| Fenêtre d'ouverture de la réinitialisation / conservation de la sauvegarde préalable | 24 h / 30 jours |
| Battement de cœur : alerte | > 5 min |
| Conservation des copies avant migration | 3 |

## 16. Recette multi-postes (à répéter à chaque version)

| Réf. | Scénario | Résultat attendu |
|---|---|---|
| SYNC-R1 | Mère arrêtée, deux fileuls créent chacun un dossier patient ; mère redémarrée | deux codes distincts (RG-01), zéro doublon, les deux postes voient les deux dossiers |
| SYNC-R2 | Coupure en plein lot d'envoi, puis rejeu du même lot | zéro doublon, accusé identique |
| SYNC-R3 | Deux postes sortent le dernier lot d'un article, mère arrêtée | avec bail : aucun conflit ; sans bail : le second geste est refusé en nommant l'article, jamais de stock négatif |
| SYNC-R4 | Même champ d'une fiche modifié sur deux postes | conflit nommé sur la console, décision synchronisée |
| SYNC-R5 | Champs différents de la même fiche | les deux modifications conservées |
| SYNC-R6 | Internet coupé 2 h puis rétabli | la mère rattrape le relais seule ; retard visible puis nul |
| SYNC-R7 | Poste révoqué pendant qu'il travaille hors ligne | 401 au retour, données conservées, état « suspendu » |
| SYNC-R8 | Mère détruite ; restauration depuis le relais avec la clé de clinique | données reconstruites, `epoch + 1`, fileuls resynchronisés, perte = retard affiché |
| SYNC-R9 | Marque d'époque inconnue | pas de purge, export des opérations, tirage complet, rejeu contrôlé |
| SYNC-R10 | Mobile : tournée à domicile hors ligne, puis connexion mobile | enveloppes au relais, relevées par la mère, distribuées aux fileuls ; conflit éventuel arbitré ; lot expiré |
| SYNC-R15 | Coupure de courant sur les fileuls : un agent d'accueil enregistre trois patients sur mobile (profil Réception) | dossiers créés hors ligne, codes sans collision, **homonyme probable** signalé en conflit nommé, tout visible sur les fileuls au retour |
| SYNC-R16 | Réinitialisation en production avec second profil | sauvegarde préalable créée, activité vidée, essentiels conservés, `epoch + 1`, appareils purgés après export de leurs opérations non envoyées, restauration de la sauvegarde préalable possible |
| SYNC-R17 | Réinitialisation tentée interrupteur fermé / sans second profil | commande absente / refus nommé, rien n'est modifié |
| SYNC-R18 | Appairage : code expiré, code réutilisé, jeton expiré, renouvellement rejoué | refus nommés ; renouvellement silencieux ; appareil révoqué au rejeu |
| SYNC-R19 | Poste tué (SIGKILL) avec des opérations en attente | file intacte au redémarrage, envoi sans doublon au retour de la mère |
| SYNC-R20 | Suppression, modification d'une fiche archivée, d'une pièce émise, d'un journal, d'un référentiel par un poste | refus nommés ; archivage et restauration synchronisés |
| SYNC-R21 | Création d'un dossier, tirage ralenti | le dossier reste visible en continu, numéro réel dès l'accusé |
| SYNC-R11 | Migration de base d'un poste qui échoue | retour à la copie, signalement, aucune perte |
| SYNC-R12 | Horloge d'un poste décalée de 10 min | ordre fondé sur `seq`, dérive signalée |
| SYNC-R13 | Collecte de toutes les enveloppes du relais | rien de lisible : ni nom de collection, ni patient |
| SYNC-R14 | « Renvoyer vers tous » avec un poste éteint | il acquitte à sa reconnexion ; la console montre le retard |

**Gardes de test** : tous les scénarios s'exécutent sur **deux processus mère/fileul réels** (pas des simulations), avec coupure réseau forcée ; les vecteurs de règles de `packages/domaine` sont rejoués avant chaque version ; un scénario qui modifie la matrice des droits ou vide une collection **la restaure**.

## 17. Ce qui n'est pas documenté / à décider

| # | Question | Qui |
|---|---|---|
| Q1 | Écrans exacts du profil « Réception de secours » du mobile ; accord sur l'**absence du fichier complet des patients** et sur le traitement des doublons possibles | Direction, accueil |
| Q2 | **Nom et fonction** du détenteur du séquestre papier de la clé de clinique, et sa rotation *(la réponse « oui » ne désigne personne)* | Direction |
| Q3 | Second profil de confirmation de la réinitialisation (DAF ? Direction ?) et durée de conservation de la sauvegarde préalable | Direction |
| Q4 | Algorithme de chiffrement et gestion des clés : revue de sécurité indépendante | ingénierie |
| Q5 | Service de la mère : **Windows par défaut, Linux pris en charge** (décision du 29/10) — à éprouver au banc sur les deux | ingénierie |
| Q6 | Cadre légal de la conservation chiffrée de données de santé sur un hébergement tiers | Direction (avis juridique) |
| Q7 | Poste mère de secours à froid : combien, où | Direction |
| Q8 | Les valeurs de §15 : mesure sur le matériel réel de la clinique | ingénierie |
