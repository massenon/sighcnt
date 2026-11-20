# PRD — Socle : l'application sans rechargement de page, les notifications qui informent, les tâches planifiées

Statut : **brouillon** du 20/10/2026, à arrêter par la Direction
Sources : demande de la Direction du 20/10/2026 (« convertir le prototype PHP/PostgreSQL actuel en vraie application sans chargement de pages, avec des notifications qui informent l'utilisateur, avec des cron jobs ») · ARCHITECTURE-CIBLE.md et ADR-0001 (postes autonomes, hub en étoile) · vague 66 (pages `.php`, magasin en PostgreSQL) · vague 36 (moteur de notification) · CDCT §4.3 (hors périmètre : cloud d'usage courant)

## 1. Problème

Chaque écran du prototype est une **page** : cliquer un lien recharge le document, recharge les vingt scripts, **re-télécharge le magasin entier (4,8 Mo)** depuis PostgreSQL, ré-hydrate, puis peint. Sur le serveur intégré de PHP, mono-processus, cela prend une à trois secondes par écran, et c'est le temps que l'accueil perd vingt fois par matinée. Les notifications, elles, sont **recalculées par chaque page** à l'ouverture puis toutes les 45 secondes, sur le poste seulement : un rendez-vous pris sur le poste Accueil ne prévient le poste du médecin qu'à son prochain rechargement, et rien ne se passe quand personne n'a d'écran ouvert — l'échéance fiscale dépassée à 2 h du matin n'est vue qu'à l'ouverture du tableau de bord. Ne pas le faire, c'est garder une maquette qui se visite et ne se travaille pas.

## 2. Objectifs et non-objectifs

**Objectifs**

- O1. **Une seule page** : après la connexion, naviguer entre les 305 écrans ne recharge jamais le document ; le magasin est chargé une fois, puis tenu à jour par **deltas**. Cible : écran suivant peint en moins de **300 ms** sur un poste de la clinique.
- O2. **Les écrans ne changent pas** : la déclaration `SIGH.screen(id, {…})`, le kit, le manifeste `nav.js`, les parcours et les bancs d'essai restent ; la conversion touche `app.js`, `store.js`, `gen-pages.js` et l'API, pas les 300 écrans (décision « ne pas réécrire l'interface », 23/09/2026).
- O3. **Les postes se voient** : une écriture faite sur un poste est visible sur les autres en moins de **5 secondes** sans geste de l'utilisateur (flux d'événements du serveur), et la cloche sonne sur le poste **concerné**.
- O4. **Le serveur travaille sans écran ouvert** : des tâches planifiées (échéances fiscales, péremptions, rendez-vous du lendemain, sauvegarde nocturne, file MECeF, relances) tournent à heure fixe et produisent des notifications persistées, lues par le poste à sa prochaine synchronisation.
- O5. **Rien ne régresse** : 0 erreur JS, 0 lien cassé, 67 scénarios, audit RBAC à 0 promesse, et les adresses profondes (`pages/m8-caisse.php`, `#onglet=`) continuent d'ouvrir le bon écran.

**Non-objectifs**

- Réécrire les écrans en Vue, React ou tout autre cadre : hors décision de la Direction, et sans gain pour les 305 écrans existants.
- Un serveur accessible depuis Internet : hors périmètre CDCT §4.3 ; le serveur reste celui de la clinique, sur son réseau.
- Remplacer PostgreSQL ou le modèle « une ligne par collection » : ce PRD ajoute un journal d'événements à côté, il ne refond pas le schéma (c'est la phase P1/P3 de l'architecture cible, après le banc de synchronisation).
- Le poste de bureau (Tauri) et la base SQLite locale : phase P2 de l'architecture cible. Ce PRD en est la **condition** (une interface qui vit dans un seul document), pas l'exécution.
- Les notifications par SMS ou courriel : aucun canal sortant n'existe ni n'est demandé.

## 3. Utilisateurs et rôles

