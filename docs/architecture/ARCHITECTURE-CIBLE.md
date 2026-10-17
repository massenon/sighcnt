# Architecture cible — SIGH-CNT hors ligne d'abord

Statut : **proposition** du 17/10/2026, à arrêter par la Direction (voir §14) · ADR associées : ADR-0001 (local-first et hub en étoile), ADR-0002 (monorepo).

## 0. La recommandation en dix lignes

Chaque **poste de travail** porte l'application entière et sa propre base (SQLite chiffrée) : il
ouvre une session, consulte, prescrit, encaisse et **imprime sans aucun réseau**. Un **hub de
clinique** (petit serveur Linux sur onduleur, PostgreSQL) est l'autorité : il ordonne les
opérations venues des postes, vérifie les invariants (RG-01 → RG-14), tient le journal d'audit et
redistribue à tous. Le réseau est une **étoile** poste ↔ hub, jamais un maillage poste ↔ poste. On
ne synchronise pas des états mais des **gestes** : un journal d'opérations append-only, identifié
par UUID et horloge logique, rejouable. Les conflits se **montrent** (tâche nommée au poste
responsable), ils ne se résolvent jamais en silence. Internet ne sert qu'à deux choses : la
**certification MECeF** (file d'attente sortante au hub) et le **réplica hors site** chiffré. Les
300 écrans, le manifeste RBAC et les moteurs du prototype sont **repris**, pas réécrits ; seule la
couche de persistance change.

## 1. Contexte et contraintes

| Contrainte | Source | Conséquence architecturale |
|---|---|---|
| ~30 agents, ~15 postes, un seul bâtiment, LAN câblé/Wi-Fi | rapport de cadrage | une étoile suffit ; pas de multi-site |
| Coupures d'électricité et d'Internet fréquentes | terrain (Natitingou) | le poste ne dépend ni du hub ni d'Internet pour le geste courant |
| « Architecture Web/API ou cloud pour l'usage courant » hors périmètre | CDCT §4.3 | pas de SaaS, pas de serveur distant sur le chemin d'un geste |
| Zéro action anonyme, journalisation ancienne/nouvelle valeur | RG-12 | le journal d'opérations EST le journal d'audit |
| Stock jamais négatif, écritures équilibrées, codes uniques | RG-03, RG-10, RG-01 | invariants vérifiés par une autorité unique (le hub) |
| Suppression logique seulement | RG-14 | tombstones, jamais de DELETE répliqué |
| Facture normalisée MECeF | CDCT, pièce SoBAPS | certification en ligne différée, encaissement jamais bloqué |
| L'impression est une exigence majeure | CDCT §21, draf1 | impression locale au poste, gabarits dans un paquet partagé |
| Existant : prototype 305 écrans + `sigh_web` Laravel (173 tables, 70 k lignes PHP) | CLAUDE.md vague 66 | reprise de l'interface et des moteurs ; schéma relationnel à auditer |
| Décision « 1 + 2 et pas 3 » : ne pas réécrire l'interface | Direction, 23/09/2026 | la couche écran garde son contrat de lecture SYNCHRONE |

**Ce que la maquette actuelle ne sait pas faire, et qui commande tout** : son serveur remplace une
**collection entière** à chaque envoi (`magasin.php`, POST par delta de collection). Deux postes
qui écrivent dans `factures` à la même minute : le second **efface** la facture du premier. Ce
n'est pas un bug d'implémentation, c'est le modèle « on synchronise des états » qui ne peut pas
tenir à plusieurs postes. D'où le principe 2.

## 2. Trois principes

1. **Le poste est la vérité locale, le hub est la vérité de la clinique.** Un poste travaille
   toujours ; le hub tranche quand les postes se contredisent. Jamais l'inverse.
2. **On synchronise des gestes, pas des états.** Une opération nommée (« encaisser la facture
   F-2026-0412, lignes 1 et 3 »), signée, datée, idempotente. L'état se reconstruit en la
   rejouant ; le journal RG-12 est obtenu gratuitement.
3. **Un conflit se montre.** C'est la doctrine « une restriction s'annonce » appliquée à la
   synchronisation : une opération que le hub ne peut pas appliquer telle quelle devient une
   tâche visible au poste responsable, avec son motif. Rien n'est fusionné en cachette.

## 3. Vue d'ensemble

```
   POSTE Accueil        POSTE Caisse        POSTE Labo        POSTE Maternité  …  (≈ 15)
   ┌───────────────┐    ┌───────────────┐   ┌───────────────┐  ┌───────────────┐
   │ UI (écrans du │    │               │   │               │  │               │
   │  prototype)   │    │               │   │               │  │               │
   │ domaine + rbac│    │               │   │               │  │               │
   │ store local   │    │               │   │               │  │               │
   │ SQLite chiffré│    │               │   │               │  │               │
   │ journal + file│    │               │   │               │  │               │
   │ impression    │    │               │   │               │  │               │
   └───────┬───────┘    └───────┬───────┘   └───────┬───────┘  └───────┬───────┘
           │  HTTPS LAN (push journal / pull séquence, SSE)             │
           └──────────────┬────┴────────────────┬────────────────────────┘
                          ▼                     ▼
                 ┌────────────────────────────────────────┐
                 │  HUB DE CLINIQUE (Linux + onduleur)     │
                 │  PostgreSQL 16                          │
                 │  service de synchronisation (autorité)  │
                 │   - ordre global, invariants, RBAC      │
                 │   - tranches de numéros, audit immuable │
                 │  passerelle MECeF (file sortante)       │
                 │  sauvegardes + serveur de mises à jour  │
                 └───────────────┬────────────────────────┘
                                 │  Internet, quand il y en a (chiffré)
                        ┌────────┴─────────┐          ┌──────────────┐
                        │ réplica hors site │          │ e-MECeF DGI  │
                        │ (sauvegarde seule)│          └──────────────┘
                        └───────────────────┘
```

**Modes dégradés, tous nominaux :**

| Panne | Ce qui continue | Ce qui attend | Ce que l'écran dit |
|---|---|---|---|
| Hub arrêté (coupure, panne) | tout le travail de chaque poste, impression comprise | la visibilité entre postes, les tranches de numéros neuves, MECeF | pastille « hub injoignable depuis 12 min, 7 opérations en attente » |
| Internet coupé | tout, hub compris | certification MECeF, réplica hors site | « facture en attente de certification » sur la pièce |
| Un poste HS | les autres postes | ce que ce poste n'avait pas encore poussé (visible au hub : dernière séquence reçue) | réinstallation puis ré-hydratation complète depuis le hub |
| Hub perdu (disque) | les postes | la clinique entière, le temps de restaurer | restauration depuis la sauvegarde + **rejeu des journaux des postes** (§10) |

## 4. Le poste

- **Application de bureau** : **Tauri 2** (coque Rust légère, interface dans le WebView du
  système — WebView2 sur Windows 10/11). Un installeur signé, une icône, un fichier de base, pas
  de navigateur à configurer, pas de cache qu'un nettoyage efface. **Electron** reste l'option de
  repli si le parc comporte des Windows antérieurs à 10 (inventaire à faire, §14). Une PWA seule
  est écartée : le cache navigateur n'est pas un support de données de santé.
- **Base locale SQLite** (via SQLCipher : chiffrée au repos — un portable volé contient des
  dossiers médicaux). Trois familles de tables : les **collections** (une table par collection,
  colonnes typées pour ce qu'on filtre et indexe, `json` pour le reste — c'est ce qui permet de
  reprendre le modèle documentaire du prototype sans tout re-typer d'un coup), le **journal
  d'opérations** (locales et reçues), la **file de sortie** (opérations non encore acquittées par
  le hub).
- **Store** : le contrat du prototype est conservé — `S.collection('factures').all()` répond de
  façon **synchrone** depuis un cache mémoire chargé depuis SQLite au démarrage, et chaque
  écriture produit une opération (journal + file de sortie) avant de mettre le cache à jour. Les
  300 écrans ne voient pas la différence : c'est la condition de la décision « ne pas réécrire ».
- **Authentification hors ligne** : l'annuaire des comptes (identifiant, hachage argon2id, rôle,
  fonction, secteur, `doit_changer`) est une collection répliquée comme les autres ; la session est
  locale et verrouillée à 15 min (CDCT §12.2). Les droits viennent de `packages/rbac`, le même code
  qu'au hub.
