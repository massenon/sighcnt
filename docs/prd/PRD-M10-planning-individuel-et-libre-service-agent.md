# PRD : Planning et gardes individuels, et espace « Mes » de l'agent (maquette, poste, mobile)

Statut : **proposé le 06/11/2026** à la demande de la Direction. Les décisions de la section 9 sont à valider avant le premier code.
Sources : demande de la Direction du 06/11/2026 ; relevés dans le dépôt le même jour (`m10-rh.js`, `nav.js`, `rbac.json`, `apps/mobile/lib`) ; `docs/architecture/adr/ADR-0005-*` et `ADR-0006-*` (mobile par le relais seul, échanges entre pairs) ; `docs/specs/SPEC-protocole-synchronisation.md`.
Règle de rédaction : pas de tiret cadratin comme ponctuation. Doctrine : maquette d'abord, puis vecteurs, domaine Dart, poste, mobile.

## 1. Problème

**Ce qui existe (relevé le 06/11/2026).**

- `m10-planning` (« Planning & gardes ») porte trois blocs : les **régimes de travail par catégorie** (collection `regimesTravail`, un régime vaut pour une liste de fonctions), la **grille hebdomadaire** (une case par agent et par jour, un clic crée, modifie ou retire une vacation) et le **registre des vacations** (collection `planning`, une fiche par vacation : date, agent, fonction, service, type, régime appliqué).
- Le CRUD d'une vacation existe (créer, modifier, retirer par archivage, refus nommé si le repos après une garde n'est pas respecté), réservé aux rôles `admin`, `da` et `surveillant`.
- Les régimes se modifient avec une **portée** (vacations à venir seulement, ou historique compris) ; chaque vacation porte `regimeLibelle`, le régime sous lequel elle a été posée.

**Ce qui manque.**

1. **Une garde propre à un agent.** Le régime vaut pour une catégorie. Deux médecins n'ont pas les mêmes gardes (durée, cadence, repos, honoraire), et rien ne l'exprime sinon en retouchant vacation par vacation. Il n'existe **aucun historique daté** des régimes (pas d'équivalent de `historiquePrimes`) : on ne peut pas répondre à « quel régime s'appliquait à cet agent le 12 mars ? ».
2. **Aucun filtre avancé** sur le planning. La grille n'a que la navigation par semaine ; le registre filtre sur le type et le service seulement : ni période, ni agent, ni fonction, ni statut, ni recherche enregistrée.
3. **Aucun espace de l'agent.** Hormis « Mon compte », aucun écran « Mon / Mes » : un agent ne consulte ni son contrat, ni sa fiche de paie, ni son planning, ni ses primes ; il ne peut pas déclarer une présence, une absence ou un congé. L'application mobile couvre le dossier patient, l'agenda et l'accueil pour deux profils (soignant, réception de secours), sans aucune donnée RH.
4. **Pas de revue d'ensemble.** On ne sait pas, écran par écran, lesquels n'ont ni filtre avancé, ni CRUD complet, ni paramètre système (l'inventaire est l'annexe de ce PRD, voir section 8).

## 2. Objectifs

