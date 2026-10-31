# PRD — Poste Flutter desktop fidèle à la maquette `prototype_html/`

| | |
|---|---|
| **Statut** | brouillon 26/10/2026 — ADR-0003 est *proposée*, pas acceptée : ce PRD est conditionné au banc de validation (§ Questions ouvertes, Q1) |
| **Cible** | `apps/poste` (Flutter desktop Windows 10/11 + Linux), puis `apps/mobile` sur le même code d'interface |
| **Sources** | `CLAUDE.md` (doctrine de la maquette), `docs/architecture/ARCHITECTURE-CIBLE.md`, ADR-0001/0002/0003, `docs/prd/PRD-SOCLE-*`, `prototype_html/` (306 pages, 74 scénarios, 1 185 vérifications) |

## 1. Problème

La maquette `prototype_html/` (PHP + PostgreSQL, ≈ 84 000 lignes de JS, 305 écrans, 333 impressions) est validée par la Direction écran par écran, mais elle ne peut pas être le produit : un seul serveur sans autonomie des postes, droits RBAC appliqués surtout côté navigateur, magasin réécrit par collection entière, aucune continuité hors ligne ni boîtier MECeF physique. La cible (ADR-0001/0003) est un poste Flutter autonome (SQLite chiffré) synchronisé à un hub PostgreSQL.

**Le risque principal n'est pas technique, il est de fidélité** : une réécriture de cette taille dérive. Chaque règle de gestion, chaque refus nommé, chaque libellé arbitré par la Direction (vagues 1 à 70 du `CLAUDE.md`) est une décision déjà payée. Les perdre au portage obligerait à les redemander. Ce PRD définit ce que « fidèle » veut dire de façon **mesurable**, pour que « 100 % » soit un critère de recette et non une intention.

## 2. Définition de « 100 % fidèle »

Fidèle = **à périmètre et comportement identiques, vérifié par des mesures**, pas « ressemble ». Cinq axes, chacun avec sa preuve :

| Axe | Ce qui doit être identique | Preuve |
|---|---|---|
| **Fonctionnel** | Chaque écran du manifeste (`nav.js`) existe, chaque commande fait la même chose | Matrice de parité 306 → 306 ; 74 scénarios portés en tests d'intégration Dart, 1 185 vérifications |
| **Règles de gestion** | RG-01 → RG-14 et toutes les règles nommées (refus nommés, trois états « réglé / dû / sans pièce liée », verrous du labo, avoirs…) | Vecteurs de tests partagés (JSON entrée → sortie) exécutés par la maquette **et** par `packages/domaine` |
| **Droits (RBAC)** | Ce que chaque rôle voit et peut écrire, écran par écran, 16 rôles | `inventaire-rbac` et `audit-rbac` rejoués contre l'app Flutter : 0 promesse, 0 lecture non dite ; écart avec la matrice maquette = 0 |
| **Visuel** | Mise en page, hiérarchie, couleurs, typographie, états vide/chargement/erreur | Captures de référence (Chrome, `build/shot.js`) comparées aux captures Flutter, seuil de différence par écran (§ P0-3) |
| **Impression** | Les 333 états, l'en-tête légal unique, les trois gabarits (A4, ticket 80 mm, carte CR80), totaux calculés | Rendu PDF comparé page à page ; extraction de texte (`_pdftext`) identique |