- **Impression locale** : gabarits A4, rouleau 80 mm, carte CR80 de `packages/impression`,
  imprimante du poste. Aucune dépendance au hub pour imprimer un reçu.
- **Horloge** : l'heure d'un PC de clinique n'est pas fiable (pile BIOS). Le poste porte une
  **horloge logique hybride** (HLC) recalée sur le hub à chaque échange ; l'heure affichée est
  l'heure du geste, l'ordre d'application est celui du hub.

## 5. Le hub de clinique

Un mini-serveur (type NUC ou tour silencieuse, 16 Go, deux disques en miroir) sous Linux, sur
onduleur, dans un local fermé. Tout tourne en **Docker Compose** (`infra/hub`) :

| Service | Rôle |
|---|---|
| PostgreSQL 16 | la vérité de la clinique : collections + journal d'opérations + audit |
| `apps/hub` (Node.js 22 / TypeScript, Fastify) | réception des journaux, ordre global, **invariants**, **RBAC serveur**, tranches de numéros, diffusion (SSE), annuaire |
| passerelle MECeF | file sortante vers e-MECeF, reprise automatique, pièce réimprimable avec son code |
| sauvegarde | `pg_dump` chiffré quotidien sur disque externe + réplica hors site (restic) quand Internet répond |
| mises à jour | sert les installeurs des postes ; un poste se met à jour depuis le hub, jamais depuis Internet |

