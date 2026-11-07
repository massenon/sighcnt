# PRD — M12 : Clôture d'exercice, à-nouveaux et navigation entre exercices

Statut : **brouillon** du 20/10/2026, à arrêter par la Direction et le Comptable
Sources : demande de la Direction du 20/10/2026 (texte « bascule et clôture d'exercice ») · CDCT §10.11 et RG-10 · cahier de charge du 30/12/2024 (« le logiciel ne se clôture pas en fin d'exercice ») · SYSCOHADA révisé (classes 1 à 5 reportables, résultat au compte 13) · prototype `m12-cloture`, `m12-ouverture`, `m12-etats-financiers`, `m12-immobilisations` (vagues 57 à 61)

## 1. Problème

Le prototype sait **verrouiller une période** et **écrire les à-nouveaux** (journal AN, bilan d'ouverture refusé s'il ne s'équilibre pas), mais il ne sait pas **clôturer un exercice** : rien ne solde les classes 6 et 7, rien ne rend l'exercice irréversible, et tous les écrans comptables travaillent sur **l'année 2026 écrite en dur** (`exercice: 2026`, « Périodes comptables — exercice 2026 »). Au 1ᵉʳ janvier 2027, le comptable ne pourra ni saisir ses écritures d'inventaire sur 2026 pendant que la caisse travaille sur 2027, ni consulter 2025 en lecture seule, ni rapprocher deux exercices autrement que par la liasse déposée. Le coût de ne pas le faire : une comptabilité qui s'arrête au 31 décembre, ou qui continue sans que rien ne protège l'année écoulée — c'est précisément ce qu'un contrôle fiscal vient vérifier.

## 2. Objectifs et non-objectifs

**Objectifs**

- O1. Le comptable clôture l'exercice N en **un geste contrôlé** : résultat dégagé, classes 6 et 7 soldées, exercice figé ; après clôture, aucune écriture de N ne se crée, ne se modifie ni ne s'archive.
- O2. Les à-nouveaux de N+1 naissent de la clôture, **au solde pour les comptes non lettrables, ligne à ligne pour les comptes de tiers non lettrés** — les factures assureur en attente se retrouvent dans l'exercice suivant.
- O3. Tout écran comptable travaille sur un **exercice choisi** (sélecteur dans la coquille, mémorisé par poste) ; un exercice clos est en **lecture seule**, et l'écran le dit.
- O4. Deux exercices peuvent être **ouverts simultanément** (N en attente de clôture, N+1 en saisie courante), avec des **à-nouveaux provisoires** recalculés à chaque consultation de N+1 tant que N n'est pas clos.
- O5. Les états financiers affichent **N et N-1 côte à côte** depuis le journal, sans recopie, et un exercice clos reste **exportable** pour l'obligation de conservation.

**Non-objectifs**

- Le lettrage automatique par rapprochement bancaire : le lettrage manuel suffit à distinguer une ligne de tiers soldée d'une ligne en attente ; l'automatisation est un chantier M9/M12 distinct.
- La réouverture d'un exercice clos : une clôture est **définitive** (c'est l'exigence légale). Une correction postérieure passe par une écriture de l'exercice suivant, jamais par la réouverture.
- La migration des exercices antérieurs à la mise en service (2025 et avant) autrement que par la liasse déposée déjà transcrite (`data-liasse.js`) et un bilan d'ouverture saisi.
- Les écritures d'inventaire elles-mêmes (provisions, régularisations) : elles existent déjà comme écritures ordinaires ; ce PRD ne crée pas d'assistant de provisions.

## 3. Utilisateurs et rôles

| Rôle | Voit | Fait | Ne voit / ne fait pas |
|---|---|---|---|
| Comptable | tous les exercices, le sélecteur, les deux colonnes N / N-1 | saisit sur les exercices ouverts, écrit le bilan d'ouverture, **demande** la clôture | ne clôture pas seul (RG-10 + validation de la Direction) |
| Assistant comptable (`aide_comptable`) | tous les exercices | saisit sur l'exercice courant uniquement | `m12-cloture` lui reste fermé nommément (fiche RBAC19) |
| Direction / DAF | tous les exercices | **valide** la clôture (second geste, motif), lit les états N / N-1 | ne saisit pas d'écriture |
| Assistant de Direction | tous les exercices en lecture | lit, imprime | ne saisit rien (M12 en VOIR depuis la vague 67) |
| Caissier, autres postes | rien de M12 | — | la caisse continue d'encaisser en N+1 : l'écriture d'encaissement naît en brouillon sur l'exercice de SA date |

Ce que l'écran dit au rôle restreint : « Exercice 2025 clos le 30/04/2026 par … — lecture seule. Les corrections se passent par une écriture de l'exercice en cours. »

## 4. Parcours

1. **Décembre N** : la caisse, la pharmacie et la paie continuent ; les écritures portent la date de leur geste. Le comptable valide ses brouillons au fil de l'eau.
2. **Janvier N+1** : le sélecteur d'exercice propose N (ouvert, « en attente de clôture ») et N+1 (ouvert, courant). Les écrans de N+1 affichent des **à-nouveaux provisoires** calculés depuis les soldes validés de N ; une bannière le dit (« à-nouveaux provisoires — l'exercice N n'est pas clos »).
3. **Janvier à avril N+1** : le comptable saisit les écritures d'inventaire sur N (amortissements semestriels déjà calculés par `m12-immobilisations`, provisions, régularisations), valide, contrôle la balance (RG-10), édite le bilan et le compte de résultat de N.
4. **Clôture** (`m12-cloture`) : le comptable lance la **pré-clôture** — contrôles bloquants nommés (brouillons restants, période déséquilibrée, immobilisation sans dotation, compte 47x non soldé, lettrage de tiers incomplet signalé) ; il **demande** la clôture ; la Direction **valide** (motif, date). Le logiciel écrit alors, sur N : les écritures de **détermination du résultat** (journal OD : solde des classes 6 et 7 vers 13), puis sur N+1 : le **journal AN définitif** (classes 1 à 5 ; tiers lettrables ligne à ligne), en **remplaçant** les à-nouveaux provisoires. Les deux pièces naissent **validées** (elles sont la conséquence d'un geste validé), et la clôture est journalisée (RG-12).
5. **Après** : N passe en lecture seule partout ; le sélecteur le marque « clos ». Un export signé (grand livre, balance, journaux, états financiers, PDF + CSV) est produit et archivé (GED, `documents`), avec son empreinte.
6. **Consultation ultérieure** : choisir N-1 dans le sélecteur ouvre le grand livre, la balance, les journaux de N-1 en lecture seule ; les états financiers de N montrent N-1 à côté.

## 5. Exigences fonctionnelles

| Réf. | Énoncé | Source | Règles | Critère d'acceptation |
|---|---|---|---|---|
| EF-M12-30 | Une collection `exercices` porte chaque exercice : année, début, fin, état (`ouvert`, `en_attente_cloture`, `clos`), dates et auteurs de demande et de validation, empreinte de l'export | demande 20/10 | RG-12, RG-14 | Un exercice existe pour chaque année portée par une écriture ; aucun ne se supprime |
| EF-M12-31 | **Sélecteur d'exercice** dans la coquille des écrans M12 (et MECeF, M9 créances), mémorisé par poste, par défaut l'exercice courant | demande 20/10 (« menu déroulant en haut de l'écran ») | — | Changer d'exercice recalcule tous les écrans sans rechargement de la donnée ; le fil d'Ariane porte l'exercice |
| EF-M12-32 | Toute lecture comptable filtre par l'exercice choisi ; **aucune année écrite en dur** ne subsiste dans M12 | audit du code (`exercice: 2026` × 8) | — | `grep "2026"` dans `m12-comptabilite.js` ne rend que des commentaires et le dépôt de la liasse |
| EF-M12-33 | Un exercice **clos** est en lecture seule : création, modification, archivage d'écriture refusés **au moteur** (`S.collection('ecritures')` vérifie l'exercice), et l'écran l'annonce | demande 20/10 | RG-13 doctrine « une restriction s'annonce » | Une écriture datée d'un exercice clos est refusée en nommant l'exercice, même par un appel direct du magasin |
| EF-M12-34 | **Pré-clôture** : liste de contrôles bloquants et non bloquants, chacun nommant les pièces en cause et l'écran où corriger | RG-10 | RG-10 | Un brouillon restant bloque ; une immobilisation sans dotation de l'exercice bloque ; un tiers non lettré **signale** (il sera repris ligne à ligne) |
| EF-M12-35 | Clôture en **deux gestes** : demande (comptable) puis validation (Direction/DAF) avec motif ; la validation est journalisée | doctrine « signer n'est pas saisir » (vague 53) | RG-12 | Sans validation, rien n'est écrit ; la demande est révocable |
| EF-M12-36 | **Écritures de détermination du résultat** sur N : solde de chaque compte 6 et 7 vers 13 (bénéfice au crédit, perte au débit), une pièce équilibrée, journal OD, validée | SYSCOHADA | RG-10 | Après clôture, la balance de N a toutes ses classes 6 et 7 à zéro et le 13 porte exactement le résultat du compte de résultat |
| EF-M12-37 | **À-nouveaux définitifs** sur N+1 au 1ᵉʳ janvier : classes 1 à 5 ; comptes **non lettrables** au solde ; comptes de **tiers** (401, 411, 421, 43x, 44x…) **ligne par ligne pour les lignes non lettrées**, chaque ligne gardant sa référence de pièce d'origine | demande 20/10 | RG-10 | La somme des AN = soldes de clôture ; une facture assureur de N non réglée se retrouve en N+1 avec son numéro |
| EF-M12-38 | **Lettrage** des comptes de tiers : marquer un ensemble de lignes équilibrées comme soldées (code de lettrage, date, auteur) ; dé-lettrer motivé ; seul le non-lettré est repris | demande 20/10 | RG-12 | Un lettrage déséquilibré est refusé ; l'écran des créances M9 lit le lettrage |
| EF-M12-39 | **À-nouveaux provisoires** : tant que N n'est pas clos, tout écran de N+1 (balance, grand livre, bilan) intègre un report calculé depuis les soldes validés de N, marqué « provisoire » ; la clôture les remplace par le journal AN | demande 20/10 (« exercices ouverts simultanés ») | — | Modifier une écriture validée de N change la balance de N+1 ; après clôture, elle ne change plus |
| EF-M12-40 | **Deux colonnes N / N-1** sur bilan, compte de résultat et flux (`m12-etats-financiers`, `m12-compte-resultat`, `m12-flux-tresorerie`) : N-1 lu du journal s'il existe, sinon de la liasse déposée, et la source est dite | demande 20/10 · vague 61 | — | 2026 affiche 2025 depuis la liasse ; 2027 affichera 2026 depuis le journal |
| EF-M12-41 | **Export d'archive** à la clôture : journaux, grand livre, balance, états financiers en PDF et CSV, empreinte SHA-256, fiche GED `documents` | obligation de conservation | RG-12 | L'export d'un exercice clos se régénère à l'identique (même empreinte) |
| EF-M12-42 | **Immobilisations** : la dotation semestrielle de l'exercice est une écriture d'inventaire proposée (68x / 28x) ; un bien cédé dans l'exercice sort du bilan ; le « report au bilan » lit l'exercice choisi | vague 57-59 | RG-10 | La pré-clôture bloque si une dotation attendue n'est pas passée |
| EF-M12-43 | Le **premier exercice** s'ouvre par un bilan d'ouverture saisi (`m12-ouverture` existant), seule voie pour un exercice sans prédécesseur dans le logiciel | existant | RG-10 | Un AN saisi déséquilibré est refusé |

## 6. Données

- Nouvelle collection **`exercices`** (semée au socle depuis les années des écritures : lue par M12, M9, MECeF, tableaux de bord) → **incrément de `VERSION`**.
- Nouvelle collection **`lettrages`** (code, compte, lignes, montant, auteur, date, annulé le/motif).
- `ecritures` : champ `exercice` (dérivé de la date à l'écriture, indexé), `lettrage` (code ou null), `origineCloture` (`resultat` | `an` | null).
- Référentiel : les comptes **lettrables** sont ceux de la classe 4 marqués `lettrable: true` au plan comptable (`comptes`) — paramétrage administrable, par défaut 40x/41x/42x/43x/44x/47x.
- Paramètre d'exploitation : exercice courant par poste (`S.reglage('exercice')`), jamais en dur.

## 7. Hors ligne et synchronisation

| Donnée | Famille de fusion | Si deux postes agissent sans hub | Ce que l'écran dit |
|---|---|---|---|
| Écriture d'un exercice ouvert | pièce émise (immuable après validation) ; brouillon = fiche descriptive | deux brouillons = deux pièces ; une validation est une opération | — |
| `exercices` (état) | agrégat à invariant : **la clôture est une opération du hub seul** | un poste hors ligne ne peut pas clôturer : la demande part en file, la validation attend le hub, qui vérifie que **toutes les files de tous les postes** sont reçues jusqu'au 31/12 | « Clôture en attente : le hub n'a pas reçu la file du poste Caisse (dernière réception le …) » |
| Écriture datée d'un exercice clos arrivant après coup (poste hors ligne au moment de la clôture) | invariant violé | l'opération est **mise en suspens** et une tâche nommée naît au poste comptable : « écriture du 28/12 arrivée après clôture — à passer sur l'exercice suivant » | la pièce reste visible, non comptée, avec son motif |
| Lettrage | fiche descriptive (dernier écrit gagne) + contrôle d'équilibre au hub | deux lettrages contradictoires → le second est mis en suspens | tâche au comptable |
| À-nouveaux provisoires | calcul local, jamais stocké | — | « provisoire » |

## 8. Impression et états

Balance de clôture, journal OD de détermination du résultat, journal AN, bilan et compte de résultat N / N-1 (feuillets 7/51 et 8/51 existants), **procès-verbal de clôture** (A4 : exercice, résultat, contrôles passés, signatures Comptable et Direction, empreinte de l'archive). En-tête légal unique, totaux par `somme`, filtres portés sur la pièce.

## 9. Ce qui n'est pas documenté

- La **liste des contrôles bloquants** de pré-clôture est une proposition (aucun document de cadrage ne l'arrête) ; à valider par le Comptable.
- Le **journal des écritures de résultat** (OD) et la codification des lettrages (`A`, `B`… par compte) sont proposés par analogie avec les logiciels de la place (PERFECTO) ; à confirmer.
- La **durée de conservation** et le support d'archive (disque externe, GED) relèvent de l'obligation légale béninoise : à confirmer par le cabinet comptable.

## 10. Questions ouvertes pour la Direction

1. Qui **valide** la clôture : la Directrice Administrative, le Directeur Médical, ou les deux ? (recommandation : DAF, avec le Directeur en copie par notification)
2. Les **comptes lettrables** se limitent-ils aux tiers (classe 4) ou faut-il aussi lettrer la banque (52x) par rapprochement ? (recommandation : classe 4 seulement en v1)
3. Faut-il **bloquer la saisie de N+1** tant que N n'est pas clos après le 30 avril ? (recommandation : non — signaler, jamais bloquer la caisse)

## 11. Priorités

- **P0** : EF-M12-30 à 37, 39, 43 (sélecteur, lecture seule au moteur, clôture en deux gestes, résultat, AN au solde, AN provisoires).
- **P1** : EF-M12-38 (lettrage et AN ligne à ligne — en attendant, les tiers sont repris au solde avec la liste des pièces non réglées lue de M9), EF-M12-40 (N-1 depuis le journal), EF-M12-41 (export d'archive).
- **P2** : EF-M12-42 avancé (proposition automatique des dotations), rapprochement bancaire assisté.

## 12. Indicateurs de réussite

- Clôture de l'exercice 2026 réalisée dans le logiciel avant le 30/04/2027, sans ressaisie dans PERFECTO (indicateur retardé).
- 0 écriture créée sur un exercice clos à l'audit du journal (indicateur avancé, mesuré par scénario).
- Balance de N+1 au 1ᵉʳ janvier = soldes de clôture de N, au franc (scénario de bout en bout).
- Temps du comptable pour produire bilan + compte de résultat N / N-1 : moins d'une demi-journée (contre plusieurs jours aujourd'hui entre PERFECTO et Excel).
