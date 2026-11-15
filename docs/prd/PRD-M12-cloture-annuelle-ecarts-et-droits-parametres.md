# PRD : clôture annuelle et passage à N+1, écarts mesurés, et droits sans rôle écrit en dur

Statut : **livré en partie** (lots CLO et CLO-2, 14 et 15/11/2026) : C0 à C5 faits, C6 en cours (85 sites restants) ; voir les sections 8 et 9. Brouillon du 11/11/2026, réponses de la Direction en section 6
Sources : texte de spécification fourni par la Direction le 11/11/2026 (clôture annuelle, réouverture réservée au comptable, archive SYSCOHADA révisé / DGI Bénin, navigation N, N-1, N+1) · `PRD-M12-cloture-exercice.md` et vague 69 (moteur `SIGH.exercice`) · relecture du code de la maquette faite dans cette session (`parcours.js` 3260 à 3660, `api/cron.php`, `m12-comptabilite.js`)

Ce PRD n'est pas écrit avec l'outil `sdlc-kit` (aucun coffre `.sdlc` dans le dépôt) : il suit la forme des PRD de `docs/prd/`.

**Limite de la première analyse (11/11/2026)** : c'était une **lecture du code**. Le lot C0 (14/11/2026) a mesuré au banc chaque ligne « à sonder » : voir la section 8. Chaque ligne du tableau dit si elle est « lue » ou « à sonder ». Aucune ligne n'a été rejouée dans Chrome. Le texte fourni décrit un autre produit (application web progressive, tâche planifiée nommée d'après lui) : on reprend ses **comportements**, jamais ses noms ni ses écrans.

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

## 8. Constats du lot C0 (mesure au banc, 14/11/2026)

Scénario « Vague 179 » du banc fonctionnel (une assertion par ligne, tirée du comportement réel de la maquette, sans rien corriger). Mesuré sur l'arbre d'avant le lot : **12 vérifications vraies, 3 en défaut** (les trois défauts sont corrigés dans les étapes ci-dessous et leurs assertions rejoignent le scénario avec la correction, pour que chaque comportement ait un test qui échoue sur l'arbre d'avant).

| N° | Constat C0 | Suite |
|---|---|---|
| E2 | **lu** : une pièce du 01/01 d'une année sans exercice fait exister l'exercice (ouvert). **Écart confirmé** : aucune trace au journal d'audit | C4 : toute ouverture est tracée |
| E3 | non mesurable à la maquette (un seul magasin) | C5, banc de synchronisation |
| E4 | **lu** : en clôture, la saisie manuelle du comptable et de l'administrateur passe ; une pièce de module (même par le comptable) et la saisie manuelle d'un autre profil sont refusées. La liste est en dur | C1 : liste lue dans le circuit |
| E6 | **lu** : l'encadré « À-nouveaux provisoires » est posé au socle et paraît sur la balance et sur le bilan de N+1 | rien |
| E7 | **lu, le PRD se trompait** : les boutons « ‹ N-1 » et « N+1 › » existent dans la barre supérieure (`#exercice-precedent`, `#exercice-suivant`), absents si l'exercice voisin n'existe pas | C2 : libellé « Exercice N », onglet conservé |
| E8 | **lu** : le bandeau de statut (clos, en clôture, à-nouveaux provisoires) est posé UNE fois, dans `app.js` ; grand livre d'un exercice clos : bandeau et lecture seule vérifiés | C1 : le texte nomme les rôles lus |
| E9 | bilan **lu** : colonnes N et N-1 au même filtre (validées seulement, brouillons absents des deux). **Écart confirmé** : le compte de résultat n'a pas de colonne N-1 tirée du journal (seulement les deux colonnes de la liasse déposée) | C2 |
| E10 | **écart confirmé** : le journal AN est proposé à la saisie manuelle ; le moteur ne refuse ni CL ni AN ; CL n'est pas dans la liste (absent du référentiel des journaux) | C4 |
| E11 | à mesurer au grand livre | C3 |
| E17 | **lu** : la pièce CL solde chaque centre séparément (pièce équilibrée par centre), contrepartie 131 (bénéfice) ou 139 (perte) par centre ; les lignes sans centre forment leur propre groupe. Le centre « Structure » du texte fourni n'existe pas dans le référentiel de la clinique : **sans objet** | rien |
| E18 | **lu** : le journal CL est exclu des états de N, le résultat de l'année reste (celui des états égale celui de la fiche, non nul ; avec CL il tomberait à zéro) ; l'écran du compte de résultat de N montre les produits et charges non soldés | rien |

Observation hors lot : la colonne « Exercice en cours » du compte de résultat laisse vides les lignes de total (XI, XB, etc.) ; un total d'état est CALCULÉ (règle du dépôt), celui-ci ne l'est pas encore.

## 9. Livraison du lot CLO (14/11/2026) : état par exigence et par écart

| Lot | Exigence | État | Preuve |
|---|---|---|---|
| C0 | mesure des lignes « à sonder » | **fait** (section 8) | scénario « Vague 179 », 15 vérifications |
| C1 | EF-DRO-1, 2, 3 : circuit réglable, garde de génération, refus qui cite la liste lue | **fait**, maquette et poste | scénario « Vague 180 » (17), vecteurs `exercice.json` (section `circuit`), garde `build/garde-roles-en-dur.js` (95 sites inscrits avant, 86 après) |
| C2 | EF-CLO-2, 3, 7 : boutons de pas, bandeau, encadré, colonnes N et N-1 | **fait** à la maquette (les boutons et le bandeau existaient : le PRD se trompait, E7 était « lu ») ; la colonne N-1 du compte de résultat est ajoutée à la maquette ET au poste ; le sélecteur ‹ Exercice N › du poste existait déjà ; le bandeau d'état du socle n'est pas porté au poste (inchangé) | scénario « Vague 181 », test `m12_etats_test` |
| C3 | EF-CLO-4 : soldes d'ouverture et de clôture du grand livre | **fait**, maquette et poste | « Vague 181 », vecteurs `soldesGL`, test du poste |
| C4 | EF-CLO-1, EF-CLO-6, E1, E2, E10 : ouverture automatique, journaux CL et AN retirés de la saisie | **fait**, maquette, serveur de la maquette et poste | scénario « Vague 182 » (8), « Vague 179 », vecteurs `ouverture` |
| C5 | EF-CLO-5, E3, E13 : postes appairés | **fait au lot CLO-2** (poste et mère Dart ; la maquette n'a pas de fileul) : refus nommé au rejeu par la mère (`exercice_clos`, `exercice_en_cloture`), statut des exercices synchronisé, avertissement non bloquant avant « Démarrer la clôture » (délai réglable, 24 h), banc à deux postes | `cloture_rejeu_sync_test.dart` (vraie mère), `m12_exercice_test.dart`, mutations rouges |
| C6 | migration des listes de rôles en dur | **en cours** : M12 (clôture, comptes de résultat, notifications) puis le centre « Validations en attente » de M13 sont migrés, 95 sites inscrits avant, 85 après CLO-2 ; les 85 restants sont listés et plafonnés par la garde | `build/garde-roles-en-dur.liste.json` |

**Décisions prises** (aucune n'est une décision de la Direction, toutes sont à confirmer, voir `DECISIONS-A-VALIDER.md` section AG) :

1. Le circuit a **cinq réglages**, pas trois : démarrer, passer l'inventaire en clôture, clôturer définitivement, rouvrir, et le mois d'ouverture de l'exercice suivant. La liste d'inventaire existait en dur (comptable, administrateur) dans la garde des écritures : elle devait venir d'un réglage pour que la règle « aucun nom de rôle dans le code » tienne.
2. Défauts semés : ceux d'avant le lot, sauf la clôture définitive, élargie au comptable (Q2). La séparation « jamais la personne qui a démarré la clôture » est conservée : un comptable seul ne peut donc toujours pas démarrer ET clôturer.
3. **Régler le circuit est un geste réservé de la fiche RBAC** (`regler_circuit_cloture`), administrateur et Directrice Administrative d'origine : proposition, le PRD disait « réservé à l'administrateur et à la DAF » sans que la Direction l'ait confirmé.
4. **La tâche quotidienne du serveur ne peut pas ouvrir un exercice** : la doctrine du planificateur (`api/cron.php`) interdit à une tâche d'écrire une collection (les postes réécrivent leurs collections entières), et le relais cible est opaque. L'ouverture est donc faite par le **poste** (au démarrage, puis toutes les six heures, et à chaque lecture de la liste des exercices à la maquette), tracée au journal d'audit avec sa cause ; la tâche du serveur `exercices_ouverture` LIT, vérifie chaque jour que ce qui doit être ouvert l'est, et alerte les rôles qui démarrent la clôture sinon. Le PRD écrivait « tâche planifiée qui écrit la fiche » (E1) : écart assumé.
5. Un exercice ouvert n'écrit **aucune pièce** : les à-nouveaux de N+1 restent provisoires et calculés jusqu'à la clôture de N (E6, inchangé).
6. Ouverture « inconnue » : quand l'exercice précédent est clos (ou celui de la liasse) sans à-nouveau écrit, l'ouverture et la clôture d'un compte de bilan sont **inconnues** à l'écran, jamais zéro. Un compte de gestion s'ouvre à zéro et se clôt à zéro après la pièce CL.