Le hub est **sans état côté métier** en dehors de PostgreSQL : on le réinstalle en une heure
depuis `infra/hub` et une sauvegarde.

**Pourquoi Node/TypeScript et pas PHP pour le hub** : `packages/domaine`, `packages/rbac` et
`packages/sync` doivent tourner **identiques** au poste et au hub (même matrice de droits, même
contrôle RG-10, même règle de fusion). Deux implémentations — JavaScript au poste, PHP au hub —
divergeraient au premier correctif : c'est la leçon « une règle qui vit en deux exemplaires »
payée quatre fois dans le prototype. Le PHP de `sigh_web` reste une **mine de schéma** (173
tables) et de règles à relire, pas une base d'exécution.

## 6. La synchronisation — le cœur

### 6.1 Identifiants

Toute fiche porte un **UUID v7** engendré au poste (trié par le temps, unique sans coordination).
Le **numéro métier** (CNT/n/année, F-NNNNN, LAB-NNNNN, NNNNN-AAAA) est une donnée **distincte** de
l'identité : il peut être provisoire, il n'empêche jamais de créer la fiche (§6.6).

### 6.2 Le journal d'opérations

```
operation {
  id            uuid v7                 — idempotence : rejouer deux fois = une fois
  poste, utilisateur, session           — RG-12 : jamais anonyme
  hlc           horloge logique hybride — ordre causal entre postes
  seq           bigint, posé par le HUB — ordre global d'application (null tant que non acquittée)
  type          'creer' | 'modifier' | 'archiver' | 'restaurer'
                | opération MÉTIER nommée : 'prescrire', 'encaisser', 'delivrer', 'valider_ecriture',
                  'emettre_avoir', 'rendre_resultat', 'transferer_stock', …
  collection, ficheId
  charge        champs modifiés : { champ: { avant, apres } }  — RG-12 ancienne / nouvelle valeur
  depend_de     [ids d'opérations]      — une délivrance dépend de son encaissement
  schema        VERSION du poste émetteur
}
```