| Rôle | Ce qui change pour lui |
|---|---|
| Tous les postes | navigation instantanée ; la cloche vit sans rechargement ; un geste d'un autre poste apparaît dans ses files (caisse, labo, pharmacie) sans rafraîchir |
| Accueil | la prise de rendez-vous prévient le praticien **sur son poste** dans les 5 s |
| Caisse | la file des prescriptions à encaisser se met à jour seule |
| Laboratoire | « échantillon reçu » et « résultat rendu » circulent entre salle de prélèvement, labo et prescripteur sans rechargement |
| Comptable, DAF, Direction | les échéances dépassées, créances âgées et seuils de BFR sont calculés **la nuit** par le serveur et présents à l'ouverture |
| Gestionnaire de stock | péremptions et ruptures calculées chaque nuit ; une tâche nommée par article, dédupliquée |
| Administrateur | voit l'état des tâches planifiées (dernière exécution, durée, erreurs) et le journal des événements |

Ce que l'écran dit : la pastille d'état de connexion (« synchronisé il y a 3 s », « hors ligne depuis 12 min — 7 gestes en attente ») est **permanente** dans le bandeau ; un geste fait hors ligne est accepté, mis en file, et rejoué quand le serveur répond (mécanisme existant : écriture refusée reprogrammée).

## 4. Parcours

1. **Connexion** → une seule page `app.php` : coquille, ruban, puis chargement du magasin (une fois), puis premier écran.
2. **Navigation** : `app.go(id)` charge le fichier du module s'il ne l'est pas encore, rend l'écran dans `#page-content`, met à jour ruban, fil d'Ariane, titre, adresse (`history.pushState`). Retour arrière du navigateur = écran précédent.
3. **Écriture** : inchangée côté écran ; le magasin pousse le **delta** et reçoit en retour le **numéro d'événement** attribué par le serveur.
4. **Réception** : le poste tient un flux `api/flux.php` (SSE) ; chaque événement porte la collection et l'identifiant touchés ; le magasin applique et **notifie les écrans ouverts** (`S.on('change')`, existant) — le tableau se rafraîchit sans que l'agent fasse quoi que ce soit.
5. **Notification** : le moteur existant (`notifications.js`) cesse de recalculer tout à chaque tour ; il **consomme** les événements reçus et les notifications persistées par le serveur, route par poste, sonne selon les paramètres.
6. **Nuit** : le planificateur du serveur exécute les tâches à leur heure ; chacune écrit ses notifications et son compte rendu d'exécution ; le matin, les postes les lisent.
7. **Hors ligne** : le serveur ne répond plus → la pastille change, la navigation continue (tout est déjà chargé), les gestes s'empilent ; retour du serveur → la file part, le flux se rouvre depuis le dernier événement connu.

## 5. Exigences fonctionnelles

