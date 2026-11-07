# PLAN — Synchronisation bidirectionnelle (poste · hub · client web · mobile)

Source : [PRD-SOCLE-synchronisation-bidirectionnelle](../prd/PRD-SOCLE-synchronisation-bidirectionnelle.md) · ADR-0001 · ADR-0003 (proposé) · PRD-SOCLE-application-sans-rechargement (EF-SOC-05 à 07)
Statut : brouillon du 26/10/2026 · Estimation : 5 phases, **S0 à S2 dans le prototype (≈ 3 à 4 semaines)**, S3 à S5 sur la pile cible (dépendent de l'acceptation d'ADR-0003)
Branche : `claude/sighcnt-monorepo-offline-first-i0v3v9` (une branche de phase si le chantier se scinde)

## Résultat attendu

1. Dès la phase S0–S2, **sur le prototype** : aucune saisie perdue à la fermeture d'un onglet hors ligne, aucun écrasement silencieux (un conflit est détecté, nommé et traité), la pastille et un écran « Conflits à régulariser » disent l'état réel.
2. À la fin de S3 : un **banc de synchronisation à deux postes + hub** prouve 0 opération perdue, convergence, conflit d'invariant visible — le critère qui permet d'accepter ou de refuser la pile (ADR-0003) et de choisir le moteur (ADR-0004).
3. À la fin de S5 : poste de bureau, client web de secours et mobile se synchronisent par **un seul contrat d'opérations**.

Chaque étape laisse le dépôt vert (`npm run verify` + `audit-rbac`).

## Ordre et dépendances

```
S0 (prototype : file persistée, versions de fiche) ─┬─> S1 (détection de conflit + écran)
                                                     └─> S2 (numéros provisoires, tranches)
S1 + S2 ──> S3 (contrat d'opérations + banc à deux postes)  ──> ADR-0004 (moteur) ── décision Direction
S3 accepté ──> S4 (hub + poste + MECeF)  ──> S5 (mobile, fichiers, réplica, client web de secours)
```

S0 à S2 **ne dépendent d'aucun arbitrage** : elles corrigent le prototype tel qu'il est et produisent les
vecteurs de test du banc. S3 est l'étape de **décision** ; rien de S4/S5 ne démarre avant.

---

## Phase S0 — Le prototype cesse de perdre et d'ignorer (sans changer de modèle)

### Étape S0.1 — Persister la file des gestes en attente
- Fichiers : `prototype_html/assets/js/store.js` (`FILE`, `transmettre`, `viderFile`, `PANNE`), `app.js` (pastille).
- Ce qu'on fait : écrire `FILE.actions` dans IndexedDB (repli `localStorage` borné) à chaque ajout/retrait ; au chargement, rejouer ce qui reste **avant** toute nouvelle écriture ; un identifiant par geste (`gid`, UUID) pour que le rejeu soit idempotent côté serveur.
- Pièges : le magasin du navigateur sature (vague 60/64) — mesurer la taille de la file, plafonner et **dire** quand le plafond est atteint ; une file dont le geste est refusé en dur (4xx autre que 401) ne doit pas boucler : la sortir en « refusé » visible ; `var` déclaré avant tout appel de rendu.
- Vérification : nouveau scénario « fermeture hors ligne » : serveur coupé → 3 gestes → rechargement de l'onglet → serveur rendu → les 3 fiches sont en base, une fois chacune. `npm run test`.
- Peut être livrée seule : oui.

