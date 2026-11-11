# PRD : clôture annuelle et passage à N+1, écarts mesurés, et droits sans rôle écrit en dur

Statut : **brouillon** du 11/11/2026, à arrêter par la Direction et le Comptable
Sources : texte de spécification fourni par la Direction le 11/11/2026 (clôture annuelle, réouverture réservée au comptable, archive SYSCOHADA révisé / DGI Bénin, navigation N, N-1, N+1) · `PRD-M12-cloture-exercice.md` et vague 69 (moteur `SIGH.exercice`) · relecture du code de la maquette faite dans cette session (`parcours.js` 3260 à 3660, `api/cron.php`, `m12-comptabilite.js`)

Ce PRD n'est pas écrit avec l'outil `sdlc-kit` (aucun coffre `.sdlc` dans le dépôt) : il suit la forme des PRD de `docs/prd/`.

**Limite de cette analyse** : c'est une **lecture du code**, pas encore une mesure au banc. Chaque ligne du tableau dit si elle est « lue » ou « à sonder ». Aucune ligne n'a été rejouée dans Chrome. Le texte fourni décrit un autre produit (application web progressive, tâche planifiée nommée d'après lui) : on reprend ses **comportements**, jamais ses noms ni ses écrans.

## 1. Nouvelle règle de la Direction : pas de masquage d'interface en dur

Lecture retenue (à confirmer, section 6) : **ce qu'un profil voit ou peut faire ne se décide jamais par un nom de rôle écrit dans le code**. Cela vient d'une donnée : la matrice des droits, ou un réglage du poste enregistré en base avec un défaut. C'est la règle de paramétrage du 09/11/2026 appliquée à l'interface.

**Mesure faite** (motifs `indexOf` sur une liste de rôles, plus comparaisons `role === '…'`), sur `prototype_html/assets/js` :

| Fichier | Listes de rôles en dur |
|---|---|
| `parcours.js` | 16 listes + 4 comparaisons |
| `m10-rh.js` | 9 |
| `m12-comptabilite.js` | 4 |
| `m2-consultations.js` | 3 comparaisons |
| `m1-patients.js` | 2 comparaisons |
| `m7-achats.js`, `m14-securite.js` | 1 chacun |

Le décompte est un **minimum** (les motifs ne saisissent pas toutes les formes d'écriture). Pour la clôture, trois sont écrits en dur : démarrer (`comptable`, `da`, `admin`), clôturer (`da`, `direction`, `admin`), rouvrir (`comptable`, `admin`). C'est exactement ce que la règle interdit : un autre cabinet, ou une Direction qui change d'avis, devrait modifier le code.

**Ce qui est déjà correct** : l'écran n'est pas masqué par le nom du rôle mais par `N.can()` et `K.droits()` (la matrice administrable). Le défaut est dans les **moteurs** : leurs refus nommés testent une liste écrite.

**Proposition** :
1. Un **circuit de clôture réglable** en base (`exercice.circuitCloture`, registre de paramètres, branche : `true`, mobile : `false`) avec trois listes (qui démarre, qui clôture définitivement, qui rouvre) et leurs **défauts égaux aux listes actuelles** : aucun comportement ne change à la livraison. Modifier une liste est un réglage versionné par date, tracé, réservé à l'administrateur et à la DAF.
2. Le moteur lit le circuit : le refus reste nommé, mais le message cite la liste **lue**, plus une liste écrite dans la phrase.
3. Une **garde de génération** (comme celle de `gen-pages`) qui **refuse tout nouveau** `indexOf` de rôle dans un moteur ou un écran, avec une liste blanche décroissante des sites existants. On migre ces sites **à la pièce**, par risque (clôture, paie, achats d'abord).
4. Le droit de la clôture se lit aussi comme un **droit de la matrice** (famille « clôture d'exercice »), pour que l'écran et le moteur lisent la même source, comme pour la validation des tarifs.

Ce lot est la **suite** du lot « menus à jour après modification des rôles » (décisions du 11/11/2026, H bis) : les deux demandent que l'interface et les moteurs lisent la matrice **au moment** où ils décident.

## 2. Écarts entre le texte fourni et la maquette

Statut : **lu** = trouvé dans le code ; **à sonder** = à confirmer au banc ; **écart** = absent ou différent.

| N° | Comportement demandé | État dans la maquette | Statut | Proposition |
|---|---|---|---|---|
| E1 | L'exercice N+1 s'ouvre tout seul : tâche planifiée quotidienne qui ouvre l'année en cours et, en décembre, l'année suivante | `exercices` est **dérivée** des écritures, de l'année en cours et de la liasse. `api/cron.php` n'a **aucune** tâche d'ouverture | **écart** | septième tâche planifiée « ouverture des exercices », quotidienne, qui écrit la fiche (année en cours, et N+1 en décembre), tracée au journal ; sans écriture de pièce |
| E2 | La première pièce datée du 1er janvier ouvre l'année si elle manque | N+1 apparaît parce que la liste est dérivée des écritures | **lu** (par dérivation) | à sonder : la pièce du 01/01 passe, l'exercice existe, une entrée de journal le dit |
| E3 | Les exercices descendent vers les postes avec leur statut | Maquette : un seul magasin, donc partagé. Poste Flutter : moteur porté, **synchronisation du statut non vérifiée** | **à sonder** (cible) | scénario à deux postes : la mère passe N en clôture, le fileul le sait sans redémarrer |
| E4 | En clôture, les modules n'écrivent plus dans N ; seul le comptable passe des écritures d'inventaire | `S.garder('ecritures')` laisse passer la **saisie manuelle** du comptable et de l'administrateur, refuse le reste | **lu** | à sonder ; la liste « comptable, administrateur » est en dur (section 1) |
| E5 | Exercice clôturé : lecture seule, tenue au moteur | refus nommé et entrée de journal | **lu** | rien |
| E6 | À-nouveaux provisoires calculés, jamais écrits ; la balance signale « à-nouveaux provisoires de N » | calculés (`provisoires`) | **lu** pour le calcul, **à sonder** pour le signalement sur la balance | afficher l'encadré sur la balance et le bilan de N+1 |
| E7 | Navigation « Exercice N-1 » et « Exercice N+1 » sous l'en-tête, sur l'onglet affiché | sélecteur d'exercice dans la barre supérieure (`app.js`) ; **boutons de navigation non trouvés** dans les écrans M12 | **écart probable** | deux boutons de pas, qui gardent l'onglet affiché, gardés par l'existence de l'exercice voisin |
| E8 | Bandeau de statut de l'exercice consulté (en clôture, clôturé) | non trouvé comme bandeau commun | **à sonder** | un bandeau unique posé au socle, comme celui de lecture seule, jamais écrit écran par écran |
| E9 | Comparatif N et N-1 sur le compte de résultat et le bilan, même filtre de statut | colonnes N et N-1 présentes (liasse déposée ou journal) sur le bilan et le feuillet du compte de résultat | **lu** | à sonder : même filtre de statut des écritures sur les deux colonnes |
| E10 | Saisie d'inventaire acceptée en clôture ; journaux CL et AN non choisissables | saisie manuelle acceptée ; restriction des journaux CL et AN **non vérifiée** | **à sonder** | retirer CL et AN de la liste de la saisie |
| E11 | Grand livre : solde d'ouverture et solde de clôture ; ouverture « inconnue », jamais zéro, quand N-1 est clos sans à-nouveau | **aucune trace** de ces deux soldes au grand livre | **écart probable** | ajouter les deux soldes ; l'ouverture d'un compte de gestion vaut zéro, celle d'un compte de bilan est l'à-nouveau (écrit ou provisoire, dit tel) |
| E12 | Notes annexes 2 et 3 (immobilisations, amortissements) : ouverture et variation par compte | l'écran des immobilisations porte un « Report au bilan » ; **pas** de notes 2 et 3 | **écart probable** | à confirmer avec le Comptable : ces notes existent-elles dans la liasse déposée ? (feuillets 25/51 et suivants, déjà transcrits) |
| E13 | Avant « Démarrer la clôture » : avertir des postes appairés qui ont des opérations à envoyer ou dont l'état est inconnu (24 h) | le contrôle de pré-clôture ne regarde que **ce poste** (« aucune opération en attente d'envoi ») | **écart** | la mère lit l'état de ses fileuls (dernier contact, opérations en attente) ; avertissement non bloquant, comme demandé |
| E14 | Démarrer, Reprendre la saisie, Clôturer définitivement, Rouvrir | les quatre transitions existent ; clôture refusée à qui a démarré (« signer n'est pas saisir ») | **lu** | garder cette séparation, plus stricte que le texte fourni ; le texte ne dit pas **qui** clôture définitivement |
| E15 | Rouvrir : comptable seul, motif d'au moins dix caractères, contre-passation de la pièce de clôture et d'à-nouveaux, rien ne s'efface | identique, refusé si N+1 n'est plus ouvert | **lu** | rien, sauf la liste en dur (section 1) |
| E16 | Contrôles avant clôture : aucun brouillon, balance équilibrée, N-1 clôturé ; refus si N+1 clôturé | présents, plus d'autres (comptes d'attente 47x, à-nouveaux déjà écrits) | **lu** | rien |
| E17 | Pièce de clôture au 31/12 au journal CL, centre par centre, contrepartie 131 ou 139 ; pièce d'à-nouveaux au 01/01 au journal AN | pièce de résultat et à-nouveaux produits ; répartition **par centre** et centre « Structure » **non vérifiés** | **à sonder** | rapprocher du texte ; un scénario compte les lignes par centre |
| E18 | Les états de N gardent le résultat de l'année (le journal CL est exclu) | **non vérifié** | **à sonder** | scénario : après clôture, le compte de résultat de N montre le résultat, non zéro |
| E19 | Archive légale au format SYSCOHADA révisé / DGI Bénin | CSV des écritures SYSCOHADA révisé, balance, PDF, manifeste SHA-256, vérification au téléchargement | **lu** pour SYSCOHADA révisé | **« format DGI Bénin » : aucun document du dépôt ne le décrit**. La section du texte sur l'archive n'a pas été fournie. Ne rien deviner : demander le format attendu |

## 3. Exigences retenues

| N° | Exigence |
|---|---|
| EF-CLO-1 | Tâche planifiée quotidienne d'ouverture des exercices (E1), journalisée, qui n'écrit aucune pièce. |
| EF-CLO-2 | Boutons de pas « Exercice N-1 / N+1 » sur les écrans M12, conservant l'onglet, absents si l'exercice voisin n'existe pas (E7). |
| EF-CLO-3 | Bandeau de statut de l'exercice consulté, posé une fois au socle (E8). |
| EF-CLO-4 | Soldes d'ouverture et de clôture au grand livre, « inconnu » jamais zéro (E11). |
| EF-CLO-5 | Avertissement non bloquant avant « Démarrer la clôture » sur les postes qui ont des opérations à envoyer ou dont l'état est inconnu (E13). |
| EF-CLO-6 | Journaux CL et AN retirés de la saisie manuelle (E10). |
| EF-CLO-7 | Encadré « à-nouveaux provisoires de N » sur la balance et le bilan de N+1 (E6). |
| EF-DRO-1 | Le circuit de clôture (qui démarre, qui clôture, qui rouvre) est un **réglage en base**, défauts égaux aux listes actuelles, versionné par date (section 1). |
| EF-DRO-2 | Garde de génération contre tout nouveau rôle écrit en dur dans un moteur ou un écran. |
| EF-DRO-3 | Un refus nommé cite la liste **lue** dans le réglage, jamais une liste recopiée dans la phrase. |

## 4. Hors ligne et synchronisation

Le circuit de clôture est un paramètre de **branche** : il se règle à la mère, voyage aux fileuls par le journal de configuration (famille R) et **jamais aux mobiles** (RG-13). Le statut d'un exercice voyage comme une donnée métier : un fileul qui ne l'a pas encore reçu **ne doit pas** accepter une pièce datée d'un exercice qu'il croit ouvert sans le dire ; la mère refuse la pièce au rejeu avec un refus nommé (« exercice en clôture ») et le poste la range en tâche à traiter. C'est le comportement que le texte fourni décrit (« le serveur refuse leurs pièces datées de N »). **À sonder** sur le banc de synchronisation.

## 5. Lots proposés

| Lot | Contenu | Preuve exigée |
|---|---|---|
| **C0 mesure** | rejouer au banc les lignes « à sonder » du tableau (E2, E3, E4, E6, E8 à E10, E17, E18) ; corriger ce document avec le constat | une assertion par ligne, qui échoue si le comportement manque |
| **C1 circuit réglable** | EF-DRO-1 à 3 pour les trois transitions de clôture (clôture définitive : DA, Direction, administrateur, comptable par défaut) ; garde de génération avec liste blanche | scénario : changer le circuit change qui peut clôturer, sans toucher au code ; mutation : remettre une liste en dur, la garde rougit |
| **C2 navigation et bandeau** | EF-CLO-2, 3, 7 | scénario au geste sur N-1, N, N+1 |
| **C3 grand livre** | EF-CLO-4 | ouverture « inconnue » dite, comptes de gestion à zéro |
| **C4 ouverture automatique** | EF-CLO-1 et E2 | décaler l'horloge du banc en décembre puis en janvier |
| **C5 postes appairés** | EF-CLO-5 et E3 | banc de synchronisation à deux postes |
| **C6 migration à la pièce** des autres listes de rôles en dur | par risque, un lot par module | l'audit RBAC reste à 0 promesse |

## 6. Questions : réponses de la Direction du 11/11/2026

| N° | Question | Réponse |
|---|---|---|
| Q1 | Lecture de « pas de masquage d'interface en dur » (section 1) | **Oui** : aucun nom de rôle dans le code, tout vient de la matrice et des réglages |
| Q2 | Qui prononce la clôture définitive | **La Directrice Administrative, la Direction, l'administrateur ou le comptable.** Défaut du circuit réglable : ces quatre rôles. La séparation « jamais la personne qui a démarré la clôture » est **conservée** (elle n'a pas été levée) : à confirmer si la Direction veut qu'un comptable puisse démarrer ET clôturer seul |
| Q3 | Format d'archive « DGI Bénin » | **Pas de format DGI.** Un format est proposé et nommé (SIGH-ARC version 1) dans `docs/specs/SPEC-archive-cloture-exercice.md` ; l'archive actuelle est conservée (CSV des écritures, balance, états à imprimer en PDF, manifeste SHA-256) |
| Q4 | Notes annexes 2 et 3 | pas de réponse : reste en recommandation (seulement si la liasse déposée les porte) |
| Q5 | Migrer les autres listes de rôles en dur | pas de réponse : reste en recommandation (clôture d'abord, le reste à la pièce) |

## 7. Indicateurs

- 0 liste de rôles en dur dans les trois transitions de clôture après C1.
- 0 nouvelle liste de rôles en dur acceptée par la garde de génération.
- Chaque ligne « à sonder » du tableau devient « lue » ou « écart » après C0.
