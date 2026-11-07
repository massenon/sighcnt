---
name: adr
description: Rédiger une décision d'architecture (ADR) numérotée pour SIGH-CNT — contexte, options, décision, conséquences — ou mettre à jour le statut d'une ADR existante. Utiliser quand une question structurante se pose (stockage, synchronisation, sécurité, pile technique, découpage) ou quand on demande « ADR », « décision d'architecture », « pourquoi a-t-on choisi ».
---

# /adr — décision d'architecture

Produit : `docs/architecture/adr/ADR-NNNN-<sujet>.md`, numéro = dernier + 1 (`ls docs/architecture/adr`).
Mettre à jour l'index `docs/architecture/README.md`.

## Gabarit

```markdown
# ADR-NNNN — <titre : la décision en une phrase>
Statut : proposé | accepté le <date> par <qui> | remplacé par ADR-NNNN | abandonné
Date : <aaaa-mm-jj>
Concerne : <poste | hub | synchronisation | schéma | sécurité | …>

## Contexte
Le problème, les contraintes qui pèsent (coupures, LAN seul, 30 agents, RG-xx, hors périmètre CDCT,
existant à reprendre), et ce qui se passe si l'on ne décide pas.

## Options examinées
Pour chacune : description en trois lignes, avantages, inconvénients, coût d'exploitation pour une
clinique sans informaticien à demeure. Au moins deux options, dont « ne rien changer ».

## Décision
Ce qu'on fait, écrit au présent. Ce qu'on ne fait PAS, et pourquoi.

## Conséquences
- Positives.
- Négatives, et ce qui les compense.
- Ce que cela impose aux autres composants (schéma, RBAC, impression, bancs d'essai).

## Comment on vérifiera que c'était la bonne décision
Un banc d'essai, une mesure, une date de revue.
```

## Règles

- Une ADR **n'est jamais réécrite** après acceptation : on en écrit une nouvelle qui la remplace
  (même doctrine que les pièces émises).
- Les arbitrages de la Direction consignés dans `CLAUDE.md` sont des ADR de fait : les citer, ne
  pas les reformuler.
- Une option écartée l'est avec sa raison écrite — c'est elle qui évite de rouvrir le débat.
- Pas de dépendance à un service en ligne pour l'usage courant (CDCT §4.3) : toute option qui
  en suppose un le dit en première ligne de ses inconvénients.