### Étape S0.2 — Idempotence côté serveur
- Fichiers : `prototype_html/api/crud.php`, table `gestes_traites` (installée par `sigh_installer`, bornée à 5 000 lignes comme `executions_taches`).
- Ce qu'on fait : si le `gid` d'un geste est déjà traité, rendre la réponse d'origine sans réécrire ; sinon traiter et enregistrer le `gid`.
- Pièges : ne pas toucher `api/` pendant un banc ; le PHP intégré est mono-processus — pas de verrou applicatif inutile ; nouvelle table → régénérer le schéma si elle devient collection (ici non : table technique).
- Vérification : scénario : même geste envoyé deux fois → une seule fiche, deux réponses identiques.
- Peut être livrée seule : oui (avec S0.1 pour l'usage réel).

### Étape S0.3 — Version de fiche
- Fichiers : `store.js` (insert/update), `api/crud.php` (champ `_v` entier croissant par fiche, posé par le **serveur**), `api/projection.php` (le champ tombe dans `extra` sans effet, à vérifier).
- Ce qu'on fait : chaque fiche porte `_v` ; `modifier` envoie `vBase` (la version que l'appareil avait lue). Le serveur incrémente. Aucun comportement visible encore.
- Pièges : **les champs nuls ne s'écrivent plus** (`sansNuls`) — un `_v` à 0 doit rester écrit ; un null relu comme `undefined` ; `'champ' in record` ne voit plus un champ nul ; incrément de `VERSION` (nouveau champ de forme) → **`VERSION` unique dans `store.js`**.
- Vérification : parité (`php api/projection.php --verifier`) à 0 écart ; `npm run test` vert ; mesure du magasin (Ko) avant/après — le quota est la contrainte.
- Peut être livrée seule : oui.

---

## Phase S1 — Aucun écrasement silencieux

### Étape S1.1 — Détecter la modification concurrente
- Fichiers : `api/crud.php` (`modifier`, `archiver`, `restaurer`), `store.js` (gestion de la réponse).
- Ce qu'on fait : si `vBase` ≠ `_v` courant, comparer **champ par champ** : champs disjoints → fusion et réponse `fusionne`, champ commun modifié → réponse `conflit` avec les deux valeurs, sans rien écrire ; `archiver` sur une fiche dont la version a changé → `conflit`.
- Pièges : la comparaison se fait sur le **correctif** (champs envoyés), pas sur la fiche entière ; RG-14 : aucune action `supprimer` ne doit apparaître ; RG-12 : l'auteur reste posé par le serveur.
- Vérification : scénario « deux postes » (session admin + deuxième jeton via `BANC.connecter`) : A change le téléphone, B le quartier → les deux conservés ; A et B changent le téléphone → réponse `conflit`, fiche inchangée.
- Peut être livrée seule : oui.

### Étape S1.2 — Collection `conflits` et écran « Conflits à régulariser »
- Fichiers : `store.js` (semis au socle de `conflits`, **taille mesurée**), `assets/js/nav.js` (écran, rangée M14 ou alias Accueil), `modules/m14-securite.js`, `data.js` (`LIBELLES` pour la corbeille), `build/gen-schema-pg.js` (régénération).
- Ce qu'on fait : un conflit crée une fiche avec : collection, fiche, champ, valeur A/B, auteurs, heures, poste responsable (`D.secteurNormalise`/rôle propriétaire de la collection), état (ouvert/décidé). L'écran liste, filtre, décide (garder A / garder B / saisir) via `K.commande` ; la décision est une écriture journalisée.
- Pièges : toute écriture par `K.commande`/`K.droits` (RBAC vague 37) ; une restriction s'annonce (le bandeau nomme le rôle) ; `servant` si une page de saisie ; écran déclaré dans `nav.js` puis `npm run pages` ; ajouter la ligne `LIBELLES` ; fiche RBAC des rôles concernés (un rôle sans fiche a tous les droits).
- Vérification : `npm run pages && npm run check` (0 lien cassé), `npm run audit-rbac` (0 promesse), scénario de décision (garder B → la fiche porte B, la tâche disparaît des deux postes).
- Peut être livrée seule : après S1.1.

### Étape S1.3 — Dire la vérité à l'écran
- Fichiers : `app.js` (`pastilleSync`), écran de diagnostic (M14 `m14-taches` ou nouveau).
- Ce qu'on fait : la pastille affiche les gestes en attente **et** les conflits ouverts ; le diagnostic liste la file, les refus et le mode de résolution actif (« version détectée » depuis S1.1 ; « dernier geste gagne » pour le chemin `magasin.php` collection entière tant qu'il existe).
- Pièges : sur téléphone, la pastille masque son libellé sous 640 px (scénario responsive existant).
- Vérification : scénarios 72/73 existants toujours verts ; nouvelle assertion sur le texte du diagnostic.
- Peut être livrée seule : oui.

