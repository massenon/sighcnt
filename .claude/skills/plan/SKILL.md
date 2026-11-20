---
name: plan
description: Produire un plan d'implémentation découpé en étapes vérifiables pour SIGH-CNT à partir d'un PRD, d'une ADR ou d'une spec — fichiers touchés, ordre, dépendances, commandes de vérification, incrément de schéma. Utiliser quand on demande « un plan », « comment on s'y prend », « découper le travail », ou avant d'ouvrir un chantier de plus d'une demi-journée.
---

# /plan — plan d'implémentation

Produit : `docs/plans/PLAN-<sujet>.md`. Entrée : un PRD, une ADR ou une spec (les citer).

## Démarche

1. **Relire la doctrine** (`CLAUDE.md`) : les pièges connus deviennent des étapes explicites
   (safelist avant CSS, `VERSION` unique, `var` avant `return`, `K.commande` pour toute écriture,
   une fabrique unique par règle, un référentiel semé au bon endroit).
2. **Inventorier l'existant** avant d'écrire : `grep` des fabriques, des collections et des
   scénarios touchés. Ce qui existe se réutilise, ne se recopie pas.
3. **Découper en étapes de moins d'une demi-journée**, chacune laissant le dépôt vert.
4. **Nommer la vérification de chaque étape** : commande, scénario, mesure (ko du magasin,
   nombre de sondages RBAC, 0 erreur JS, 0 lien cassé).
5. **Isoler ce qui dépend d'un arbitrage** et le mettre en dernier, derrière une question posée.

## Gabarit

```markdown
# PLAN — <sujet>
Source : PRD/ADR/SPEC … · Estimation : … · Branche : …

## Résultat attendu
Trois lignes : ce que l'utilisateur pourra faire, ce qui sera prouvé par un scénario.

## Étapes
### Étape 1 — <verbe + objet>
- Fichiers : …
- Ce qu'on fait : …
- Pièges à éviter : …
- Vérification : `commande` → résultat attendu
- Peut être livrée seule : oui / non

### Étape 2 — …

## Schéma et données
Incrément de VERSION ? Migration ? Collection semée où ? Taille estimée (le quota du poste se mesure).

## Synchronisation
Nouvelles opérations du journal, famille de fusion, invariants à vérifier au hub.

## Hors périmètre de ce plan
Ce qu'on a vu et qu'on ne fait pas, avec le ticket ou la question qui le porte.

## Risques
Tableau risque → signal précoce → parade.

## Définition de « fini »
lint + build + check + test + audit-rbac verts ; CLAUDE.md / docs mis à jour ; scénario ajouté.
```

## Règles

- Un plan ne contient pas de code : il nomme les fichiers et les fonctions, le code vient après.
- Un plan qui touche un invariant (RG-03, RG-10, numérotation) contient une étape « banc d'essai
  de l'invariant à deux postes, hub coupé ».
- La dernière étape est toujours la documentation (`CLAUDE.md`, tableau des écrans par vague).