| Réf. | Énoncé | Source | Règles | Critère d'acceptation |
|---|---|---|---|---|
| EF-SOC-01 | **Routeur en document unique** dans `app.js` : `go(id, opts)` rend l'écran sans rechargement ; `pushState` ; `popstate` restaure ; l'ancre `#onglet=` est honorée (`U.tabs`) ; le drapeau `ruban-transitoire` et la préférence du ruban sont conservés | demande 20/10 | — | Scénario : vingt navigations successives, `performance.navigation` ne compte qu'un chargement, chaque écran peint < 300 ms sur le banc |
| EF-SOC-02 | **Chargement paresseux des modules** : le fichier d'un module se charge à la première demande (balise `script` ajoutée), une fois ; `MODULE_FILES` de `gen-pages.js` devient la table du routeur (source unique) | vague 66 (`N.EXT` unique) | — | Un module jamais visité n'est jamais téléchargé ; un écran d'un module déjà chargé n'émet aucune requête de script |
| EF-SOC-03 | **Les adresses profondes vivent** : `pages/<id>.php` reste engendré (dix lignes) et se contente de rediriger la coquille sur l'écran ; `check.js` continue d'ouvrir les 306 pages | doctrine « jamais de lien écrit à la main » | — | 0 lien cassé ; un signet vers `pages/m8-caisse.php#onglet=registre` ouvre l'onglet |
| EF-SOC-04 | **Le montage ne peint qu'une fois par écran** et détruit proprement le précédent (minuteries, écouteurs du document, tiroirs, toasts) ; chaque écran peut déclarer `demonter()` | vague 66 (`boot` peint une fois) | — | Après cent navigations, aucune fuite mesurable : minuteries actives = celles de l'écran courant + le moteur de notification |
| EF-SOC-05 | **Hydratation unique** puis **deltas** : `api/magasin.php?depuis=<seq>` rend les collections changées depuis la séquence ; le magasin tient `seq` ; plus aucun rechargement de 4,8 Mo après la connexion | demande 20/10 | — | Mesure : volume transféré pour vingt écrans < 200 Ko hors premier chargement |
| EF-SOC-06 | **Journal d'événements serveur** : table `evenements` (seq, horodatage, poste, utilisateur, collection, ficheId, type, résumé) alimentée à chaque POST accepté ; c'est la première pierre du journal d'opérations de l'ADR-0001 | ADR-0001 | RG-12 | Chaque écriture acceptée porte un `seq` ; `GET ?depuis=` rend exactement les événements postérieurs |
| EF-SOC-07 | **Flux `api/flux.php`** (SSE, repli : long-polling) : pousse les événements aux postes connectés, filtrés par ce que le rôle a le droit de voir (RG-13 appliqué au serveur sur la collection) ; reconnexion automatique depuis le dernier `seq` | demande 20/10 | RG-13 | Deux navigateurs : une fiche créée sur A apparaît sur B en < 5 s ; un caissier ne reçoit aucun événement de `demandesAnalyses` (résultats) |
| EF-SOC-08 | **Le moteur de notification consomme** : `notifications.js` lit les événements et les notifications persistées (`notifications`, existante) au lieu de rebalayer les collections à chaque tour ; le regroupement, le routage par poste, l'acquittement et le son restent | vague 36 | — | Une alerte produite par le serveur la nuit est à la cloche à l'ouverture ; aucune donnée médicale dans le message |
| EF-SOC-09 | **Planificateur serveur** : `api/cron.php` exécuté par le planificateur du système (cron Linux ou Planificateur de tâches Windows, toutes les 5 min) ; il lit un **registre des tâches** (`tachesPlanifiees` : nom, expression horaire, dernière exécution, durée, état, erreur) et exécute celles qui sont dues, en **une seule instance** (verrou en base) | demande 20/10 (« cron jobs ») | RG-12 | Deux lancements simultanés n'exécutent qu'une fois ; l'écran `m14-taches-planifiees` montre l'historique |
| EF-SOC-10 | **Tâches planifiées livrées** : (1) échéances fiscales dépassées et à J-7 (D.CALENDRIER_FISCAL) ; (2) péremptions FEFO à J-30/J-7 et ruptures sous seuil (RG-05) ; (3) rendez-vous du lendemain par praticien ; (4) créances assureur au-delà du seuil (`objectifsPilotage`) ; (5) file MECeF en attente — reprise de certification ; (6) sauvegarde nocturne (`pg_dump` chiffré, registre `fichiersSauvegarde`) ; (7) purge des sessions expirées | vagues 22, 28, 36, 64 | RG-05, RG-12 | Chaque tâche écrit **une** notification par cause, dédupliquée tant que la cause dure (doctrine « entendre n'est pas traiter ») |
| EF-SOC-11 | **La règle vit au module, pas au planificateur** : chaque tâche appelle le moteur existant (`PR.alertesRecouvrement`, calcul des échéances, FEFO) — en PHP, par **réexécution du moteur JavaScript côté serveur** (Node sur le hub) ou par portage dans `packages/domaine` ; aucune règle n'est réécrite deux fois | doctrine « une règle vit à un endroit » | — | Changer un seuil dans `objectifsPilotage` change la tâche sans la modifier |
| EF-SOC-12 | **Pastille d'état** permanente : synchronisé / en retard / hors ligne, avec le nombre de gestes en attente et l'heure du dernier événement reçu ; cliquable vers un écran de diagnostic | doctrine « une restriction s'annonce » | — | Serveur coupé : pastille rouge en < 10 s, navigation toujours possible, gestes en file ; serveur rendu : file vidée, pastille verte |
| EF-SOC-13 | **Session** : le verrouillage à 15 min et le retour à l'écran exact (`auth-lock`) fonctionnent dans le document unique ; le jeton expire côté serveur et le flux se ferme | vague 22, 66 | CDCT §12.2 | Scénario de verrou existant vert sans rechargement |
| EF-SOC-14 | **Bancs d'essai** : `test`, `check`, `audit-rbac`, `inventaire-rbac` passent par le routeur (`ouvrir()` navigue en document unique) ; un banc « deux navigateurs » mesure le délai de propagation | — | — | 67/67 scénarios, 0 promesse, délai mesuré < 5 s |

## 6. Données

- Nouvelles tables serveur : `evenements` (journal, append-only), `taches_planifiees` + `executions_taches` ; nouvelle collection `tachesPlanifiees` lue par M14 → **`VERSION` incrémentée** (collection semée au socle : les tableaux de bord et M14 la lisent).
- `notifications` existante : champ `origine: 'serveur'`, `tache`, `seq`.
- Le magasin tient `_seq` (méta) : dernier événement appliqué.

## 7. Hors ligne et synchronisation

C'est le cœur du PRD : le document unique rend le poste **capable de travailler sans serveur** avec ce qu'il a déjà chargé (il ne l'était pas : chaque navigation exigeait le serveur). La file de gestes existante (écriture refusée → reprogrammée) devient visible (pastille) et **persistée** (`localStorage` / IndexedDB) pour survivre à une fermeture du navigateur. Familles de fusion : inchangées par rapport à l'ARCHITECTURE-CIBLE §6.4 ; ce PRD ne livre **pas** encore la fusion par champ ni les tranches de numéros (P1/P3) — un conflit entre deux postes reste, comme aujourd'hui, « le dernier delta de collection gagne », et **l'écran de diagnostic le dit** jusqu'à la livraison du journal d'opérations.

## 8. Impression et états

Inchangés : `P.etat` et `P.ticket` ouvrent l'aperçu dans le document unique ; `window.print()` imprime l'aperçu seul (feuille de style d'impression existante). Vérification : les 159 `P.tableau` continuent de passer les sondes de totaux.

## 9. Ce qui n'est pas documenté

- Les **fréquences** des tâches (5 min, nuit à 2 h) et le **délai de propagation** cible (5 s) sont des propositions.
- Le choix **SSE plutôt que WebSocket** : SSE passe par le serveur intégré de PHP et Apache sans module ; à confirmer sur le réseau de la clinique (proxy, Wi-Fi).
- L'exécution des moteurs côté serveur (Node sur le hub) anticipe l'architecture cible ; elle suppose **Node.js installé sur le serveur de la clinique** — à arbitrer (§10).

## 10. Questions ouvertes pour la Direction

1. Le serveur de la clinique peut-il porter **Node.js** à côté de PHP (pour exécuter les mêmes moteurs que le poste), ou faut-il tout tenir en PHP au prix d'une seconde implémentation des règles ? (recommandation : Node sur le hub — c'est le chemin de l'ADR-0001)
2. Quelles tâches planifiées **sonnent** au poste concerné à leur réveil (péremption critique, échéance dépassée) et lesquelles restent silencieuses jusqu'à l'ouverture ? (recommandation : seules les critiques sonnent, dans les heures d'ouverture)
3. Le document unique doit-il être livré **avant** le banc de synchronisation de P1, ou avec lui ? (recommandation : avant — il ne change pas le modèle de données et débloque l'usage quotidien)

## 11. Priorités

- **P0** : EF-SOC-01 à 05, 12, 13, 14 (document unique, modules paresseux, adresses profondes, hydratation unique + deltas, pastille, session, bancs).
- **P1** : EF-SOC-06 à 10 (journal d'événements, flux, moteur consommateur, planificateur et les sept tâches).
- **P2** : EF-SOC-11 (moteurs exécutés au serveur depuis `packages/domaine`) — s'aligne sur P3 de l'architecture cible.

## 12. Indicateurs

- Avancés : temps de peinture d'un écran (médiane < 300 ms, mesure du banc) ; volume transféré par session ; délai de propagation entre deux postes (< 5 s) ; nombre d'erreurs JS (0).
- Retardés : nombre de rechargements manuels par jour et par poste (journal) tendant vers zéro ; échéances fiscales vues avant leur date (100 % notifiées à J-7) ; aucun rendez-vous « non honoré » faute de rappel au praticien.