### Étape S1.4 — Fermer le chemin « collection entière »
- Fichiers : `store.js` (`flushDelta` / POST `magasin.php`), `api/magasin.php`.
- Ce qu'on fait : inventorier qui l'appelle encore (écrans, semis, `viderActivite`, import) ; ne le garder que pour le semis initial, la remise à zéro et l'import ; toute autre écriture passe par `crud.php` (fiche). Le POST d'une collection non vide sur un magasin déjà semé est refusé en le disant.
- Pièges : `S.viderActivite` et `S.reset()` s'appuient sur lui (vague 68) — ne pas casser le vidage qui tient ; le semis du **premier accès** ; `evenements`.
- Vérification : `npm run test` 74/74, scénario 72 (tables) et 73 (deux postes) verts ; grep des appels résiduels documenté dans le plan.
- Peut être livrée seule : oui (la plus risquée de S1 : faire en dernier).

---

## Phase S2 — Les numéros ne se doublonnent pas hors ligne

### Étape S2.1 — Inventaire des séquences
- Fichiers : `parcours.js` (`PR.codeAnalyse`, `PR.numeroBadge`, `C.codePatient`, pièces certifiantes, `AN-…`), `store.js` (compteurs).
- Ce qu'on fait : lister **toutes** les fabriques de numéros, leur format, leur série (annuelle ?), leur lieu de stockage, et si elles tournent côté client ou serveur. Aucun code.
- Pièges : la règle qui vit en deux exemplaires diverge (leçon du code patient) — noter chaque doublon.
- Vérification : tableau dans ce plan (ou en annexe du PRD) ; relu par le propriétaire du module.
- Peut être livrée seule : oui.