**Hors de cette définition** (assumé, pas une infidélité) : la mécanique de stockage et de synchronisation (SQLite + journal d'opérations remplacent PostgreSQL + magasin JSON, c'est l'objet de la migration), l'usage du navigateur (`localStorage`, repli sans serveur), et tout ce que la maquette marque « simulé » (file MECeF en ligne, collecte d'enquête locale).

## 3. Objectifs

1. **Parité fonctionnelle mesurée** : 306/306 écrans du manifeste présents, 0 écran « non porté » à la recette finale.
2. **Parité des règles prouvée** : 100 % des vecteurs de tests du domaine passent à l'identique sur la maquette et sur Dart (zéro règle en double hors du paquet partagé).
3. **Parité des droits** : écart de matrice RBAC maquette ↔ Flutter = 0 sur les 16 rôles.
4. **Parité visuelle** : ≥ 95 % des écrans sous le seuil de différence de capture (stretch : 100 %, exceptions documentées une à une).
5. **Gain de produit sans régression** : fonctionne hub arrêté (critère 1 du banc d'ADR-0003), liste de 20 000 lignes < 1 s, recherche patient < 300 ms.

## 4. Non-objectifs

- **Pas de redesign.** Toute amélioration d'ergonomie attend la parité ; elle passe par un PRD à part. Une « amélioration » faite en cours de portage est une infidélité.
- **Pas de nouvelle fonctionnalité métier** pendant le portage (le gel de la maquette, `prototype_html/` hors workspaces, s'applique : seules les corrections de défaut sont rétro-portées aux deux côtés).
- **Pas de portail patient, télémédecine, application grand public** (CDCT §4.3, hors périmètre).
- **Pas d'écran-par-écran naïf** : on porte par **tranches verticales** (ADR-0003), pas à plat — le coût dominant et le risque se jugent à la caisse + MECeF + impression d'abord.
- **Pas de migration des 18 000 dossiers papier** (hors périmètre CDCT).
- **Mobile** : même code d'interface adaptatif, mais l'émission fiscale depuis un smartphone reste exclue (ADR-0003).

## 5. Utilisateurs

Les 16 rôles de la matrice (médecin, chirurgien, anesthésiste, infirmier, aide-soignant, sage-femme via fonction, biologiste médical, échographiste, réception, caissier(ère)-dispensateur(trice), gestionnaire de stock, comptable, assistant comptable, DAF/DA, Direction, admin, ambulancier, surveillant, assistant de direction…). Persona critique pour la fidélité : **l'agent qui connaît déjà la maquette** (formé ou recetté sur elle) — pour lui, tout écart est un défaut, pas une évolution.

## 6. Récits utilisateur

**Agent de poste**
- En tant que caissière, je veux retrouver à l'identique le parcours prescription → encaissement ligne par ligne → reçu détaillé → déblocage des examens, pour ne pas réapprendre mon poste.
- En tant que biologiste, je veux les deux verrous (validation technique / biologique), la rectification versionnée et les plages par lot, pour que mes comptes rendus restent opposables.
- En tant que sage-femme, je veux le dossier obstétrical, le partogramme coté et le tableau de bord de la maternité à l'identique, pour tenir le registre national.
- En tant qu'agent de réception, je veux une saisie rapide (formulaire à six colonnes, combos avec recherche, navigation clavier) qui ne perd pas ma saisie à la navigation.

**Direction / administration**
- En tant que Directrice, je veux que la matrice RBAC que j'ai arbitrée soit celle de l'application finale, sans réécriture involontaire.
- En tant qu'administrateur, je veux les mêmes paramétrages (modules actifs, rôles, tarifs, barèmes) administrables au même endroit.

**Ingénierie / recette**
- En tant que développeur, je veux un manifeste unique de parité (écran → statut → test) pour savoir en un coup d'œil ce qui reste.
- En tant que responsable recette, je veux que chaque écart visuel ou fonctionnel soit nommé et tracé, jamais « corrigé d'office ».

**Cas limites**
- En tant qu'agent hors ligne, je veux voir la même pastille d'état et les mêmes refus nommés, et qu'une écriture refusée par le hub se retrouve en conflit **visible**, jamais en silence.

## 7. Exigences

### P0 — Sans cela, pas de « fidèle »

**P0-1. Manifeste de parité vivant** (`docs/architecture/PARITE-MAQUETTE.md`, engendré).
Une ligne par écran du manifeste `nav.js` : identifiant, module, domaine, rôles, tranche, statut (non commencé / porté / recetté), scénarios couvrants, captures de référence.
*Critères* : généré depuis `nav.js` (jamais saisi à la main) ; un écran ajouté au manifeste apparaît « non commencé » ; le total est affiché en tête (x / 306).

**P0-2. Domaine partagé et vecteurs de tests.**
Les règles RG-01→14 et les règles nommées vivent dans `packages/domaine` (+ `rbac`, `referentiels`, `impression`, `schema`). La maquette exporte des cas JSON (entrée → sortie) depuis ses moteurs exposés (`SIGH.emettreAvoir`, `PR.repartir`, `PR.encaisser`, `SIGH.exercice`, `SIGH.laboPlages`, `SIGH.bfr`, `PR.couvertureALaDate`…).
*Critères* : Given un vecteur, When il est rejoué sur la maquette et sur Dart, Then les sorties sont identiques (montants au franc, motifs textuels compris) ; aucune règle n'existe en deux exemplaires ; un vecteur qui diverge bloque le portage de l'écran concerné.

**P0-3. Fidélité visuelle mesurée.**
Design tokens extraits de `tailwind.config.js` / `src/input.css` (couleurs navy, sémantique vert/orange/rouge, Inter vendorée, tailles) vers un `ThemeData` unique ; composants Flutter équivalents du kit (`U.dataTable`, `U.combo` / `multiselect`, `U.form` à six colonnes, modale, tiroir, `K.dash`, `K.parcours`, `K.fileAttente`, toasts en haut à droite…).
*Critères* : pour chaque écran, capture Flutter vs capture maquette (mêmes données de jeu, même rôle, 1440 px et 400 px) ; écart sous seuil défini en Q4 ; **aucune couleur en dur** hors du thème ; typographie ≥ 11 pt équivalent ; états vide / chargement / erreur présents.

**P0-4. Porter le ruban, pas inventer une navigation.**
Méga-menu horizontal en ruban, filtré par rôle, par module actif et par surcharge d'écran, repli automatique, fil d'Ariane, hubs de module, accès rapides déduits, recherche globale avec rubriques et liens profonds.
*Critères* : `N.tree(role)` de la maquette et l'arborescence Dart donnent la **même liste d'écrans** pour chacun des 16 rôles (comparaison automatique) ; un écran fermé au profil n'est jamais proposé (RG-13) ; adresse d'un module fermé → écran 403 ; navigation sans rechargement, état de saisie conservé.

**P0-5. RBAC au domaine, appliqué au poste ET au hub.**
Matrice (rôle × module × `voir/editer/annuler`), surcharges d'écran qui accordent autant qu'elles restreignent, `universel`, `servant`, alias, `secondaire`, rôle sans fiche, rôle archivé, modules désactivés.
*Critères* : `audit-rbac` rejoué (≥ 841 sondages écran × profil) : 0 promesse, 0 lecture non dite ; les commandes d'écriture refusées sont **absentes** (pas grisées) ; le hub refuse côté serveur ce que le poste interdit.

**P0-6. Impression : trois gabarits et l'en-tête unique.**
A4 avec en-tête légal unique (IFU 3201642748214, RCCM RB/NAT/2016-B-268) et pied normalisé (date/heure, utilisateur, identifiant, pagination) ; ticket 80 mm (bloc MECeF, montant en lettres, formules de la clinique) ; carte CR80 (sans IFU/RCCM) ; totaux **calculés** (`somme`) jamais fournis ; filtres en force portés sur la pièce.
*Critères* : les 333 états rendus en PDF ; comparaison page à page et par extraction de texte avec la maquette sur le même jeu ; un ticket 80 mm, un A4 de 60 lignes, une carte CR80 imprimés sous Windows **et** Linux (critère 4 du banc).

**P0-7. Typographie et formats français.**
`C.money` (espace fine insécable U+202F entre milliers, insécable avant la devise), dates, montants en lettres, saisie à virgule.
*Critères* : suite de cas de formatage identiques ; une sonde compare les chiffres seuls, toute espace neutralisée.

**P0-8. Port des 74 scénarios.**
Chaque scénario devient un test d'intégration Dart (même parcours, mêmes vérifications), exécuté contre un poste + un hub de test.
*Critères* : 74/74, 1 185 vérifications ; les scénarios qui modifient la matrice ou vident une collection la **restaurent** ; une ligne se retrouve par sa **référence**, jamais par son rang ; chaque échec est nommé sur-le-champ.

**P0-9. Tranche 1 verticale : caisse + MECeF + impression.**
Parcours complet prescription → facture à lignes payables → part assureur / patient / non assuré → encaissement partiel → déblocage des demandes nommées → écriture comptable en brouillon équilibrée (RG-10) → ticket 80 mm → boîtier MECeF (base MECeF = part patient seulement).
*Critères* : hub arrêté et Internet coupé, la caisse émet ; coupure du boîtier en cours d'émission puis reprise sans doublon fiscal (critère 3 du banc).

**P0-10. Hors ligne et conflits nommés (ADR-0001).**
Journal d'opérations, famille de fusion déclarée pour chaque écriture, numéros provisoires, archivage au lieu de suppression (RG-14), pastille d'état permanente, refus d'écriture anonyme (RG-12).
*Critères* : deux postes créent un dossier hub arrêté → zéro doublon de code (RG-01) ; deux postes sortent le dernier lot → conflit visible, jamais de stock négatif (RG-03).

**P0-11. Sécurité du poste.**
Base SQLite chiffrée (SQLCipher), secret dans le coffre du système, verrouillage de session à 15 min avec retour à l'écran et à l'onglet près, révocation d'appareil, journal d'audit complet. Le mot de passe est **saisi, jamais conservé** ; aucun secret dans le dépôt (`*.local.php`, `.env` jamais versionnés).
*Critères* : disque copié → base illisible sans le coffre ; appareil perdu → révoqué à la reconnexion (critère 7).

### P1 — Fast-follow

- **P1-1.** Tranches 2 à n dans l'ordre du risque : pharmacie/stock (FEFO, RG-03/05) → laboratoire (verrous, plages par lot) → hospitalisation/maternité → comptabilité (liasse, clôture d'exercice) → RH/paie → administration. Pour chaque tranche : écrans, scénarios et captures verts avant la suivante.
- **P1-2.** Notifications consommatrices et planificateur : les tâches de `api/cron.php` (échéances, seuils, péremptions FEFO, rendez-vous du lendemain, créances âgées, sauvegarde) deviennent des tâches du hub ; alertes routées par rôle **côté hub** ; son = canal, jamais de donnée médicale dans l'alerte.
- **P1-3.** Mobile Android sur le même code adaptatif (KPI en accordéons, tableaux en cartes, bouton d'action flottant), en consultation et saisie ; jamais d'émission fiscale.
- **P1-4.** Outil de comparaison automatique de captures en CI (Windows + Linux).

### P2 — À ne pas empêcher

- Moteur de synchronisation définitif (ADR-0004 : PowerSync / ElectricSQL / maison).
- Extraction de packs « autre clinique » (modules activables par clinique, déjà conçus en vague 50).
- Ré-arbitrage d'architecture pour la collecte publique depuis Internet (page hébergée ailleurs, jamais le hub exposé).
- iOS si le parc le demande.

## 8. Règles de fidélité à ne jamais défaire

Ces points sont des décisions de la Direction ; les rouvrir demande une décision explicite.

- **En-tête légal unique** (arbitrage 31/08/2026) ; rôle `aide_comptable` = « Assistant Comptable » ; Zone 1 / Zone 2 du dossier ; dépenses multi-lignes ; l'avoir remplace l'annulation.
- **Une pièce émise ne se réécrit jamais** ; une donnée de référence qui change se **versionne par date** (couverture assurance, grille des primes, plages par lot).
- **Une restriction s'annonce** ; une commande refusée est absente ; un état vide **le dit** ; « non calculable » n'est pas zéro ; un tiret n'est ni zéro ni exclusion.
- **Aucun montant ni numéro d'urgence inventé** ; ce qui attend un professionnel nommé reste marqué « à valider ».
- **Aucune règle en double** : la leçon payée à chaque fois (code patient, `carteValide`, date du jour).
- **Écrans bi-domaines par alias**, rangées `secondaire`, `servant`, `universel` : mécanismes du manifeste à porter tels quels.
- **Piège hissage / amorçage** : tout référentiel lu par plusieurs modules s'amorce au socle, jamais par un écran.

## 9. Parité : méthode de portage d'une tranche

1. **Figer la référence** : captures, vecteurs de tests et scénarios de la tranche, rejoués sur la maquette (vert avant de commencer).
2. **Porter le domaine** (`packages/domaine`) et rejouer les vecteurs.
3. **Porter les écrans** avec les composants du kit, dans le thème commun.
4. **Rejouer** : captures, scénarios, audit RBAC de la tranche.
5. **Recette Direction** de la tranche, puis **gel** (aucune modification sans PRD).
6. Revue d'ADR-0003 à la fin de la tranche 1 (puis à six mois d'exploitation).

## 10. Métriques de succès

**Indicateurs avancés**
| Indicateur | Cible succès | Stretch | Mesure |
|---|---|---|---|
| Écrans portés / 306 | 100 % à la livraison | — | `PARITE-MAQUETTE.md` (engendré) |
| Vecteurs de domaine identiques | 100 % | — | CI, maquette vs Dart |
| Scénarios portés | 74/74 (1 185 vérif.) | — | CI poste + hub de test |
| Écrans sous seuil visuel | ≥ 95 % | 100 % | comparaison de captures |
| Sondages RBAC en écart | 0 | — | `audit-rbac` rejoué |

**Indicateurs de performance** (banc d'ADR-0003, sur le matériel réel de la clinique) : liste de 20 000 lignes < 1 s ; recherche patient < 300 ms ; latence de synchro p95 < 5 s avec 15 postes + 5 téléphones.

**Indicateurs retardés**
- Écarts « ça ne marche pas comme avant » signalés par les agents au premier mois : **≤ 5 par module**.
- Reprises de règle par la Direction après portage : **0** (une règle redemandée = une règle perdue).
- Incidents fiscaux (doublon MECeF, pièce déséquilibrée) en exploitation : **0**.

## 11. Risques

| Risque | Mitigation |
|---|---|
| Coût de réécriture (≈ 80–100 000 lignes) | tranches verticales, risque d'abord, prototype = spécification vivante |
| Tableaux denses et impression de pages longues sur Flutter desktop | critères 4 et 5 du banc **avant** tout écran métier |
| Greffons série/USB/thermique inégaux sur Linux | critères 3 et 4 du banc, repli nommé (hub .NET / poste alternatif) |
| Dérive par « petites améliorations » | non-objectif explicite, gel par tranche |
| Règle recopiée en Dart à côté du domaine | revue : toute règle hors `packages/domaine` est refusée |
| Boîtier MECeF non documenté | dix questions au fournisseur et à la DGI (ADR-0003) avant tout code d'intégration |

## 12. Questions ouvertes

**Bloquantes**
- **Q1 (direction + ingénierie)** — ADR-0003 est *proposée* : le banc à sept critères doit passer avant d'accepter Flutter. Qui exécute le banc, et sur quel matériel ?
- **Q2 (fournisseur / DGI)** — Modèle, interface et protocole du boîtier MECeF : indispensables à la tranche 1.
- **Q3 (ingénierie)** — Moteur de synchronisation (ADR-0004) : nécessaire avant d'écrire la couche de données du poste.
- **Q4 (design + direction)** — Seuil de différence visuelle acceptable par écran (pixels, ou différence perceptuelle ?) et rendu de référence (Chrome Windows ? Linux ?).

**Non bloquantes**
- **Q5 (direction)** — Qui réalise radiographie, scanner, IRM ? (resté à arbitrer en vague 61)
- **Q6 (direction)** — Quatre points des badges : durée de validité, format du numéro, mentions du verso, usage pour le pointage.
- **Q7 (ingénierie)** — Les écrans « simulés » de la maquette (file MECeF en ligne, enquête locale) : portés tels quels, ou remplacés par la vraie fonction cible ?
- **Q8 (ingénierie)** — Calendrier d'extinction de `prototype_html/` : conservé comme référence de recette jusqu'à quelle date ?

## 13. Phasage

| Phase | Contenu | Sortie |
|---|---|---|
| **0 — Banc** | sept critères d'ADR-0003 sur matériel réel, Windows + Linux ; export des vecteurs et captures de référence ; manifeste de parité engendré | ADR-0003 acceptée ou repli |
| **1 — Socle + tranche 1** | `packages/domaine`, `schema`, `rbac`, thème, kit de composants, ruban ; caisse + MECeF + impression | revue d'ADR ; recette de la caisse |
| **2 → n — Tranches** | ordre du risque (§ P1-1), une recette Direction par tranche | parité x / 306 croissante |
| **Finale** | 306/306, 74/74, RBAC à 0 écart, recette globale, formation par rôle | mise en service par clinique pilote |

Pas de dates : le calendrier dépend du résultat du banc et de l'effectif Flutter/Dart (non documenté).

## 14. Hors ligne et synchronisation (section obligatoire)

Le poste est **autonome** : toute écriture va d'abord dans SQLite chiffré, puis dans le journal d'opérations vers le hub. Chaque écriture déclare sa **famille de fusion** (spec par écran) ; aucune suppression ne se propage (RG-14 : archivage) ; aucune donnée métier ne se synchronise par un outil de fichiers ; les numéros attribués hors ligne sont provisoires puis réconciliés sans jamais modifier un code déjà donné (RG-01). Voir `PRD-SOCLE-synchronisation-bidirectionnelle.md` et `PLAN-synchronisation-bidirectionnelle.md`. La maquette reste en « dernier geste gagne » : c'est une différence **assumée** de comportement sous conflit, car le but du portage est précisément de la remplacer par des conflits nommés.