Une opération **métier** (« encaisser ») est préférée à trois opérations techniques (« modifier
facture, modifier ligne, créer écriture ») : le hub peut revérifier l'invariant de l'ensemble, et
le journal se lit comme un registre.

### 6.3 Protocole

- **Push** : le poste envoie sa file de sortie dans l'ordre ; le hub acquitte opération par
  opération (idempotent par `id`) et pose `seq`.
- **Pull** : le poste demande « tout ce qui a un `seq` supérieur au dernier que je connais » ;
  un flux SSE le prévient qu'il y a du neuf, un long-polling le remplace si SSE est bloqué.
- **Hydratation initiale** : instantané des collections + `seq` courant, puis pulls incrémentaux.
- **Transport** : HTTPS sur le LAN, certificat interne du hub installé par l'installeur. Rien ne
  sort du bâtiment.

### 6.4 Règles de fusion, par famille de données

| Famille | Exemples | Règle | Conflit possible ? |
|---|---|---|---|
| **Fiche descriptive** | patient (identité, adresse), personnel, référentiels, fournisseurs | fusion **par champ**, le HLC le plus récent gagne ; les deux versions restent au journal | oui, bénin ; les deux valeurs se lisent dans l'historique de la fiche |
| **Journal métier (append-only)** | constantes, administrations, mouvements de stock, relevés, présences, audit | on ajoute, jamais on ne modifie ; deux postes = deux lignes | non |
| **Pièce émise** | facture, reçu, certificat, écriture validée, CR validé, bulletin de paie | **immuable** après émission ; correction = avoir, rectification numérotée (doctrine déjà en place) | non : deux émissions = deux pièces |
| **Agrégat à invariant** | stock par magasin (RG-03), séries de numéros (RG-01), pièce comptable (RG-10), lit occupé, carte d'assurance à la date (RG-09) | vérifié au poste **et** revérifié par le hub à l'application ; si l'invariant ne tient plus → opération **en suspens** et **tâche nommée** | oui, et c'est précisément ce qu'on rend visible |

Les CRDT génériques sont écartés : « le stock ne peut pas être négatif » n'est pas une propriété
qu'une structure fusionnable sait garantir ; seule une autorité qui applique dans un ordre le peut.

### 6.5 Numérotation hors ligne

