# PRD — Socle : la synchronisation bidirectionnelle entre le poste, le hub, le client web et l'application mobile

Statut : **brouillon** du 26/10/2026, à arrêter par la Direction
Sources : demande de la Direction du 26/10/2026 (« synchronisation bidirectionnelle web/app et poste ») · ADR-0001 (postes autonomes, hub en étoile, journal d'opérations) · ADR-0003 (pile Flutter/Dart, MECeF boîtier physique) · ARCHITECTURE-CIBLE.md §6 · PRD-SOCLE-application-sans-rechargement (EF-SOC-05 à 07, partiellement livrés) · vague 70 (journal d'événements, relecture ciblée, pastille) · RG-01, 03, 10, 12, 13, 14 · CDCT §4.3 (hors périmètre : cloud d'usage courant, portail patient)

## 1. Problème

La clinique veut que **ce qui est saisi à un endroit apparaisse aux autres** — création, modification, suppression — sur le poste de bureau, sur le client web et sur le téléphone, **sans jamais perdre une saisie** et **sans qu'une coupure de courant ou de réseau arrête le travail**. Aujourd'hui, le prototype tient la moitié de la promesse :

- les postes qui partagent le serveur PHP/PostgreSQL **se voient** (journal `evenements`, sondage toutes les 3 s, relecture ciblée des collections touchées, pastille d'état), mais **un poste coupé du serveur ne peut ni écrire durablement ni naviguer sur un écran qu'il n'a pas chargé** ;
- un conflit est tranché en silence : **le dernier geste arrivé gagne**. Deux postes qui modifient la même fiche — ou, par le chemin « collection entière » de `api/magasin.php`, deux fiches de la même collection — se piétinent sans que personne le sache ;
- la file de gestes en attente vit **en mémoire** : fermer l'onglet hors ligne la perd ;
- les numéros (code patient `CNT/n/AA`, pièces certifiantes, codes d'analyse) sont attribués par le seul serveur : un poste hors ligne ne peut pas en émettre ;
- le serveur est unique et c'est lui qui est l'autorité ; il n'existe ni poste autonome (SQLite), ni application mobile.

Une synchronisation « qui marche quand tout va bien » est un piège dans un établissement de santé : le jour de la panne, deux agents ont écrit chacun de leur côté, et **c'est ce jour-là qu'on a besoin que rien ne soit écrasé**. Ne pas cadrer ce chantier, c'est livrer le poste de bureau et le mobile avec le seul comportement que le prototype a par accident.

## 2. Ce que « synchroniser dans les deux sens » signifie ici

Le texte de référence fourni par la Direction décrit les besoins génériques : une création, une modification ou une suppression faite d'un côté **se propage de l'autre** ; un conflit produit une **copie de conflit** plutôt qu'une perte ; il faut de la vigilance sur le hors ligne et l'écrasement. Pour SIGH-CNT, cela se traduit ainsi — et c'est la partie à lire avec attention, car **trois lectures du texte générique sont fausses pour des données de santé** :

| Notion générique | Traduction SIGH-CNT | Pourquoi |
|---|---|---|
| Création / modification se propagent | Chaque geste est une **opération** (UUID v7, horloge hybride, auteur, poste) envoyée au hub, ordonnée par une **séquence posée par le hub**, puis redistribuée aux autres appareils | ADR-0001 : on synchronise des gestes, pas des états |
| **Suppression** se propage | **Il n'y a pas de suppression.** Le geste propagé est l'**archivage** (RG-14) : la fiche reste, marquée archivée, restaurable | Une suppression propagée par erreur est irréversible ; un patient « supprimé » d'un côté ressortirait de l'autre |
| **Copie de conflit** (« fichier (conflit) ») | **Jamais de copie silencieuse** : un conflit sur un invariant devient une **tâche nommée** visible du poste responsable ; un conflit sur un champ descriptif est fusionné **champ par champ** et journalisé | Une copie de fiche patient en double viole RG-01 ; une copie de lot de stock viole RG-03 |
| Outils de synchronisation de fichiers (OneDrive, Dropbox, Nextcloud, Syncthing, rclone, FreeFileSync) | **Réservés aux fichiers** : pièces numérisées (GED), sauvegardes, réplica hors site. **Jamais** pour les données métier | Ils comparent des dates de fichiers, ne connaissent ni les invariants ni les droits, et résolvent un conflit en gardant « le plus récent » |
| Git comme synchronisation | Valable pour le **code et les référentiels versionnés** (`packages/referentiels`), pas pour les données opérationnelles | — |
| API REST bidirectionnelle | **Oui, pour le chemin hub ↔ appareil** : points d'entrée `push` (opérations) et `pull` (depuis la séquence N), idempotents | C'est le contrat de l'ADR-0001 |
| Vigilance hors ligne | **Fonction de premier rang** : file persistée, numéros provisoires, pastille permanente, rejeu idempotent | Une file en mémoire est une saisie perdue |

## 3. Les appareils, et ce que « web » veut dire (à arbitrer, §10-Q1)

| Appareil | Base locale | Rôle | Statut |
|---|---|---|---|
| **Poste de bureau** (Windows/Linux) | SQLite chiffrée (SQLCipher) | autonome ; écrit même hub arrêté ; la **caisse** porte le boîtier MECeF | cible (ADR-0003), non portée |
| **Application mobile** (Android) | SQLite chiffrée, sous-ensemble de données | consultation, saisies courtes, tâches ; **aucune émission fiscale** | cible, non portée |
| **Hub** de la clinique | PostgreSQL (autorité) | ordonne, vérifie les invariants et les droits, redistribue | cible ; aujourd'hui le serveur PHP en tient la place |
| **Client web** (navigateur) | **mémoire + stockage du navigateur** | voir ci-dessous | prototype actuel |

**« Web » peut signifier deux choses, et elles n'ont pas les mêmes conséquences :**

1. **Le client navigateur sur le réseau de la clinique** (c'est le prototype d'aujourd'hui, et la voie de repli si un poste n'est pas installable). Il est un client **léger** : il lit l'état du hub, écrit par opérations, et **n'est pas une autorité** — le cache d'un navigateur n'est pas un support de données de santé (ADR-0003, option F écartée). Il se synchronise par le même contrat que les autres appareils, avec une file persistée (IndexedDB).
2. **Un accès depuis Internet** (un médecin depuis chez lui, un partenaire). Cela **ouvre le hub à Internet**, ce que l'ADR-0003 interdit et que le CDCT §4.3 place hors périmètre. Si la Direction le veut, c'est une **décision d'architecture distincte** (ADR dédiée, VPN d'entreprise ou passerelle publique séparée qui se synchronise ensuite) — **ce PRD ne la décide pas**.

## 4. Objectifs et non-objectifs

**Objectifs**

- O1. **Aucune opération perdue** : toute opération acceptée localement est livrée au hub exactement une fois, même après coupure, fermeture brutale ou redémarrage du poste. Mesure : banc de coupure, 0 perte sur 1 000 opérations.
- O2. **Convergence** : après rétablissement, tous les appareils concernés affichent le même état, et le délai de propagation en fonctionnement normal est **< 5 s** (95ᵉ centile, 15 postes + 5 téléphones écrivant en continu).
- O3. **Aucun écrasement silencieux** : deux gestes concurrents sur la même fiche ne laissent jamais « le dernier gagne » sans trace. Chaque conflit est fusionné par règle (famille de fusion) **ou** rendu visible comme tâche nommée.
- O4. **Les invariants tiennent hors ligne** : RG-01 (un seul code par patient), RG-03 (stock jamais négatif), RG-10 (écriture équilibrée), numérotation des pièces — sans doublon ni trou injustifié.
- O5. **Les droits voyagent avec les données** : un appareil ne reçoit que ce que son rôle a le droit de voir (RG-13), appliqué **au hub**, pas seulement à l'écran.
- O6. **Le travail hors ligne est visible** : la pastille dit « synchronisé / en retard / hors ligne depuis N min — N gestes en attente », et chaque pièce en suspens porte son état.

**Non-objectifs**

- Un maillage poste à poste sans hub (ADR-0001 : sans autorité, un stock négatif passerait).
- Synchroniser des données métier avec un outil de fichiers (OneDrive, Dropbox, Syncthing…).
- Ouvrir le hub à Internet (CDCT §4.3) — voir §3, question Q1.
- Fusionner automatiquement ce qui engage un tiers ou le fisc : une **pièce émise** (facture normalisée, avoir, compte rendu validé) ne se fusionne pas, elle est **immuable**.
- Réécrire les 305 écrans du prototype pour y parvenir (décision du 23/09/2026) : le contrat de lecture synchrone du `store` est conservé.
- Une synchronisation en « temps réel strict » : un délai de quelques secondes est suffisant et assumé.

## 5. Utilisateurs et rôles

| Rôle | Ce qu'il voit | Ce qu'il fait | Ce qu'il ne doit PAS voir (RG-13) |
|---|---|---|---|
| Tous les postes | pastille d'état, ses gestes en attente, ses pièces « provisoires » | travaille hors ligne | — |
| Accueil | dossiers et rendez-vous synchronisés | crée un dossier hors ligne (code provisoire) | résultats d'analyses, données financières |
| Caissier | sa file d'encaissement, le statut MECeF | encaisse hors ligne (boîtier branché à la caisse) | dossier médical, comptabilité |
| Médecin, sage-femme | dossiers de ses patients, résultats validés | prescrit hors ligne | finances |
| Gestionnaire de stock | stock, lots, **conflits de stock à régulariser** | sort/transfère ; traite la tâche de conflit | dossier médical |
| Comptable, DAF | écritures, pièces provisoires à régulariser | valide | dossier médical |
| Administrateur | journal des opérations, appareils enrôlés, file de rejeu, conflits ouverts | **révoque un appareil**, relance un rejeu | — |
| Mobile (tout rôle) | sous-ensemble limité au rôle ; **aucune** donnée hors du périmètre du rôle | consulte, saisit court | émission fiscale impossible |

Ce que l'écran dit au rôle exclu : un écran fermé au rôle reste fermé hors ligne ; une donnée non autorisée **n'est jamais envoyée** à son appareil (elle n'est pas masquée à l'écran, elle est absente du disque).

## 6. Parcours

1. **Enrôlement d'un appareil** — l'administrateur enrôle un poste ou un téléphone (identifiant d'appareil, clé de chiffrement de la base locale conservée dans le coffre du système). Un appareil non enrôlé ne reçoit rien.
2. **Première synchronisation** — l'appareil télécharge un **instantané** de ce que son rôle peut voir, plus la séquence `N` du hub.
3. **Travail normal** — chaque geste est appliqué **localement d'abord** (le poste répond immédiatement), inscrit au journal local, puis envoyé (`push`). Le hub valide (droits, invariants), attribue la séquence, répond. Les autres appareils reçoivent l'opération au prochain `pull` ou par notification.
4. **Coupure** — le hub ne répond plus : le poste continue, la pastille change, les opérations s'accumulent dans la file **persistée**. Les numéros émis sont **provisoires** et annoncés comme tels.
5. **Rétablissement** — la file part dans l'ordre ; chaque opération est **idempotente** (rejouée deux fois, effet unique). Le hub accepte, fusionne ou refuse **en nommant la cause**.
6. **Conflit d'invariant** — le second de deux gestes incompatibles (dernier lot sorti deux fois) est **mis en conflit**, jamais appliqué : le hub crée une **tâche nommée** pour le poste responsable (gestionnaire de stock, caisse, DAF), avec les deux gestes côte à côte. Le geste refusé n'est pas détruit : il reste au journal de l'appareil d'origine.
7. **Régularisation des numéros** — un code provisoire est remplacé par le définitif à l'arrivée au hub ; les pièces déjà imprimées portent la mention « provisoire » et la correspondance est tracée.
8. **Perte ou vol d'un appareil** — l'administrateur révoque l'appareil ; à sa prochaine connexion, il est refusé et sa base locale est inutilisable sans le coffre.
9. **Poste réinstallé** — il se ré-hydrate depuis le hub ; ses opérations jamais livrées, si le disque est lisible, sont récupérées du journal local avant l'effacement.

## 7. Exigences fonctionnelles

| Réf. | Énoncé | Source | Règles | Critère d'acceptation |
|---|---|---|---|---|
| EF-SYNC-01 | **Chaque écriture est une opération** : identifiant UUID v7, horloge hybride (HLC), appareil, utilisateur, collection, fiche, type (`creer` / `modifier` / `archiver` / `restaurer`), charge utile **par champ modifié**, version de schéma | ADR-0001 | RG-12 | Aucune écriture n'atteint le hub sans ces champs ; rejouer deux fois la même opération laisse l'état identique |
| EF-SYNC-02 | **Application locale d'abord** : le geste est visible immédiatement sur l'appareil qui l'émet, avant tout aller-retour au hub | ADR-0001 | — | Hub coupé, un dossier créé est lisible à l'écran du poste en < 300 ms |
| EF-SYNC-03 | **File persistée** : les opérations non livrées survivent à la fermeture de l'application, au redémarrage, à la coupure de courant (SQLite poste/mobile, IndexedDB client web) | vague 70 (file en mémoire = limite connue) | RG-12 | Banc : tuer le processus en pleine écriture → au redémarrage, 0 opération perdue, 0 doublon |
| EF-SYNC-04 | **Points d'entrée du hub** `push(opérations)` et `pull(depuis=N)` : idempotents, authentifiés par appareil + session, limités par rôle ; réponse nommant chaque opération acceptée, fusionnée ou refusée | ADR-0001 | RG-13 | Une opération d'un appareil révoqué ou d'un rôle non autorisé est refusée avec sa cause |
| EF-SYNC-05 | **Séquence posée par le hub** : le hub attribue un `seq` croissant sans trou ; un appareil se met à jour en demandant « tout après `seq` » | EF-SOC-05/06 | — | Deux appareils appliquant le même flux d'opérations aboutissent à des états identiques |
| EF-SYNC-06 | **Quatre familles de fusion** déclarées pour **chaque** collection (§8) : fiche descriptive, journal append-only, pièce émise immuable, agrégat à invariant | ADR-0001 | RG-01, 03, 10 | Le dictionnaire des données porte la famille de chaque collection ; une collection sans famille est refusée à la génération du schéma |
| EF-SYNC-07 | **Fusion par champ pour les fiches descriptives** : deux appareils qui modifient des champs différents de la même fiche voient les deux changements conservés ; le même champ modifié des deux côtés crée un **conflit nommé** (valeur A / valeur B / auteurs / heures), pas un « le dernier gagne » | O3 | RG-12 | Banc : A change le téléphone, B change le quartier → les deux sont conservés ; A et B changent le téléphone → une tâche de conflit apparaît, la valeur en vigueur est celle du hub jusqu'à décision |
| EF-SYNC-08 | **Archivage au lieu de suppression** : le geste « supprimer » de l'interface produit une opération `archiver` ; un appareil ne peut ni émettre ni appliquer une suppression physique ; une fiche archivée sur un appareil et **modifiée** sur un autre produit un conflit nommé, pas une résurrection silencieuse | RG-14 | RG-14 | Le hub refuse toute opération `supprimer` en le disant ; archiver A puis modifier B → tâche « fiche archivée modifiée » |
| EF-SYNC-09 | **Agrégats à invariant — stock** : le hub rejoue les sorties dans l'ordre des séquences ; une sortie qui rendrait le stock négatif est **refusée à l'arrivée** et devient une tâche pour le gestionnaire de stock, avec l'ordonnance en cause | RG-03 | RG-03 | Banc : deux postes sortent le dernier lot hub arrêté → au rétablissement, le second geste est en conflit, le stock vaut 0 et jamais moins |
| EF-SYNC-10 | **Numérotation par tranches avec numéro provisoire** : chaque poste reçoit du hub des plages de numéros (code patient, pièces, codes d'analyse) ; plage épuisée hors ligne → numéro **provisoire** (`P-<poste>-<n>`) annoncé à l'écran et sur la pièce, remplacé à l'arrivée au hub avec trace de correspondance | RG-01 | RG-01 | Banc : deux postes créent chacun 50 dossiers hub arrêté → 0 doublon de `CNT/n/AA` ; les provisoires sont tous régularisés |
| EF-SYNC-11 | **Pièces émises immuables** : une facture normalisée MECeF, un avoir, un compte rendu validé, une écriture validée ne se fusionnent pas ; une correction est une **nouvelle pièce** (avoir, rectification) qui référence la première | RG-10, vague 42 | RG-10, RG-14 | Une opération `modifier` sur une pièce émise est refusée en nommant le chemin (avoir / rectification) |
| EF-SYNC-12 | **Droits appliqués au hub** : `pull` ne renvoie que les collections et fiches que le rôle peut lire (matrice RBAC portée au hub, pas seulement au client) ; `push` vérifie le droit d'écrire par module et par écran | RG-13 | RG-13 | Un caissier ne reçoit aucune fiche `demandesAnalyses` ; une écriture forcée hors droit est refusée et journalisée |
| EF-SYNC-13 | **Boîtier MECeF** : la certification est locale à la caisse ; la file sortante MECeF est distincte du journal d'opérations ; le numéro fiscal vient **toujours** du boîtier ; la facture est synchronisée **après** certification, avec son numéro | ADR-0003 | — | Hub arrêté et Internet coupé, une facture est certifiée et imprimée ; au rétablissement elle arrive au hub avec son numéro, sans doublon |
| EF-SYNC-14 | **Pastille et diagnostic** : état permanent (synchronisé / en retard / hors ligne), nombre d'opérations en attente, heure de la dernière synchronisation ; écran de diagnostic listant la file, les conflits ouverts et les refus | EF-SOC-12 | — | Hub coupé : pastille rouge en < 10 s, navigation et saisie toujours possibles ; rétabli : file vidée |
| EF-SYNC-15 | **Écran « Conflits à régulariser »** : liste des tâches de conflit par poste responsable, avec les deux versions, l'auteur et l'heure de chacune, et la décision (garder A, garder B, fusionner à la main) **journalisée** | O3 | RG-12 | Une décision produit une opération qui part au hub ; la tâche disparaît des autres postes |
| EF-SYNC-16 | **Enrôlement et révocation d'appareil** : liste des appareils (nom, rôle, dernière synchronisation), révocation immédiate au prochain contact ; base locale chiffrée dont la clé est dans le coffre du système | ADR-0003 | RG-13 | Disque copié : base illisible sans le coffre ; appareil révoqué : `push`/`pull` refusés |
| EF-SYNC-17 | **Instantané et ré-hydratation** : un appareil neuf ou réinstallé se met à jour par un instantané filtré par rôle puis par le flux ; le hub sait reconstruire un instantané depuis le journal | ADR-0001 | — | Poste réinstallé : état identique à l'instantané du hub, vérifié par somme de contrôle |
| EF-SYNC-18 | **Fichiers (GED, scans, sauvegardes)** : synchronisés séparément des données, par **empreinte** (SHA-256), en deux temps (métadonnées d'abord, binaire ensuite, reprise sur coupure), jamais par date ; un binaire modifié est une nouvelle version, l'ancienne est conservée | RG-14, vague 70 (GED) | RG-14 | Fichier modifié des deux côtés → deux versions conservées et un conflit nommé, aucune écrasée |
| EF-SYNC-19 | **Réplica hors site** : copie chiffrée de la sauvegarde du hub vers un second site, par un outil de **fichiers** (rclone, Syncthing, ou équivalent), sans jamais bloquer l'usage courant ; restauration à blanc périodique | ADR-0003, CDCT §4.3 | — | Une restauration depuis le réplica rend un hub identique (parité vérifiée) |
| EF-SYNC-20 | **Horloges** : l'horloge locale d'un poste peut dériver ; l'ordre d'application repose sur la séquence du hub et l'HLC, pas sur l'heure murale ; une dérive > 2 min est signalée à l'administrateur | — | — | Poste réglé à +1 h : l'ordre des opérations reste correct, une alerte est émise |

## 8. Données et familles de fusion

Chaque collection du dictionnaire des données (`docs/architecture/DICTIONNAIRE-DONNEES.md`, 139 tables dans 18 schémas) reçoit **une** famille. Propositions initiales, à valider écran par écran avec la spec correspondante (`/spec` §6) :

| Famille | Règle de fusion | Exemples de collections |
|---|---|---|
| **A. Fiche descriptive** | fusion **par champ** ; même champ modifié des deux côtés → conflit nommé | `patients` (identité, coordonnées), `personnel`, `assureurs`, référentiels administrables, `rendezvous` |
| **B. Journal append-only** | union des lignes, jamais de modification ; l'ordre est la séquence | `audit`, `constantes`, `temperatures`/`releves`, `mouvements` (de stock), `notifications`, `evenements` |
| **C. Pièce émise immuable** | aucune fusion ; correction = nouvelle pièce liée | `factures` normalisées, `avoirs`, `ecritures` validées, comptes rendus **validés** (labo, imagerie), certificats délivrés, bulletins de paie validés |
| **D. Agrégat à invariant** | le hub **rejoue et vérifie** ; l'opération qui violerait l'invariant est mise en conflit | `stock` / lots (RG-03), numérotation (RG-01), lit occupé (un lit = une admission active), clôture d'exercice (exercice clos en lecture seule) |

Nouveaux objets de données (→ **incrément de `VERSION`**, collections semées au socle, **taille mesurée avant semis** — le quota du poste est la contrainte, vague 64) :

- côté hub : `operations` (journal append-only, jamais modifié), `appareils`, `plages_numeros`, `conflits`, `curseurs` (dernier `seq` par appareil) ;
- côté appareil : `file_sortante` (persistée), `curseur_local`, `numeros_provisoires`.

Chaque fiche gagne un champ de **version de fiche** (HLC de la dernière opération appliquée) pour permettre la fusion par champ.

## 9. Hors ligne et synchronisation (le cœur du document)

- **Ce qui est possible hors ligne** : tout ce qui est déjà chargé et autorisé au rôle — consulter, créer un dossier (code provisoire), prescrire, encaisser (le boîtier MECeF est local à la caisse), enregistrer une constante, sortir un article.
- **Ce qui ne l'est pas, et que l'écran dit** : émettre une pièce qui exige l'autorité du hub — régularisation d'un numéro, validation comptable partagée, clôture d'exercice, restauration d'un archivé par un autre poste. Le bouton reste **visible et verrouillé**, avec le motif (« nécessite le hub »).
- **Deux postes agissent sans hub sur la même donnée** : selon la famille — A fusion par champ ou conflit nommé ; B union ; C impossible (la pièce n'existe que sur l'appareil émetteur jusqu'à son arrivée) ; D mise en conflit au rejeu.
- **Ce que l'écran dit d'une opération en suspens** : « envoyé / en attente (N) / refusé — cause » à côté de la pièce ; numéro « provisoire » ; liste des conflits au bandeau pour le poste responsable.
- **Le prototype jusqu'à la livraison** : reste en « dernier geste gagne », et **l'écran de diagnostic le dit** (EF-SOC-12). Ce PRD ne prétend pas que le prototype soit conforme.

## 10. Impression et états

Les pièces imprimées hors ligne portent la mention **« provisoire »** tant que leur numéro n'est pas régularisé ; la correspondance provisoire → définitif est conservée et imprimable. L'état « Journal de synchronisation » (opérations, conflits, décisions) est un état officiel archivable (en-tête légal unique, pied normalisé). Les tickets MECeF ne portent jamais de numéro provisoire : le numéro fiscal vient du boîtier.

## 11. Ce qui n'est pas documenté

- Le **moteur de synchronisation** (PowerSync, ElectricSQL ou moteur maison) : **ADR-0004 à écrire après le banc**. Ce PRD décrit le comportement attendu, pas l'outil.
- Les **tailles de tranches de numéros** et les seuils de réapprovisionnement de plage : propositions à calibrer sur le volume réel (≈ 18 000 dossiers, ~30 agents, quelques dizaines de créations par jour).
- La liste exacte des **collections visibles par le mobile** : proposition à valider rôle par rôle.
- Les **délais** (5 s, 10 s, 300 ms) sont des cibles à valider sur le matériel et le réseau réels de la clinique (Wi-Fi, onduleur, coupures).
- Le **modèle, l'interface et le protocole du boîtier MECeF** ne figurent dans aucun document du dépôt (ADR-0003, dix questions au fournisseur et à la DGI).

## 12. Questions ouvertes pour la Direction

| # | Question | Qui répond | Recommandation | Bloquante ? |
|---|---|---|---|---|
| Q1 | **« Web » = navigateur sur le réseau de la clinique, ou accès depuis Internet ?** | Direction | Réseau de la clinique d'abord ; un accès Internet est une ADR séparée (VPN ou passerelle publique distincte) | **Oui** |
| Q2 | Quels rôles ont besoin du **mobile**, et pour quels gestes (consulter, tâches, constantes, rendez-vous) ? | Direction + chefs de service | Consultation et tâches ; saisies courtes (constantes) ; jamais d'émission fiscale | Oui, pour la portée du mobile |
| Q3 | Quand deux agents modifient **le même champ** d'une fiche patient, qui arbitre ? | Direction médicale + accueil | L'accueil pour l'état civil, le médecin pour le clinique ; le conflit va au poste propriétaire | Non (valeur par défaut : hub en vigueur + tâche) |
| Q4 | Combien de temps un poste peut-il rester **hors ligne** avant de ne plus être autorisé à émettre des numéros ? | Direction + DAF | 72 h, puis lecture seule pour les pièces numérotées | Non |
| Q5 | Le **réplica hors site** : où (autre ville, prestataire, second bureau) et à quelle fréquence ? | Direction | Sauvegarde chiffrée quotidienne, restauration à blanc trimestrielle | Non |
| Q6 | Un appareil perdu : qui a le droit de **révoquer** (administrateur seul, ou aussi DAF) ? | Direction | Administrateur + DAF, journalisé | Non |
| Q7 | Accepte-t-on que le **client navigateur** serve de poste de secours si un poste n'est pas installable ? | Direction + prestataire | Oui, en lecture + saisies courtes, avec file IndexedDB | Non |

## 13. Priorités

- **P0** : EF-SYNC-01 à 06, 08, 09, 10, 11, 12, 14 — le contrat d'opération, l'application locale d'abord, la file persistée, les familles de fusion, l'archivage, les invariants de stock et de numérotation, les droits au hub, la pastille.
- **P1** : EF-SYNC-07, 13, 15, 16, 17, 20 — fusion par champ, MECeF, écran de conflits, enrôlement/révocation, ré-hydratation, horloges.
- **P2** : EF-SYNC-18, 19 — fichiers par empreinte, réplica hors site (réalisables avec des outils de fichiers standards).
- **Conditionné par Q1** : tout accès depuis Internet.

## 14. Indicateurs

- Avancés : opérations perdues (**0**) ; doublons de code patient (**0**) ; stock négatif (**0**) ; délai de propagation p95 (**< 5 s**) ; conflits ouverts depuis plus de 24 h (**0** visé) ; part des opérations rejouées avec succès à la première tentative.
- Retardés : nombre de « fiches écrasées » signalées par les agents (tendance vers 0) ; temps moyen de régularisation d'un conflit ; temps de reprise après une coupure d'une heure (file vidée en moins de 5 min) ; échec de restauration à blanc (0).