### Étape S2.2 — Tranches de numéros par poste
- Fichiers : `api/crud.php` (action `reserver_plage`), table `plages_numeros`, fabriques de S2.1.
- Ce qu'on fait : un poste réserve une plage (ex. 50) par série ; il consomme localement ; au-delà, numéro **provisoire** `P-<poste>-<n>` avec marqueur `provisoire: true` ; à la reconnexion le serveur attribue le définitif et enregistre la correspondance.
- Pièges : **RG-01** — un code attribué ne se modifie pas : le provisoire n'est pas un code patient, c'est un repère ; les pièces imprimées portent « provisoire » (impression : `print.js`) ; série annuelle qui repart à 1 (réservation par année).
- Vérification : **banc de l'invariant à deux postes, serveur coupé** : deux sessions créent chacune 30 dossiers hors ligne → au rétablissement, 0 doublon de `CNT/n/AA`, tous les provisoires régularisés, la correspondance existe.
- Peut être livrée seule : oui, par série (patient d'abord).

### Étape S2.3 — Invariant de stock au rejeu
- Fichiers : `api/crud.php` ou module serveur dédié, `parcours.js` (`PR.delivrer`, `PR.alerterStock`), `modules/m6-stock.js`.
- Ce qu'on fait : une sortie est validée **à l'arrivée** contre le stock du hub ; si elle le rendrait négatif → conflit nommé (tâche au gestionnaire de stock, ordonnance en cause), pas d'écriture.
- Pièges : **RG-03** ; ne pas dupliquer la règle (PHP + JS) — soit appeler le moteur existant, soit la déclarer une fois et la faire vérifier par un vecteur de test partagé ; le justificatif (n° d'ordonnance) reste obligatoire.
- Vérification : **banc à deux postes, hub coupé** : deux sorties du dernier lot → le second est en conflit, stock = 0, jamais < 0 ; `npm run test` vert.
- Peut être livrée seule : après S1.2.

---

## Phase S3 — Contrat d'opérations et banc de synchronisation (étape de décision)

### Étape S3.1 — Spécifier le contrat
- Fichiers : `packages/sync/` (schéma JSON des opérations, des réponses `push`/`pull`, des conflits), `docs/specs/SPEC-sync-contrat.md` (`/spec`), `docs/architecture/DICTIONNAIRE-DONNEES.md` (colonne « famille de fusion »).
- Ce qu'on fait : figer l'enveloppe d'opération (UUID v7, HLC, appareil, auteur, type, charge par champ, version de schéma), les réponses (accepté/fusionné/refusé + cause), la table collection → famille A/B/C/D, **avec les vecteurs de test JSON** (entrée → état attendu) qui serviront aux trois implémentations (prototype, hub, poste).
- Pièges : une collection sans famille est refusée à la génération (`gen-schema-pg.js` à étendre) ; nulls non écrits ; version de schéma portée par l'opération.
- Vérification : un script `node` rejoue les vecteurs contre une implémentation de référence en JS (le prototype) → tous passent.
- Peut être livrée seule : oui.

### Étape S3.2 — Banc de synchronisation (P1 de l'architecture cible)
- Fichiers : `infra/` (script de banc), `docs/plans/TESTS-synchronisation.md` (`/test-plan`), moteur(s) candidat(s) isolés dans `packages/sync/candidats/`.
- Ce qu'on fait : deux postes (SQLite) + un hub (PostgreSQL), trois collections représentatives (une par famille A, B, D), sur le matériel de la clinique : (1) hub arrêté puis rétabli, (2) conflit d'invariant, (3) redémarrage brutal en écriture, (4) 15 postes + 5 mobiles en charge, (5) restauration à blanc. Comparer PowerSync / ElectricSQL / moteur maison **sur ce banc**, pas sur la brochure.
- Pièges : les critères 1, 2, 6 d'ADR-0003 sont éliminatoires ; mesurer, pas supposer ; le banc tourne sur Windows **et** Linux.
- Vérification : rapport chiffré (opérations perdues, doublons, délai p95) → **ADR-0004** (moteur) et **acceptation ou refus d'ADR-0003** par la Direction.
- Peut être livrée seule : oui. **C'est la porte de sortie du plan.**

---

## Phase S4 — Hub et poste de bureau (après acceptation)

### Étape S4.1 — Hub : `push`/`pull`, séquence, droits
- Fichiers : `apps/hub/`, `packages/rbac/`, `packages/schema/postgres/`.
- Ce qu'on fait : implémenter le contrat de S3.1 ; matrice RBAC portée au hub (RG-13) ; journal `operations` append-only ; enrôlement/révocation d'appareils.
- Pièges : une règle un exemplaire — `packages/domaine` partagé ; ne pas ouvrir le hub à Internet.
- Vérification : vecteurs de S3.1 + audit RBAC rejoué au niveau du hub (un caissier ne reçoit aucune fiche d'analyse).

### Étape S4.2 — Poste : base locale, file, application locale d'abord
- Fichiers : `apps/poste/`, `infra/poste/`.
- Ce qu'on fait : SQLite chiffré, journal local, rejeu idempotent, pastille, numéros provisoires ; **tranche verticale caisse + MECeF + impression d'abord** (risque dominant).
- Pièges : le boîtier MECeF est branché à la **caisse**, pas au hub ; numéro fiscal toujours issu du boîtier ; file MECeF distincte du journal d'opérations.
- Vérification : critères 1–4 et 6–7 du banc d'ADR-0003 sur la tranche portée ; les scénarios du prototype correspondants portés en tests d'intégration.

---

## Phase S5 — Mobile, fichiers, réplica, client web de secours

### Étape S5.1 — Application mobile
- Fichiers : `apps/poste/` (même code adaptatif) ou `apps/mobile/` selon ADR-0004.
- Ce qu'on fait : sous-ensemble de collections par rôle (réponse à Q2), aucune émission fiscale.
- Vérification : mêmes vecteurs ; instantané filtré par rôle (aucune donnée hors périmètre sur l'appareil).

### Étape S5.2 — Fichiers (GED, scans) par empreinte
- Fichiers : `apps/hub/`, `packages/sync/`.
- Ce qu'on fait : métadonnées d'abord, binaire ensuite avec reprise ; SHA-256 ; une version par modification.
- Vérification : fichier modifié des deux côtés → deux versions conservées, un conflit nommé.

### Étape S5.3 — Réplica hors site
- Fichiers : `infra/hub/`.
- Ce qu'on fait : copie chiffrée de la sauvegarde par un outil de fichiers (rclone ou Syncthing), **jamais sur le chemin d'un geste** ; restauration à blanc trimestrielle (`api/restaurer.php` en est la version prototype).
- Vérification : restauration depuis le réplica → parité 0 écart.

### Étape S5.4 — Client web de secours (si Q7 = oui)
- Fichiers : le client du prototype, file IndexedDB (S0.1) branchée sur le contrat.
- Vérification : mêmes vecteurs ; lecture + saisies courtes seulement.

### Dernière étape — Documentation
- `CLAUDE.md` (vague correspondante, état des bancs), `docs/README.md`, `docs/architecture/README.md` (ADR-0004), ce plan mis à jour, `RELEASE-<version>.md` (`/release`).

---

## Schéma et données

- Prototype : champ `_v` sur les fiches ; collections `conflits` (+ éventuellement `appareils`) ; tables techniques `gestes_traites`, `plages_numeros`. **`VERSION` incrémentée une seule fois par phase** (constante unique de `store.js`), après **mesure du magasin** : référence 4 786 Ko pour ~330 Ko de marge (vague 64) — toute collection ajoutée se mesure avant d'être semée.
- Cible : `operations`, `appareils`, `plages_numeros`, `conflits`, `curseurs` (PRD §8) ; famille de fusion par collection dans le dictionnaire.

## Synchronisation (ce que ce plan introduit)

Opérations : `creer`, `modifier` (par champ), `archiver`, `restaurer`, `decider_conflit`, `reserver_plage`. Familles : A fiche, B journal, C pièce immuable, D agrégat — table complète à produire en S3.1. Invariants vérifiés au hub : RG-01 (code), RG-03 (stock), RG-10 (écriture équilibrée), lit = une admission active, exercice clos en lecture seule. Chaque étape touchant un invariant porte son **banc à deux postes, hub coupé**.

## Hors périmètre de ce plan

- Tout accès depuis Internet (Q1 du PRD) : ADR distincte.
- Le portage des 305 écrans vers Flutter (ADR-0003 : tranches verticales, plan séparé par tranche).
- La synchronisation des données métier par un outil de fichiers (exclu par principe).
- Les SMS/courriels sortants.

## Risques

| Risque | Signal précoce | Parade |
|---|---|---|
| S1.4 casse le vidage/semis qui s'appuient sur la collection entière | scénarios 67/72/73 rouges | faire S1.4 en dernier, garder le chemin pour semis/reset/import |
| La file persistée sature le stockage navigateur | alerte de quota, file plafonnée | IndexedDB, plafond visible, test de saturation |
| Faux conflits (champ recalculé par un écran à chaque ouverture) | tâches de conflit sans cause humaine | exclure les champs dérivés de la comparaison ; sonde « aucun conflit sur lecture seule » |
| Le moteur candidat ne tient pas l'invariant de stock | banc 2 rouge | moteur maison ou repli hub .NET (ADR-0003), domaine protégé par vecteurs partagés |
| Dérive d'horloge d'un poste | ordre d'application incohérent | ordre par séquence du hub + HLC ; alerte > 2 min |
| Dispersion de la règle (PHP + JS + Dart) | trois exemplaires qui divergent | un seul exemplaire + vecteurs de tests partagés |
| La Direction demande l'accès Internet en cours de route | Q1 rouverte | ADR dédiée avant tout code ; ne pas exposer le hub |

## Définition de « fini »

`npm run lint`, `build`, `check` (0 erreur JS, 0 lien cassé), `test` (scénarios + ceux ajoutés), `audit-rbac` (0 promesse) verts ; parité PostgreSQL à 0 écart ; banc à deux postes hub coupé vert pour chaque invariant touché ; `VERSION` incrémentée une fois ; `CLAUDE.md` et `docs/` mis à jour ; scénario ajouté par étape.