Les séries (code patient par année, factures, LAB-, codes d'analyse, pièces certifiantes) sont
gapless à l'unité sur le registre papier, et un poste hors ligne ne peut pas demander « le
suivant ». Règle :

1. Le hub délivre à chaque poste des **tranches** par série (ex. 20 numéros), le poste en garde
   toujours une d'avance et la renouvelle dès qu'il voit le hub.
2. Tranche épuisée, hub injoignable : la pièce reçoit un **numéro provisoire** (`P-<poste>-<n>`),
   la mention **PROVISOIRE** s'imprime, et la régularisation attribue le numéro définitif à la
   synchronisation ; la pièce se réimprime avec. Le lien provisoire → définitif reste au journal.
3. Conséquence assumée : les numéros d'une série ne sont pas strictement chronologiques entre
   postes (le poste Caisse peut émettre 0412 après que Labo a émis 0431). Ils restent uniques et
   sans trou sur l'exercice. Un suffixe de poste dans le numéro a été écarté : il romprait la
   correspondance avec les registres papier.

**À arbitrer** (§14) : si une série doit rester chronologique à l'unité (pièces certifiantes ?),
elle devient **émise par le hub seul** et le poste la demande en ligne — c'est une restriction qui
s'annonce, pas un blocage du geste (la pièce part provisoire).

### 6.6 Stock

Un magasin (gros, détail, labo) a **un seul poste écrivain** — magasinier pour le gros,
Caissière-Dispensatrice pour le détail : c'est l'organisation réelle de la clinique, et elle rend
le conflit de stock structurellement improbable. Le hub reste le filet : une sortie qui rendrait un
stock négatif à l'application est mise en suspens, avec une tâche « régulariser le stock de
<article> au magasin <x> » au poste écrivain. Chaque mouvement porte ses deux valorisations
(prix de vente et CUMP), comme aujourd'hui.

### 6.7 Comptabilité

Une **pièce** (toutes ses lignes plates) est **une** opération : RG-10 contrôlée au poste avant
émission et revérifiée au hub. Les écritures naissent en brouillon ; la validation est un geste du
comptable, lui-même une opération. La clôture (`m12-cloture`) exige que le hub ait reçu **toutes**
les files de tous les postes jusqu'à la date : un poste en retard est nommé, la clôture attend.

### 6.8 Schéma et versions

`VERSION` vit en **un seul endroit** (`packages/schema`) ; les migrations sont numérotées et
rejouables, pour SQLite et pour PostgreSQL. Chaque opération porte le `schema` de son émetteur. Un
poste **en retard** continue de lire mais **n'écrit plus** tant qu'il n'est pas mis à jour, et le
dit — un poste qui écrirait une forme que le hub ne lit pas, c'est la vague 67 rejouée. Le hub
accepte en lecture les deux dernières versions.

### 6.9 Moteur : construire sur l'existant, trancher par un banc d'essai

Écrire un moteur de synchronisation complet (reprise, idempotence, instantanés, compaction) est le
poste le plus risqué du projet. Deux moteurs libres et auto-hébergeables correspondent exactement
au schéma ci-dessus — « PostgreSQL au hub, SQLite au poste, lecture synchronisée par le moteur,
écriture via **notre** API où vivent les invariants » :

| Option | Pour | Contre |
|---|---|---|
| **PowerSync** (édition libre auto-hébergée) | SQLite partout (Tauri, navigateur) ; file d'envoi côté client passant par notre API ; règles de diffusion par rôle/secteur (RG-13 sur le fil) | service supplémentaire au hub ; dépendance à un éditeur |
| **ElectricSQL** | Apache-2, « shapes » par filtre, PGlite/SQLite | plus jeune sur le chemin d'écriture ; outillage en évolution |
| **Maison** (`packages/sync` seul) | aucune dépendance, exactement nos règles | tout à écrire et à prouver ; le risque le plus élevé |

**Décision proposée** : un **banc d'essai de deux semaines** (`packages/sync`, trois collections —
patients, factures, mouvements — deux postes, hub coupé puis rétabli, voir `/test-plan`) qui
compare PowerSync et l'implémentation maison sur le protocole §6.3. Le choix se consigne en
ADR-0003. Quel que soit le moteur, le **journal d'opérations et les invariants restent à nous** :
le moteur transporte, il ne décide pas.

## 7. Sécurité

- **Au repos** : SQLite chiffré (SQLCipher) sur chaque poste ; clé dérivée d'un secret du poste
  remis par le hub à l'installation ; disques du hub chiffrés (LUKS).
- **En transit** : TLS sur le LAN ; aucune API exposée hors du bâtiment ; le réplica hors site ne
  reçoit que des sauvegardes chiffrées, jamais une connexion à PostgreSQL.
- **Droits** : `packages/rbac` est exécuté par le poste (ce qu'on voit) **et** par le hub (ce
  qu'on applique) ; une opération hors droits est refusée au hub même si un poste modifié l'émet.
  C'est le pas que la maquette n'a pas fait (son serveur ne connaît pas la matrice).
- **Audit** : table append-only au hub, chaînée par hachage (chaque entrée porte le hachage de la
  précédente) : une entrée effacée se voit. Export mensuel signé sur le disque de sauvegarde.
- **Comptes** : argon2id, verrouillage après échecs, changement obligatoire au premier usage,
  un rôle s'archive et ses comptes cessent d'ouvrir (déjà en place).
- **Jamais de donnée médicale** dans une adresse, un son, un message d'alerte, un QR (doctrine
  des badges et des enquêtes, conservée).

