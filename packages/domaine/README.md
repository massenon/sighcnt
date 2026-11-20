# packages/domaine — règles de gestion et moteurs (Dart)

Paquet **Dart pur** (sans Flutter, sans entrée-sortie), exécuté par le poste fileul, le mobile **et** le poste mère : un seul exemplaire des règles RG-01→14 (ADR-0003, ADR-0005 rév. 3). *Remplace l'ancien plan en TypeScript.*

Contenu à venir par tranches : parcours transactionnel (`prescrire`, `encaisser`, `delivrer`), prise en charge (`repartir`), avoirs, BFR, paie et primes datées, validations labo. Pour l'instant : le **contrat de synchronisation** (`Operation`, `Famille`, `CodeSync`), miroir de `packages/sync/banc/`.

Chaque règle porte des **vecteurs** (`test/vecteurs/`) exportés de la maquette : sans vecteur, pas de règle. `dart test` dans ce dossier (squelette non compilé ici, pas de SDK Dart).
