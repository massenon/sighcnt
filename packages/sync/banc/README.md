# Banc de synchronisation à plusieurs processus

Éprouve **le protocole** de `docs/specs/SPEC-protocole-synchronisation.md` avec une **mère** et des **fileuls** qui sont de vrais processus, chacun sur sa base, reliés par un **commutateur TCP** qui coupe le réseau en cours de route.

```bash
cd packages/sync
npm run banc              # tout (≈ 20 s) — Node ≥ 22.13, aucune dépendance à installer
node --no-warnings banc/run.js R3 R4     # seulement ces scénarios
```

## Ce que le banc fait

| Élément | Rôle |
|---|---|
| `mere.js` | Poste mère de **référence** : appairage, journal d'opérations à `seq` sans trou, quatre familles de fusion, conflits nommés, bail de stock, plages de numéros, époque, réinitialisation encadrée, console d'administration (HTTP) |
| `fileul.js` | Poste fileul de **référence** : base locale, file persistée, curseur, « on reçoit avant d'envoyer », suspension à la révocation, export avant purge d'époque |
| `proxy.js` | Commutateur : `ouvert` · `ferme` (câble arraché) · `perd_reponse` (le lot est traité mais la réponse n'arrive jamais) |
| `run.js` | Orchestrateur : lance, tue (SIGKILL) et relance les processus ; 15 scénarios, 72 vérifications |

## Scénarios (référence : spec §16)

R1 mère arrêtée, deux dossiers · R1b plage épuisée, numéro provisoire · R2 réponse perdue, rejeu sans doublon · R3 dernier lot sans bail · R3b dernier lot avec bail · R4 conflit nommé et décision · R5 champs différents · R7 révocation hors ligne · R8 réinitialisation en production (fenêtre, second profil, sauvegarde, époque, export) · R12 horloge décalée · R14 « renvoyer vers tous » · R18 appairage (usage unique, expiration, renouvellement rejoué) · R19 file persistante après SIGKILL · R20 archivage, pièce émise, journal, référentiel · R21 un dossier qu'on vient de créer ne disparaît pas de l'écran.

## Ce que ce banc PROUVE

- l'idempotence du rejeu, l'ordre par la séquence de la mère (jamais par l'horloge), les conflits nommés, l'absence de stock négatif avec et sans bail, l'absence de suppression physique, la réinitialisation qui ne ressuscite rien, la persistance de la file à l'arrêt brutal ;
- que le banc **détecte** les défauts : on a retiré tour à tour l'idempotence, le contrôle de stock, la détection de conflit, la garde de suppression, le contrôle d'époque à l'envoi et le maintien d'un dossier accepté à l'écran — chaque retrait fait échouer le ou les scénarios concernés.

## Ce que le banc a déjà trouvé (et corrigé)

1. **Un dossier créé disparaissait de l'écran** entre l'accusé de la mère et le tirage suivant (la file l'oubliait avant que le flux ne le rende). Corrigé dans `fileul.js` (`enVol()`), verrouillé par R21.
2. **Le contrôle d'époque à l'envoi n'était testé par rien** : le poste de référence tire avant d'envoyer, donc le tirage le protégeait et masquait l'absence de garde côté mère. Un test d'envoi direct d'une ancienne époque a été ajouté (R8).
3. Plusieurs courses **dans les tests eux-mêmes** (lire avant convergence) : corrigées en attendant la convergence, jamais en allongeant une pause.

## Ce qu'il NE prouve PAS (à faire avant d'accepter ADR-0005)

| Non couvert | Pourquoi ça compte |
|---|---|
| **Dart / Flutter** | le banc est en Node : il valide la **conception**, pas le code Dart ; le même banc doit ensuite piloter le vrai service Dart (mêmes routes, mêmes scénarios) |
| **PostgreSQL** | la mère de référence utilise SQLite ; la tenue des transactions et des verrous sous PostgreSQL reste à mesurer |
| **SQLCipher, service Windows/Linux, onduleur, coupure de courant réelle** | critères 6 et 7 du banc d'ADR-0003 |
| **Le relais en ligne et le chiffrement de bout en bout** (P2/P3, mobile, boîte aux lettres) | scénarios R6, R8, R10, R13, R15 de la spec : prochain banc |
| **Charge** | 15 postes + mobiles, 20 000 lignes : aucune mesure ici |
| **Dépendance entre opérations** | une opération refusée ne bloque pas encore celles qui en dépendent sur la même fiche (spec §5.6) |
| **Fusion de deux mères / bascule d'autorité** | non écrite |

Un résultat vert ici **ne dit pas** que le produit est prêt : il dit que le protocole décrit tient sur ce qu'on lui a demandé.