## 8. MECeF

L'encaissement n'attend **jamais** la certification. La facture naît, s'imprime avec la mention
« en attente de certification MECeF », et la passerelle du hub soumet à e-MECeF dès qu'Internet
répond ; le code et le QR de certification sont rattachés à la pièce, réimprimable. La file sortante
est visible dans `mecef-*` (combien en attente, depuis quand, dernière erreur). **À confirmer auprès
de la DGI** : la tolérance de délai entre émission et certification, qui conditionne la taille
acceptable de la file (§14).

## 9. Impression et états

Les gabarits (A4, rouleau 80 mm, carte CR80) et l'en-tête légal unique (IFU 3201642748214,
RCCM RB/NAT/2016-B-268) vivent dans `packages/impression`, consommés par le poste ; les états
portent les filtres en force, le pied normalisé et des totaux calculés. Une imprimante réseau
partagée est possible, mais chaque poste de caisse garde **sa** ticket 80 mm en direct.

## 10. Sauvegarde et reprise d'activité

- **Quotidien** : `pg_dump` chiffré sur le second disque et sur un disque externe tournant ; hors
  site quand Internet répond (restic vers un stockage objet ou un second site). Une sauvegarde est
  **restaurée** une fois par mois sur une base jetable, sinon elle n'existe pas.
- **Le journal des postes est une sauvegarde répartie** : si le hub est perdu, on restaure la
  dernière sauvegarde puis chaque poste **repousse** sa file et son journal depuis la séquence
  restaurée — par construction, les opérations sont idempotentes et ordonnées. Procédure écrite
  dans `infra/hub/PRA.md`, testée au pilote.
- **Rétention** : journal d'opérations jamais purgé (RG-12) ; instantanés compactés par exercice.

## 11. Déploiement et mises à jour

Installeur Windows signé (Tauri), configuration du poste (nom, secret, adresse du hub) posée à
l'installation ; mises à jour servies **par le hub**, appliquées à la prochaine ouverture, schéma
rétro-compatible d'une version. `m14` affiche la version de chaque poste et sa dernière
synchronisation : un poste en retard se voit.

## 12. Ce qui est repris, et d'où

| Du prototype | Vers | Ce qui change |
|---|---|---|
| `nav.js` (manifeste, rôles, `can()`, alias, `servant`, `universel`) | `packages/rbac` | TypeScript, exécuté aussi au hub |
| `parcours.js`, moteurs de M8/M9/M11/M12 (`repartir`, `emettreAvoir`, `bfr`, paie) | `packages/domaine` | fonctions pures, testées hors navigateur |
| `data-*.js` | `packages/referentiels` | référentiels versionnés avec leur source |
| `print.js` | `packages/impression` | gabarits, en-tête unique |
| `store.js` (CRUD, archivage, audit, `_version`) | `apps/poste` (store) + `packages/schema` + `packages/sync` | persistance SQLite, journal d'opérations ; **contrat synchrone conservé** |
| modules d'écran (`modules/*.js`), `_kit.js`, `ui.js`, `app.js` | `apps/poste` | repris tels quels, puis migrés en TypeScript module par module |
| bancs d'essai (`check`, `test`, `audit-rbac`) | `apps/poste` | + banc de synchronisation à deux postes |
| `api/*.php` | — | remplacé par `apps/hub` |

| De `sigh_web` (Laravel) | Vers | Ce qui change |
|---|---|---|
| 61 migrations, 173 tables | `packages/schema` (après audit) | base du typage des colonnes filtrées/indexées |
| règles métier en PHP | `packages/domaine` (relues) | pas d'exécution PHP en cible |
| pages Inertia/Vue | — | non reprises : elles exigent le serveur à chaque navigation |

## 13. Trajectoire

