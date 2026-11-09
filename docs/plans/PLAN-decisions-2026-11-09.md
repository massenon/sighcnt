# Plan : mise en œuvre des décisions de la Direction du 09/11/2026

Source : `docs/decisions/DECISIONS-A-VALIDER.md` (section D). Règle commune : tout paramètre est **en base**, réglable dans les paramètres du poste, avec un défaut semé ; un paramètre qui change se versionne par date. Synchronisation : les paramètres voyagent du poste vers le relais par le journal (famille R, configuration), chiffrés de bout en bout ; le relais ne les lit pas et son panneau web n'affiche que ses propres réglages. Chaque lot déclare ses paramètres dans cette famille et prouve l'aller-retour (poste, relais chiffré, second poste) au banc. Méthode : maquette d'abord, puis vecteurs, domaine Dart, poste. Un agent par lot, banc isolé, une suite complète et un audit RBAC à la fin de la série. Un seul agent écrit dans la maquette à la fois.

| Lot | Décision(s) couverte(s) | Contenu | Défaut |
|---|---|---|---|
| L1 | Validation Q1 à Q5 | Choix « Valider » dans la modale de mise à jour des 14 familles ; enregistrer par un profil de la famille valide ; hors famille l'élément repasse « à valider » (b) ; élément semé reste « à valider » jusqu'à la première relecture ; motif obligatoire pour les valeurs chiffrées ; création par un validateur naît validée ; une seule ligne de journal ; sonde du refus fileul | |
| L2 | AIB Q1, Q3, Q5, Q7 | Formulaire de validation du barème AIB dans les paramètres (famille `bareme_aib`) ; taux selon la situation de l'acheteur (1 %, 5 %, 3 %) ; charge des 5 % : paramètre **acheteur / clinique** ; branchement sur les écritures d'achat **différé**, avec son formulaire de validation | charge : clinique |
| L3 | MECeF (décision 3) | Paramètre **mode : boîtier ou e-MECeF** ; aucun numéro simulé au poste ; e-MECeF « non configuré : dossier d'interface DGI requis » | boîtier |
| L4 | Planning Q1 | Régime individuel qui déroge **champ par champ** (durée, repos, honoraire), le reste suit la catégorie | |
| L5 | Planning Q2, Q3 | Circuit de validation des présences et absences **paramétrable** (surveillant seul, DAF seule, surveillant puis DAF) ; congés et ordres de mission au même circuit, mission avec avis du chef de service | surveillant seul |
| L6 | Planning Q4 | L'agent **propose** une modification de son planning, le surveillant valide ; réglage « l'agent peut modifier directement » | non |
| L7 | Planning Q5, Q6, Q8 | Fiche de paie : copie chiffrée locale sur le téléphone, réglage oui/non ; espace « Mes » accessible sur poste partagé en secours (session nominative) ; « Mon assurance du personnel » en lecture seule | téléphone : oui |
| L8 | Planning Q7 | Le badge sert de pointage, réglage oui/non, relié au registre des présences | oui |
| L0 | Synchronisation des paramètres | Famille de configuration « paramètres » : du poste vers le relais, stockage chiffré côté relais, rejeu sur les fileuls ; panneau web limité aux réglages du relais ; banc de synchronisation à deux postes | |
| L9 | Travail restant | Valeurs d'attente du personnel (marquage par champ) ; portage barème AIB, paramètres fiscaux, calendrier et versement CNSS vers vecteurs, Dart et poste ; SMS S3 à S6 ; module satisfaction ; relais en ligne R0 à R7 ; dictionnaire de données ; rechargements de page à rendre attentifs à l'envoi (E2307) | |

Ordre : L0 (avant tout paramètre), L1, L2, L3, puis L4 à L8 (même écran M10 pour L4, L5, L6, L8 : un agent à la fois), puis L9. Le poste Flutter suit chaque lot de la maquette (vecteurs régénérés, parité N1).
Chaque lot rend : scénario de banc qui sonde au geste, réglage en base visible dans les paramètres, défaut vérifié, entrée ECARTS-MAQUETTE.md, commit.

## L0 : synchronisation des paramètres (réalisé le 09/11/2026)

### Inventaire : ce qui existait