- **O1.** Un agent a un **régime individuel** (dérogation) à date d'effet, qui l'emporte sur le régime de sa catégorie ; l'historique est conservé. Critère : la fiche d'un agent dit quel régime s'appliquait à n'importe quelle date, et un bulletin ou un calcul de prime ancien ne change jamais.
- **O2.** Le **planning est un CRUD complet** pour tout le personnel (médical ou non) : créer, consulter, modifier, archiver, restaurer, dupliquer une semaine type, avec contrôle des incompatibilités (repos, double affectation) et refus nommés. Critère : scénario de bout en bout par rôle autorisé, refus nommé par rôle non autorisé.
- **O3.** Le **filtre avancé** est celui du standard du kit : période du/au avec raccourcis, sélection multiple (service, fonction, agent, type de vacation, statut), recherche texte, filtres enregistrables par utilisateur, effaçables d'un geste, **reportés sur l'état imprimé** (principe déjà posé par `print.js`).
- **O4.** Un **espace « Mes »** : dix-sept rubriques de l'agent (section 4), en lecture de ses propres données, avec saisie là où la Direction l'a demandé (présences, absences, congés, ordres de mission, rendez-vous), **validée par la DAF** quand la règle l'exige.
- **O5.** L'agent y accède **depuis l'application mobile** (hors ligne d'abord, synchronisation par le relais) **et** depuis le poste ; la saisie faite sur le téléphone atteint la mère et la DAF sans passer par un tiers.
- **O6.** **RG-13** : un agent ne voit que ses propres données RH ; la hiérarchie voit son périmètre ; la paie et le contrat ne sont lisibles que par l'agent, la DAF et la Direction. Critère : sondes par profil, jamais de donnée d'un autre agent sur l'écran ni dans la copie du téléphone.
- **O7.** Une **revue d'écarts** classe tous les écrans (section 8) : filtre avancé manquant, CRUD incomplet, paramètre système manquant, avec une priorité et une correction proposée.

## 3. Non-objectifs

- **Moteur de planification automatique** (générer les gardes à partir de contraintes) : v2. Ici, la saisie et le contrôle des incompatibilités.
- **Pointage biométrique ou badgeage** : le badge sert à la vérification d'identité (arbitrage de la vague 54), pas au pointage, tant que la Direction n'a pas tranché (question restée ouverte).
- **Paie recalculée sur le téléphone** : la fiche de paie affichée est la pièce **émise** par la mère, jamais recalculée à l'appareil (une pièce émise ne se réécrit jamais).
- **Modification des primes, des évaluations ou des sanctions par l'agent** : lecture seule.
- **Écriture web** (navigateur) : hors périmètre, voir `PRD-RELAIS-copie-consultable.md`.

## 4. Les dix-sept rubriques de l'espace « Mes » : ce qui existe, ce qui manque

| # | Rubrique demandée | Écran RH existant (vue de gestion) | Collection source | Saisie par l'agent | Validation |
|---|---|---|---|---|---|
| 1 | Ma fiche de poste | `m10-fiches-poste` | `fichesPoste` | non | non |
| 2 | Ma fiche de paie | `m11-bulletins` (module paie) | `bulletins` (pièce émise) | non | non |
| 3 | Mon contrat | `m10-contrats` | `contrats` | non | non |
| 4 | Mes planning et gardes | `m10-planning` | `planning` | **proposer un échange ou une indisponibilité** (P1) | surveillant ou DAF |
| 5 | Mes statistiques de garde | `m10-stats-gardes` | calculé | non | non |
| 6 | Mes statistiques des permanences | `m10-stats-permanences` | calculé | non | non |
| 7 | Mon taux de présence par service | `m10-stats-presence` | calculé | non | non |
| 8 | Mes présences et absences | `m10-presences` | `presences` | **oui (CRUD)** | **DAF** |
| 9 | Congés | `m10-conges` | `conges` | **oui (demande)** | **DAF** |
| 10 | Ordres de mission | `m10-missions` | `missions` | **oui (demande)** | **DAF** |
| 11 | Mes primes | `m10-primes` | `grillePrimes` et calcul de paie | non | non |
| 12 | Événements du personnel | `m10-evenements` | `evenements` | non (lecture) | non |
| 13 | Frais de participation | `m10-participations` | `participations` | non (lecture) | non |
| 14 | Mon assurance du personnel | `m10-assurance-personnel` | dossier patient lié par `personnelId` | non | non |
| 15 | Notes de service | `m13-notes-service` | `notesService` | non (lecture) | non |
| 16 | Agenda | `m2-agenda` | `rendezvous` | **oui** (déjà au mobile pour le soignant) | non |
| 17 | Rendez-vous et visites | `m2-rendezvous` | `rendezvous` | **oui** (déjà au mobile) | non |

Constat : les écrans de gestion existent pour les dix-sept rubriques ; ce qui manque, c'est la **vue de l'agent sur lui-même** (filtre par `personnelId` de la session, sans demander un droit d'écran sur toute la collection) et, pour quatre rubriques (présences, congés, missions, échange de garde), la **saisie par l'agent avec validation de la DAF**.

## 5. Récits d'utilisateur

- Comme **DAF**, je définis un régime de garde propre à un médecin, avec une date d'effet, pour que ses gardes diffèrent de celles de sa catégorie sans toucher aux autres, et je retrouve l'historique.
- Comme **surveillant**, je filtre le planning d'un mois par service, fonction et agent, et j'imprime exactement ce que je vois.
- Comme **médecin**, depuis mon téléphone hors ligne, je consulte mes gardes de la semaine, je déclare une absence, et la DAF la valide quand je suis de nouveau connecté.
- Comme **infirmier**, je demande un congé ; je vois son état (en attente, validé, refusé avec motif) sans voir celui des autres.
- Comme **agent**, je lis ma fiche de paie émise, mon contrat et mes primes, et personne d'autre que la DAF et la Direction ne peut les lire.
- Comme **DAF**, je valide ou refuse une absence, un congé ou une mission avec un motif obligatoire en cas de refus, et le refus est visible de l'agent.

## 6. Exigences

### P0 (sans eux, pas de livraison)

- **EX-1 Régime individuel.** Collection `regimesIndividuels` (agent, régime de base, champs dérogés, date d'effet, motif, auteur) et `historiqueRegimesIndividuels` : modèle de `grillePrimes` / `historiquePrimes`. Résolution : `D.regimeALaDate(agent, date)` (individuel s'il existe, sinon catégorie), jamais rétroactive sur une vacation déjà passée sans portée explicite. Refus nommés (date d'effet antérieure, motif manquant).
- **EX-2 Filtre avancé du planning.** Sur la grille (service, fonction, agent, type, période affichée) et sur le registre (période du/au, agent, fonction, service, type, statut archivé ou non, recherche texte). Filtres enregistrables par utilisateur, reportés sur l'impression.
- **EX-3 CRUD du planning pour tout le personnel**, avec droits explicites : DAF et surveillant écrivent leur périmètre, le médecin propose pour lui-même (P1), refus nommés, journal RG-12.
- **EX-4 Espace « Mes » en lecture** (rubriques 1 à 3, 5 à 7, 11 à 15) : vue de l'agent sur ses propres données par `personnelId` de la session ; aucun droit d'écran sur la collection entière n'est accordé pour cela.
- **EX-5 Saisie avec validation** (rubriques 8, 9, 10) : l'agent crée, la DAF valide ou refuse (motif obligatoire au refus), l'état est visible de l'agent. Au niveau des échanges entre postes, c'est la famille **W** (flux de travail) de la règle de fusion de l'ADR-0006 : soumettre, valider, rejeter par le rôle habilité.
- **EX-6 Mobile.** Nouveau profil **agent** (en plus de soignant et réception de secours) : les rubriques ci-dessus, hors ligne d'abord, par le relais seul (jamais d'appel direct à la mère), copie locale **limitée aux données de l'agent connecté** (RG-13 : la configuration et les données des autres ne descendent jamais sur son téléphone).
- **EX-7 Sondes.** Un scénario maquette par rubrique de saisie ; sondes RBAC par profil (l'agent A ne voit pas l'agent B) ; test de non-fuite sur la copie du mobile ; vecteurs depuis les écrans réels pour le domaine Dart.

### P1

- **EX-8 Échange de garde entre deux agents** avec accord des deux et validation du surveillant ; **indisponibilité** déclarée par l'agent.
- **EX-9 Semaine type** (dupliquer une semaine vers une autre) et **conflits visibles** (deux agents sur la même garde sans remplaçant).
- **EX-10 Notifications** : l'agent est notifié du refus ou de la validation ; la DAF est notifiée des demandes (moteur d'alertes existant, source `rh_a_valider`).
- **EX-11 Revue d'écarts** (annexe, section 8) : correction des écarts de priorité haute.

### P2 (à ne pas rendre difficile)

- Génération assistée des gardes, pointage par badge, export iCalendar du planning personnel, vue « planning de l'équipe » partageable.

## 7. Paramétrage système à intégrer

Aujourd'hui en dur ou dispersé, à porter en réglages administrables (écran `cfg-*`, versionnés par date quand une pièce émise en dépend) :

| Paramètre | Où il vit | Proposition |
|---|---|---|
| Durée de repos après une garde (24 h, 48 h) | constantes `D.REGLES_PLANNING` | réglage par régime, daté |
| Types de vacation et leurs couleurs | `D.TYPES_PLANNING` | référentiel administrable |
| Services du planning | `D.SERVICES` | lire les secteurs NS 145 (une seule source) |
| Délai de dépôt d'une demande de congé, plafond annuel, jours fériés | absents | réglages RH datés (jours fériés par année) |
| Circuit de validation (qui valide quoi : DAF, surveillant, Direction) | écrit dans les écrans | réglage par type de demande |
| Fenêtre de modification d'un planning publié | absente | réglage (« figé à J-2 », avec dérogation motivée) |
| Données exposées sur le mobile de l'agent | à définir | liste blanche par rubrique, désactivable |

## 8. Revue d'écarts demandée (annexe)

La Direction demande, en expert de conception de progiciel aux normes internationales, quels écrans manquent de **filtre avancé**, de **CRUD**, ou d'un **paramétrage système** à intégrer. L'inventaire est outillé (relevé des écrans réels, pas lecture à l'œil) et livré dans `docs/architecture/AUDIT-FILTRES-CRUD-PARAMETRAGE.md` ; il alimente la priorisation d'EX-11. Critères de la norme retenue :

- **Filtre avancé** : recherche texte, période du/au, sélection multiple sur les axes métier de la liste, tri, filtres enregistrables, effacement d'un geste, report sur l'impression et l'export.
- **CRUD complet** : créer, consulter, modifier, archiver (jamais supprimer, RG-14), restaurer, avec droits par commande, refus nommés, journal.
- **Paramétrage** : toute valeur métier qui change dans le temps (taux, seuils, durées, listes, circuits) est un réglage versionné par date, jamais une constante.

## 9. Décisions à valider par la Direction

| # | Question | Ma recommandation | Qui |
|---|---|---|---|
| **Q1** | Le régime individuel **remplace-t-il** celui de la catégorie, ou ne déroge-t-il que sur les champs renseignés ? | **déroge champ par champ** (durée, repos, honoraire), le reste suit la catégorie | Direction, DAF |
| **Q2** | Qui valide les **absences et présences** : la DAF seule, ou le surveillant d'abord puis la DAF ? | surveillant pour le service, **DAF pour le tout**, la DAF pouvant valider seule (demande du 06/11/2026) | Direction |
| **Q3** | Les **congés et ordres de mission** suivent-ils le même circuit ? | oui, DAF ; mission avec avis du chef de service | Direction |
| **Q4** | L'agent peut-il **modifier** son planning (échange) sans passer par le surveillant ? | non : il **propose**, le surveillant valide | Direction |
| **Q5** | La **fiche de paie** descend-elle sur le téléphone ou se consulte-t-elle en ligne seulement ? | copie chiffrée locale de la pièce **émise** de l'agent seul, désactivable par réglage | Direction, Ingénierie |
| **Q6** | **Tout le personnel** a-t-il un smartphone ? Sinon l'espace « Mes » est-il accessible sur un poste partagé après connexion nominative ? | oui, poste partagé en secours (session nominative déjà en place) | Direction |
| **Q7** | Le **badge** sert-il de pointage ? | différer ; la présence se déclare et se valide | Direction |
| **Q8** | La **rubrique « Mon assurance du personnel »** reste-t-elle en lecture seule (la clinique soigne ses agents à 100 %) ? | oui | Direction |

## 10. Métriques de réussite

- 100 % des vacations affichent leur régime résolu **à leur date** ; zéro bulletin ou prime ancien modifié par un changement de régime (sonde).
- Les filtres du planning réduisent un mois de 40 agents à un service en un geste, et l'état imprimé porte les filtres en force (sonde sur la pièce).
- Une absence saisie hors ligne sur le téléphone est validée par la DAF et revient à l'agent dans les 60 secondes de reconnexion (banc, relais réel).
- Aucune donnée d'un autre agent dans l'écran, la copie locale du mobile ni le journal d'échanges (sonde de non-fuite).

## 11. Ce qui ne peut pas être vérifié ici

Le mobile sur un appareil Android réel, la synchronisation sur deux appareils physiques, l'accessibilité au lecteur d'écran, l'usage terrain par un surveillant sur un planning de quarante agents.

## 12. Phasage

1. **Maquette** : régime individuel et son historique (EX-1), filtres du planning (EX-2), CRUD complet (EX-3), vue « Mes » en lecture et saisie validée (EX-4, EX-5), paramètres RH (section 7), scénario et vecteurs.
2. **Domaine Dart** : résolution du régime à la date, circuit de validation, règles de visibilité par agent ; rejeu des vecteurs.
3. **Poste** : écrans, parité N1, espace « Mes » sur poste partagé.
4. **Mobile** : profil agent, copie locale bornée, saisie hors ligne et validation par le relais (famille W).
5. **Revue d'écarts** (EX-11) : corrections de priorité haute, puis le reste au fil des retouches.
