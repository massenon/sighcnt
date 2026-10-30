---
name: sigh-sync
description: Protocole de synchronisation SIGH-CNT (poste mère, fileuls, mobiles, relais chiffré) — règles, banc d'essai à plusieurs processus, comment ajouter un scénario. Utiliser pour toute modification de packages/sync, packages/sync_dart ou des routes /sync, /depot, /releve.
---

# SIGH-CNT — synchronisation

Spécification : `docs/specs/SPEC-protocole-synchronisation.md`. Référence exécutable : `packages/sync/banc/`. Charger `sigh-maitre` d'abord.

## Principes (ne se négocient pas)

1. **Le poste est autonome** : il écrit d'abord chez lui (file persistée) ; la synchronisation est un arrière-plan.
2. **Le journal d'opérations fait foi**, ordonné par le `seq` de la **mère** — jamais par une horloge de poste.
3. **On reçoit avant d'envoyer** ; un lot est **idempotent** (clé = id d'opération) ; l'appareil marque « envoyée » **après l'accusé**.
4. **Quatre familles + référentiel** (A fiche, B journal, C pièce émise, D invariant, R référentiel) déclarées par collection ; une collection sans famille est refusée.
5. **Aucune suppression** : `archiver` / `restaurer`. **Époque** : un envoi d'une époque inconnue est refusé (409) **côté mère**, que l'appareil ait tiré ou non.
6. **Le relais est opaque** : enveloppes AES-256-GCM, AAD = `id|appareil|dir|n` ; rangs **contigus** par (appareil, sens) ; un trou ou une altération **bloque** l'appareil et alerte — jamais d'application silencieuse.
7. **Le mobile ne parle qu'au relais** ; la mère **relève** (le relais ne l'appelle jamais).

## Le banc

```bash
cd packages/sync
npm run banc            # tout en Node (référence) : 26 scénarios, 127 vérifications
npm run banc:cible      # mère + postes + mobile en Dart, relais Laravel : mêmes 26 scénarios
node --no-warnings banc/run.js R4 R13     # quelques scénarios
SIGH_MERE=dart node …   # mélanger les implémentations (mère Dart, postes Node…)
```
Pré-requis du mode Dart : `packages/sync_dart/construire.sh` ; du mode Laravel : `composer install` dans `apps/web`.

## Ajouter un scénario

1. Le décrire dans la spec (§16, `SYNC-Rn`) : état initial, geste, résultat attendu.
2. L'écrire dans `banc/run.js` (`scenarios.Rn`) : attendre une **condition** (`attendre`), jamais une pause fixe ; chercher une ligne par sa **référence**, jamais par son rang ; chaque `verifier` dit ce qu'il mesure.
3. **Le faire échouer exprès** : retirer le garde-fou testé dans la mère (mutation) et vérifier que le scénario rougit. Un test qui ne peut pas échouer ne protège rien — c'est arrivé deux fois (opacité du relais passée sur du base64 ; portée du mobile sur des données antérieures à l'appairage).
4. Le rejouer sur **les trois** implémentations avant de conclure.

## Pièges

Une opération acceptée doit rester visible à l'écran jusqu'à son retour dans le flux (`enVol`) · `pkill` sans crochet tue son shell · les enfants hérités de `stderr` gardent un tube ouvert (rediriger la sortie du banc vers un fichier) · `dart compile exe` refuse les hooks SQLite (`construire.sh`).