- **Le canal** : la mère publie chaque fiche de configuration au journal en famille R par `POST /admin/referentiel` ; les fileuls la reprennent par `GET /liste` et l'appliquent (`ApplicateurConfiguration`, garde « réglé sur la mère ») ; le journal est répliqué chiffré (AES-256-GCM, sens `journal`) vers le relais, qui n'en lit rien ; un mobile ne reçoit que les fiches de sa portée.
- **Les paramètres de la maquette** : des collections propres à chaque sujet (`politiqueSecurite`, `baremeNS131` + `historiqueBareme`, `grillePrimes` + `historiquePrimes`, `obligationsFiscales` + `historiqueObligations`, `reglages`). Chacune a sa forme et son propre versionnement par date ; aucune n'est générique. Elles voyagent déjà (elles sont dans `cfbEssentielles`).
- **Ce qui manquait pour un paramètre générique** : une fiche à champs fixes (clé, famille, type, valeur, défaut, date d'effet, version, auteur, motif), la règle de résolution « valeur en vigueur à la date D avec défaut », le refus de réécrire une valeur déjà utilisée par une pièce, la liste blanche du téléphone, un registre des définitions avec défauts semés, un écran par famille.

### Conclusion : la famille R suffit, une famille « paramètres » distincte n'est pas nécessaire

1. **Propriété** : un paramètre se règle sur la mère et nulle part ailleurs, ce qui est exactement la famille R (« la mère seule écrit »). Le fileul reçoit et lit, il ne règle pas.
2. **Fusion** : le défaut de la famille R est « dernier écrit gagne » sur une fiche. Un paramètre versionné par date ne doit jamais être réécrit : on le modélise donc comme **une fiche immuable par version** (`cle@dateEffet@version`). Chaque fiche n'est écrite qu'une fois, la famille R n'a plus rien à fusionner, et la valeur en vigueur est une fonction pure de l'ensemble des fiches (indépendante de l'ordre d'arrivée, vérifié par permutation). Aucune règle de fusion nouvelle dans le protocole.
3. **Ce qui s'ajoute n'est pas une famille mais trois règles de la mère**, refaites à la réception comme à l'émission (même fonction du domaine) : type et valeur, date d'effet, refus `parametre_deja_utilise`, `version_deja_prise`, `version_immuable`, `mobile_interdit`. La mère les applique à la collection `parametres` ; le relais n'en contient aucune.
4. **Les usages** (une pièce a utilisé telle valeur à telle date) sont la seule donnée qui part d'un fileul : collection `usagesParametres`, famille B (ajout seul), remontée par le pont d'activité. C'est ce qui permet à la mère de refuser de réécrire ce que la pièce d'un fileul a utilisé.
5. **Relais** : aucune route nouvelle. Les versions sont des opérations du journal : elles arrivent au relais dans les enveloppes `journal` de la mère, chiffrées avec les autres, et reviennent avec elles à la restauration (R8r). Le panneau web n'affiche aucun paramètre métier et ne propose aucune route pour en lire ou en écrire (test PHPUnit).

### Liste blanche du téléphone (RG-13)

Un paramètre ne va à un téléphone que si **sa définition le déclare** (`mobile`), qu'il n'est **pas sensible** et que sa **famille n'est pas réservée** : `paie`, `rh`, `fiscal`, `bareme_aib`, `comptabilite`, `mecef`, `securite`, `relais`, `courriel`, `sms`. La mère refuse à la réception une version qui déclare `mobile` pour un paramètre sensible ou une famille réservée (`mobile_interdit`) et ne publie aux mobiles que les versions autorisées. **La liste blanche est vide à ce jour** : aucune des six définitions ne l'est, aucun lot n'a démontré un besoin. La liste des familles réservées est prudentielle, **à valider par la Direction** (aucun document ne la fixe). Un secret (mot de passe SMTP, clé d'API) n'est pas un paramètre : il reste au coffre du poste.

### Ce qui a été livré, et comment il se vérifie

| Pièce | Où | Vérification |
|---|---|---|
| Règle de référence | `packages/sync/banc/parametres.js` | `node --test banc/parametres.test.js` : 8 tests |
| Scénario à processus réels | `banc/scenarios-parametres.js` (`L0`) | `node --no-warnings banc/run.js L0` : 24 vérifications, sur Node, sur le relais Laravel, et tout en Dart + Laravel (`SIGH_RELAIS=laravel SIGH_MERE=dart SIGH_FILEUL=dart SIGH_MOBILE=dart`) |
| Vecteurs | `node banc/vecteurs-parametres.js` → `packages/domaine/test/vecteurs/parametres.json` | 62 cas, refus comparés au code, motif et geste près |
| Domaine Dart | `packages/domaine/lib/src/parametres/` (`Parametres`, `ServiceParametres`, registre des six défauts) | `dart test` : 78 tests de paramètres |
| Mère Dart | `packages/sync_dart/lib/src/mere.dart`, `pont.dart` | scénario L0 en Dart ; `dart analyze` |
| Poste | `apps/poste` : onglet « Paramètres » de Paramètres système, semis par la mère, gardes de collection, publication et réception par les canaux existants | **non compilé ni testé ici** (pas de SDK Flutter) : voir les limites |
| Relais | `apps/web/tests/Feature/ParametresOpaquesTest.php`, texte du panneau | `php artisan test` : 106 réussis |

### Les six défauts déclarés (aucune valeur inventée)

Les défauts viennent de la colonne « Défaut » de ce plan et de la section D des décisions : MECeF `boitier` (L3) ; charge du prélèvement AIB `clinique` (L2) ; circuit des présences `surveillant` (L5) ; l'agent modifie directement `non` (L6) ; copie de la fiche de paie sur le téléphone `oui` (L7) ; le badge sert de pointage `oui` (L8). Chacun porte `branche: false` et `appliquePar` : **le réglage s'enregistre et se synchronise, mais l'écran concerné ne le lit pas encore**, et l'écran des paramètres le dit. Chaque lot qui branche un paramètre passe `branche` à vrai et lit la valeur par `ServiceParametres.valeurA(cle, dateDeLaPiece)`, puis note l'usage à l'émission de la pièce (`enregistrerUsage`).

### Limites connues

- Le mode pair (ADR-0006) ne porte pas la configuration : un fileul qui ne joint pas la mère ne reçoit pas un nouveau réglage tant qu'il ne la rejoint pas. Les paramètres ne changent que sur la mère, elle-même absente dans ce cas : aucune divergence, un retard seulement.
- Si la base de la mère était reconstruite de zéro, les anciennes versions seraient republiées après les usages déjà connus et pourraient être refusées (`parametre_deja_utilise`) alors qu'elles précédaient la pièce. La restauration par l'archive du relais (R8r) rejoue le journal tel quel et n'y passe pas.
- La date d'une pièce (`dateEffet`, usage) est une date locale AAAA-MM-JJ fournie par l'appelant ; le domaine ne lit jamais l'horloge.
- Revue de sécurité du chiffrement, SQLCipher, service Windows, charge : non couverts par ce lot (voir le README du banc).
