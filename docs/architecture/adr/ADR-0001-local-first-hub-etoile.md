# ADR-0001 — Postes autonomes hors ligne, hub de clinique en étoile, synchronisation par journal d'opérations
Statut : **proposé** (17/10/2026) — à accepter par la Direction
Date : 2026-10-17
Concerne : poste, hub, synchronisation

## Contexte

La clinique (~30 agents, ~15 postes, un bâtiment) subit des coupures d'électricité et d'Internet.
Le CDCT exclut une architecture Web/API ou cloud pour l'usage courant (§4.3) et impose RG-01→14
(unicité des codes, stock jamais négatif, écritures équilibrées, journalisation, suppression
logique). La maquette actuelle (`prototype_html/`) tient ses données dans un magasin JSON servi
par PHP + PostgreSQL : son protocole remplace une **collection entière** à chaque envoi, donc deux
postes qui écrivent la même collection s'effacent mutuellement. `sigh_web` (Laravel + Inertia/Vue)
exige le serveur à chaque navigation. Ne pas décider, c'est livrer un logiciel qui s'arrête avec
le serveur.

## Options examinées

1. **Ne rien changer** (magasin JSON par collection, serveur PHP) — simple, déjà là ; perte de
   données certaine à plusieurs postes ; aucun RBAC serveur.
2. **Laravel/Inertia sur le hub, postes navigateurs** — réutilise `sigh_web` ; aucun travail hors
   ligne ; hub coupé = clinique arrêtée.
3. **PostgreSQL par poste + réplication** — multi-maître non natif, invariants inapplicables, un
   serveur à exploiter par PC.
4. **Local-first : SQLite chiffré par poste, hub PostgreSQL autorité, journal d'opérations
   synchronisé en étoile, conflits rendus visibles** — travail garanti sans réseau ; invariants
   tenus par une autorité unique ; journal RG-12 natif ; demande un moteur de synchronisation
   (existant ou maison) et un banc d'essai sérieux.
5. **CRDT / maillage sans hub** — pas d'autorité : un CRDT accepte un stock négatif.

## Décision

Option 4. Chaque poste porte l'application et sa base ; le hub ordonne et vérifie ; on synchronise
des **gestes** (opérations idempotentes, UUID v7, horloge logique hybride, séquence posée par le
hub), pas des états ; quatre familles de fusion (fiche descriptive, journal append-only, pièce
émise immuable, agrégat à invariant) ; numérotation par tranches avec numéro provisoire ; un seul
poste écrivain par magasin ; MECeF en file sortante ; l'interface et les moteurs du prototype sont
repris, le contrat de lecture synchrone du store est conservé.

On ne fait **pas** : de maillage poste à poste, de dépendance Internet sur le chemin d'un geste,
de fusion silencieuse, de réécriture de l'interface.

Le choix du moteur (PowerSync, ElectricSQL ou maison) est **différé à ADR-0003**, après le banc
d'essai de P1 (deux postes, hub coupé puis rétabli, trois collections).

## Conséquences

- Positives : la clinique travaille sans hub et sans Internet ; audit complet gratuit ; RBAC
  appliqué au hub ; sauvegarde répartie (les journaux des postes permettent de reconstruire le hub).
- Négatives : un moteur de synchronisation à prouver ; des numéros non chronologiques entre
  postes ; une file « à régulariser » à traiter par les postes responsables ; du matériel (hub
  + onduleur). Compensations : banc d'essai avant tout écran, numéros provisoires annoncés, tâches
  nommées, hub réinstallable depuis `infra/hub`.
- Impose : `VERSION` unique dans `packages/schema` ; `packages/rbac` et `packages/domaine`
  exécutés au poste **et** au hub ; chaque spec (`/spec` §6) déclare la famille de fusion de
  chaque écriture ; chaque plan touchant un invariant porte un banc à deux postes.

## Comment on vérifiera

Banc de P1 (`/test-plan`, « banc de synchronisation ») : 0 opération perdue, convergence des deux
postes, conflits d'invariant visibles comme tâches, numéro provisoire régularisé, poste réinstallé
ré-hydraté à l'identique. Revue de la décision à la fin du pilote (P5).
