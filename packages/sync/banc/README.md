# Banc de synchronisation à plusieurs processus

Éprouve **le protocole** de `docs/specs/SPEC-protocole-synchronisation.md` avec une **mère** et des **fileuls** qui sont de vrais processus, chacun sur sa base, reliés par un **commutateur TCP** qui coupe le réseau en cours de route.

```bash
cd packages/sync
npm run banc              # tout (≈ 20 s) — Node ≥ 22.13, aucune dépendance à installer
node --no-warnings banc/run.js R3 R4     # seulement ces scénarios
```

## Ce que le banc fait

| Élément | Rôle |
|---|---|
| `mere.js` | Poste mère de **référence** : appairage, journal d'opérations à `seq` sans trou, quatre familles de fusion, conflits nommés, bail de stock, plages de numéros, époque, réinitialisation encadrée, console d'administration (HTTP) |
| `fileul.js` | Poste fileul de **référence** : base locale, file persistée, curseur, « on reçoit avant d'envoyer », suspension à la révocation, export avant purge d'époque |
| `proxy.js` | Commutateur : `ouvert` · `ferme` (câble arraché) · `perd_reponse` (le lot est traité mais la réponse n'arrive jamais) |
| `relais.js` | Relais en ligne de **référence** (contrat de `apps/web`) : **opaque** — il n'importe ni `crypto.js` ni aucune clé ; stocke des enveloppes (appareil, sens, rang, taille), des indicateurs en clair sans nom, le battement de cœur de la mère ; ne contacte jamais la mère |
| `crypto.js` | Enveloppes AES-256-GCM, clé de clinique ; métadonnées authentifiées (id, appareil, sens, rang) ; **utilisé par la mère et le mobile seulement** |
| `mobile.js` | Mobile de **référence** (profils `soignant` et `reception`) : ne connaît **que** le relais, lot expirant, file persistante à rang contigu, effacement + export à la révocation |
| `run.js` | Orchestrateur : lance, tue (SIGKILL) et relance mère, relais, fileuls et mobiles ; 26 scénarios, ≈ 127 vérifications (≈ 70 s) |

La mère de référence contient désormais le **pont** : réplication chiffrée de son journal vers le relais, relève des enveloppes des mobiles (contiguïté des rangs, authentification), boîtes aux lettres par appareil, lots de tournée, profils de droits des mobiles, détection de doublon possible, restauration depuis le relais, battement de cœur et indicateurs.

## Scénarios (référence : spec §16)

R1 mère arrêtée, deux dossiers · R1b plage épuisée, numéro provisoire · R2 réponse perdue, rejeu sans doublon · R3 dernier lot sans bail · R3b dernier lot avec bail · R4 conflit nommé et décision · R5 champs différents · R7 révocation hors ligne · R8 réinitialisation en production (fenêtre, second profil, sauvegarde, époque, export) · R12 horloge décalée · R14 « renvoyer vers tous » · R18 appairage (usage unique, expiration, renouvellement rejoué) · R19 file persistante après SIGKILL · R20 archivage, pièce émise, journal, référentiel · R21 un dossier qu'on vient de créer ne disparaît pas de l'écran.

**Relais chiffré et mobile :** R6 Internet coupé, la mère rattrape seule · R6b battement de cœur et indicateurs sans nom · R10 mobile à domicile (lot, saisie hors ligne, relais, distribution, **aucun contact direct avec la mère**, **aucune fuite hors de la tournée**) · R10b expiration du lot · R10c mobile perdu : révocation, effacement, export · R13 relais opaque (octets décodés + entropie) · R13b enveloppe altérée / retirée · R15 coupure de courant : réception de secours sur mobile, doublon signalé, droits du profil · R23 cloisonnement des boîtes · R8r mère détruite, restauration depuis le relais (empreinte identique) · R8s restauration après réinitialisation, et mauvaise clé.

## Ce que ce banc PROUVE

- l'idempotence du rejeu, l'ordre par la séquence de la mère (jamais par l'horloge), les conflits nommés, l'absence de stock négatif avec et sans bail, l'absence de suppression physique, la réinitialisation qui ne ressuscite rien, la persistance de la file à l'arrêt brutal ;
- que le banc **détecte** les défauts : on a retiré tour à tour l'idempotence, le contrôle de stock, la détection de conflit, la garde de suppression, le contrôle d'époque à l'envoi, le maintien d'un dossier accepté à l'écran, **le chiffrement des enveloppes, le cloisonnement des boîtes du relais, la détection des trous de rang, les droits du profil mobile et la portée du lot** — chaque retrait fait échouer le ou les scénarios concernés.

## Ce que le banc a déjà trouvé (et corrigé)

1. **Un dossier créé disparaissait de l'écran** entre l'accusé de la mère et le tirage suivant (la file l'oubliait avant que le flux ne le rende). Corrigé dans `fileul.js` (`enVol()`), verrouillé par R21.
2. **Le contrôle d'époque à l'envoi n'était testé par rien** : le poste de référence tire avant d'envoyer, donc le tirage le protégeait et masquait l'absence de garde côté mère. Un test d'envoi direct d'une ancienne époque a été ajouté (R8).
3. **Le test d'opacité du relais était trop faible** : une enveloppe « cachée » par un simple base64 passait. Il décode désormais chaque enveloppe, cherche les secrets dans les octets et mesure l'entropie (un chiffrement authentifié ressemble à du hasard).
4. **Le test de portée du mobile ne pouvait pas échouer** : les dossiers « hors tournée » existaient avant l'appairage, donc rien ne descendait de toute façon. Le scénario modifie et crée désormais des dossiers APRÈS l'appairage.
5. Plusieurs courses **dans les tests eux-mêmes** (lire avant convergence) : corrigées en attendant la convergence, jamais en allongeant une pause.

## Ce qu'il NE prouve PAS (à faire avant d'accepter ADR-0005)

| Non couvert | Pourquoi ça compte |
|---|---|
| **Dart / Flutter** | le banc est en Node : il valide la **conception**, pas le code Dart ; le même banc doit ensuite piloter le vrai service Dart (mêmes routes, mêmes scénarios) |
| **PostgreSQL** | la mère de référence utilise SQLite ; la tenue des transactions et des verrous sous PostgreSQL reste à mesurer |
| **SQLCipher, service Windows/Linux, onduleur, coupure de courant réelle** | critères 6 et 7 du banc d'ADR-0003 |
| **Le vrai relais Laravel** | `relais.js` est le contrat ; `apps/web` doit passer **les mêmes scénarios** (R6, R6b, R13, R23 visent le relais) |
| **Gestion de la clé de clinique** | ici la clé est dans la base de la mère et passée en argument : le coffre du système, le séquestre papier et la **rotation** de clé ne sont pas éprouvés |
| **Algorithme et revue de sécurité** | AES-256-GCM via `node:crypto` : une revue indépendante reste à faire (spec Q4) ; aucune protection contre l'analyse du trafic (tailles, rythme) |
| **Restauration d'une mère avec appareils** | après restauration, les appareils doivent se **réappairer** (leurs jetons ne sont pas restaurés) ; les baux de stock sont perdus |
| **Réinitialisation entre deux réplications** | une activité non encore répliquée au moment de la réinitialisation est supprimée localement — sans conséquence ici (elle est de toute façon vidée) |
| **Relais saturé ou lent, grandes tailles** | enveloppes de quelques Ko seulement ; aucune mesure de débit ni de limite d'exécution cPanel |
| **Charge** | 15 postes + mobiles, 20 000 lignes : aucune mesure ici |
| **Dépendance entre opérations** | une opération refusée ne bloque pas encore celles qui en dépendent sur la même fiche (spec §5.6) |
| **Fusion de deux mères / bascule d'autorité** | non écrite |

Un résultat vert ici **ne dit pas** que le produit est prêt : il dit que le protocole décrit tient sur ce qu'on lui a demandé.

## Le même banc, trois implémentations (29–30/10/2026)

Le banc pilote **n'importe quelle combinaison** de processus par variables d'environnement :

| Variable | Valeur | Exécutable lancé |
|---|---|---|
| `SIGH_MERE` / `SIGH_FILEUL` / `SIGH_MOBILE` | `dart` | `packages/sync_dart/build/<x>_bundle/bundle/bin/<x>` (à construire : `packages/sync_dart/construire.sh`) ; sinon le `.js` de référence |
| `SIGH_RELAIS` | `laravel` | le **vrai relais** `apps/web` (serveur intégré de PHP, SQLite jetable, migrations rejouées) ; sinon `relais.js` |

| Passage | Résultat |
|---|---|
| Tout en Node (référence) | 26 scénarios, 127 vérifications |
| Mère + fileuls Dart (scénarios sans relais) | 15 scénarios, 72 vérifications |
| Relais Laravel seul (mère, postes et mobiles Node) | 11 scénarios relais verts après correction de l'ordre autorisation → validation |
| **Tout en Dart + relais Laravel** (`npm run banc:cible`) | **26 scénarios, 127 vérifications, 74 s** |

| **Mère sur PostgreSQL** (`npm run banc:pg`, `SIGH_PG_URL=postgres://utilisateur:motdepasse@hôte:port`) | **26 scénarios, 128 vérifications, 85 s** — une base PostgreSQL jetable par scénario, supprimée à la fin |

Ce que cela prouve en plus : le service Dart de la mère, le client Dart du poste et du mobile (SQLite embarqué, enveloppes AES-256-GCM via `package:cryptography`) et le relais Laravel parlent **le même protocole**, octet pour octet — une enveloppe chiffrée par Dart est lue par Node et réciproquement. Ce que cela ne prouve toujours pas : SQLCipher, le service Windows, la charge (aucun volume), la tenue aux pannes de PostgreSQL lui-même (arrêt brutal en pleine transaction), une revue de sécurité.
