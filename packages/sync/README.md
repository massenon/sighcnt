# packages/sync — journal d'opérations et synchronisation
Opération (UUID v7, poste, utilisateur, session, HLC, séquence du hub, type, charge avant/après, dépendances), file de sortie, protocole push/pull/SSE, familles de fusion, tranches de numéros. Premier chantier : le banc à deux postes (ADR-0003).

**Banc de référence** : `banc/` (voir `banc/README.md`) — une mère et des fileuls en vrais processus, réseau coupé en cours de route, 15 scénarios, 72 vérifications. `npm run banc` depuis ce dossier.
