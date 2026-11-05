# ADR-0006 : Échanges entre pairs par le relais, la mère n'étant plus un passage obligé

Statut : **accepté le 05/11/2026** par la Direction. Il **modifie** la règle de topologie de `docs/specs/SPEC-protocole-synchronisation.md` §1 (« Aucune autorité n'existe en dehors de la mère ») et l'ordre de référence `seq` de la mère (EF-SYNC-20) ; il ne remplace pas l'ADR-0001 (local-first) ni le relais opaque.
Sources : demande de la Direction du 05/11/2026 (les fileuls envoient et reçoivent automatiquement, indépendants de la mère ; réponses D1 à D3) ; `docs/prd/PRD-RELAIS-copie-consultable.md` ; `packages/sync_dart/lib/src/*.dart` ; `apps/poste/lib/sync/pont_activite.dart`.

## Contexte

Aujourd'hui tout passe par la mère : elle attribue le `seq` (seule référence d'ordre), accepte, fusionne ou refuse chaque opération, et les fileuls ne relèvent que son flux. Si la mère est éteinte, les fileuls travaillent seuls (plages de numéros, part de stock) mais **ne se voient pas** : leurs opérations attendent son retour. La Direction veut que les fileuls échangent entre eux par le relais pendant ce temps, et que les validations suivent les rôles du RBAC, où que ces rôles soient connectés.

## Décision proposée

1. **Journal par appareil au relais.** Chaque appareil publie ses opérations comme enveloppes chiffrées (AES-256-GCM, clé de clinique, aad = `id|appareil|dir|n`) dans **son propre journal** à rang contigu par appareil, et relève ceux des autres. Le relais reste opaque et sans règle métier.
2. **Ordre sans la mère.** L'ordre de fusion devient l'**horloge logique hybride** (`hlc`, déjà portée par chaque opération) départagée par l'identifiant d'appareil : **un ordre total, identique sur tous les appareils**. Le `seq` de la mère reste l'ordre **faisant foi** une fois la mère revenue ; entre-temps il est remplacé par l'ordre HLC. La dérive d'horloge est bornée et signalée (au-delà de 2 min, l'appareil est mis en alerte, EF-SYNC-20 conservé).
3. **Règle de fusion par famille, au domaine.** Chaque famille d'opérations (factures, avoirs, écritures, stock, lots, mouvements, admissions) a une **règle pure** dans `packages/domaine` dont le résultat dépend seulement de l'ensemble des opérations reçues, pas de leur ordre d'arrivée : compteurs par variations, numéros jamais réécrits mais marqués en doublon, lits en conflit marqués, stock par part, plages de numéros allouées. Deux appareils qui ont reçu les mêmes opérations aboutissent au même état (convergence). Le relais n'en contient aucune.
4. **RBAC à l'émission et à la réception.** Tout appareil refuse d'appliquer l'opération d'un pair si la matrice des droits n'autorise pas son auteur (rôle lu dans l'opération authentifiée). La validation d'un flux de travail (ex. approvisionnement) est une opération du rôle habilité, sur le poste où il est connecté ; elle repart par le même chemin vers le demandeur.
5. **Provisoire jusqu'au retour de la mère.** Ce qui est appliqué sans la mère est marqué provisoire. Au retour, la mère relève tous les journaux, rejoue, tranche les conflits marqués et publie le résultat faisant foi (nouveau `seq`). Les pièces certifiées (MECeF) et les écritures comptables définitives ne sont jamais décidées par un pair non habilité.
6. **Conflit non tranché.** Il reste marqué et visible ; à la connexion de la personne habilitée, notification sonore et fenêtre modale des choses à faire (moteur de notifications existant, source `sync_a_arbitrer`).
7. **Copie consultable.** Tout appareil peut publier des lots de copie (PRD relais consultable) ; le web reconstitue chaque enregistrement par identifiant et version.

## Options écartées

- **Garder la mère comme seule autorité** : ne répond pas à la demande d'indépendance des fileuls.
- **CRDT généralisé** : trop large pour une clinique ; les règles par famille suffisent car les familles sont connues et peu nombreuses.
- **Un vote entre pairs pour trancher** : complexe et opaque pour les utilisateurs ; le marquage visible puis l'arbitrage par la personne habilitée suffit (D2).

## Conséquences

- **Le banc d'abord.** `packages/sync/banc` reste l'exécutable de référence du protocole : le mode pair y est écrit et prouvé en premier (convergence de trois fileuls avec la mère éteinte, puis retour de la mère), puis porté en Dart.
- **Spec à amender** : topologie (§1), ordre (§5), accusés, retour de la mère, révocation d'un appareil, époque.
- **Risques** : divergence silencieuse si une règle n'est pas commutative (d'où le test de convergence par permutation d'ordre pour chaque famille) ; double publication des mêmes opérations (idempotence par `id` d'opération) ; croissance des journaux au relais (compaction par instantané annoncé par la mère).
- **Non vérifiable ici** : comportement réel sur l'hébergement cPanel et sur plusieurs machines physiques.

## Plan

1. **Banc** : journal par appareil au relais, relève croisée, HLC, règle de fusion de deux familles pilotes (stock et admissions), test de convergence par permutation, scénario « mère éteinte puis de retour ».
2. **Domaine Dart** : règles par famille avec vecteurs tirés du banc.
3. **Poste** : branchement du moteur pair, notification sonore et modale « à traiter », réglages.
4. **Relais** : sens `copie` et sens `pair`, mesure d'opacité étendue, page de consultation.