| Phase | Contenu | Preuve de fin |
|---|---|---|
| **P0 — cadrage** (maintenant) | monorepo, ADR-0001/0002, PRD par module via `/prd`, audit du schéma `sigh_web` | docs en place, arbitrages §14 rendus |
| **P1 — socle et banc de synchronisation** | `packages/schema` (SQLite + PostgreSQL, VERSION unique), `packages/sync` : journal, HLC, protocole ; banc à deux postes ; comparatif PowerSync / maison → ADR-0003 | banc vert : hub coupé/rétabli, 0 geste perdu, conflits visibles |
| **P2 — poste** | coque Tauri, store SQLite au contrat synchrone, écrans du prototype branchés tels quels, authentification hors ligne, impression | `check` et `test` du prototype verts sur le nouveau store ; une journée d'accueil simulée sans hub |
| **P3 — hub** | RBAC serveur, invariants, tranches de numéros, audit chaîné, annuaire | audit-rbac exécuté **contre le hub** : 0 opération hors droits acceptée |
| **P4 — exploitation** | passerelle MECeF, sauvegardes + PRA testé, installeur, mises à jour, supervision `m14` | restauration à blanc réussie ; facture certifiée après coupure |
| **P5 — pilote puis généralisation** | 3 postes (accueil, caisse, labo) deux semaines, puis les autres service par service | parcours CDCT UC-01 → UC-08 traversés en réel |

## 14. Arbitrages à rendre par la Direction

| Question | Option recommandée | Ce qui dépend de la réponse |
|---|---|---|
| Parc des postes : versions de Windows, RAM, imprimantes | inventaire avant P2 | Tauri (Win 10+) ou Electron |
| Tolérance MECeF entre émission et certification | demander à la DGI | taille de file admise, mention sur la pièce |
| Séries qui doivent rester chronologiques à l'unité | aucune sauf pièces certifiantes, émises par le hub | numérotation §6.5 |
| Un seul poste écrivain par magasin | oui (organisation actuelle) | règle de fusion du stock |
| Réplica hors site : où (second site de la clinique, stockage objet chez un hébergeur, disque emporté) | stockage chiffré chez un hébergeur + disque tournant | coût mensuel, conformité |
| Hub : matériel et local | mini-serveur deux disques + onduleur 1 kVA, local fermé | budget, délais |
| Sort de `sigh_web` | relire pour le schéma et les règles, ne pas l'exécuter | charge d'audit en P0 |

## 15. Alternatives écartées

| Alternative | Pourquoi non |
|---|---|
| **Laravel + Inertia/Vue sur le hub, postes = navigateurs** (modèle `sigh_web`) | chaque navigation exige le serveur : un hub coupé arrête la clinique — l'inverse de l'exigence |
| **PostgreSQL sur chaque poste + réplication logique** | multi-maître PostgreSQL n'est pas natif ; invariants inapplicables ; exploitation d'un serveur par PC, sans informaticien |
| **CouchDB / PouchDB** (réplication documentaire) | colle au modèle documentaire actuel, mais les invariants (stock, RG-10, séries) retombent sur du code applicatif, et les états comptables en Map/Reduce sont pénibles ; SQL au poste vaut mieux pour 130 états |
| **CRDT génériques (cr-sqlite, Yjs)** | fusionnent sans autorité : « stock négatif » ou « deux factures 0412 » sont des fusions valides pour un CRDT |
| **Maillage poste ↔ poste sans hub** | aucune autorité pour les invariants ni la numérotation ; sauvegarde introuvable ; débogage impossible |
| **PWA seule servie par le hub** | code et données dans un cache navigateur, effaçable, non chiffré, sans impression système fiable |
| **Cloud d'usage courant** | hors périmètre CDCT §4.3 ; Internet intermittent |

---

*Ce document est la proposition ; `docs/architecture/adr/ADR-0001-local-first-hub-etoile.md`
porte la décision à prendre, `ADR-0002-monorepo.md` l'organisation du dépôt. Les PRD par module
(`/prd`) et le plan de P1 (`/plan`) en découlent.*
