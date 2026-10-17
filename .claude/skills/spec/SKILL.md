---
name: spec
description: Écrire la spécification technique et fonctionnelle d'un écran ou d'un module de SIGH-CNT — données, règles, droits par rôle, comportement hors ligne, impression, sondes — à partir d'un PRD ou du prototype. Utiliser quand on demande « la spec de », « spécifier l'écran », ou avant de porter un écran du prototype vers l'application de poste.
---

# /spec — spécification d'écran ou de module

Produit : `docs/specs/SPEC-<id-écran>.md` (ex. `SPEC-m8-caisse.md`) ou `SPEC-<module>.md`.

## Avant d'écrire

1. Lire l'écran dans le prototype : sa déclaration `SIGH.screen(...)`, son entrée `nav.js`
   (module, rôles, `servant`, `universel`, `secondaire`, alias), ses collections.
2. Lire la fiche RBAC du rôle dans le magasin (`rbac`) : ce que l'écran accorde ou retire.
3. Relever les scénarios du banc d'essai qui le sondent (`build/test-fonctionnel.js`).

## Gabarit

```markdown
# SPEC — <id-écran> : <titre>
PRD : docs/prd/… · Module : Mx · Domaine du ruban : … · Statut : …

## 1. Rôle de l'écran
Une phrase : ce qu'on y fait, et ce qu'on n'y fait PAS (renvoi vers l'écran qui le fait).

## 2. Droits
| Rôle | voir | éditer | annuler | Ce que l'écran affiche au rôle restreint |
Un écran l'emporte sur son module ; une surcharge accorde autant qu'elle restreint.

## 3. Données
Collections lues / écrites ; champs avec type, obligatoire, source documentaire ; identifiant
(UUID v7) et numéro métier (série, format, règle hors ligne) ; archivage (RG-14).

## 4. Règles
RG-xx appliquées, contrôles AVANT écriture (refus nommé : le message dit quoi et où corriger),
calculs (jamais de total fourni : `somme` par colonne).

## 5. Parcours et événements
Ce que l'écran émet (tâche de file, écriture comptable, notification de poste) et ce qu'il consomme.

## 6. Hors ligne et synchronisation
Famille de fusion de chaque écriture ; comportement si le hub est absent ; affichage des
opérations « en suspens / à régulariser » ; ce qui exige une tranche de numéros.

## 7. Impression
Pièce, gabarit, en-tête légal unique, filtres portés sur l'état, totaux.

## 8. Sondes
Liste des assertions qu'un scénario de bout en bout doit prouver (au geste, pas à la lecture).

## 9. Ce qui reste à valider
Par qui (Direction / professionnel nommé), quoi, et comment l'écran le dit en attendant.
```

## Règles

- Un référentiel lu par plusieurs modules se décrit comme **semé au socle** ; lu par un seul, par
  son écran. Se tromper donne une liste vide ailleurs (piège documenté).
- Toute nouvelle collection ou tout nouveau champ = incrément de `VERSION` : l'écrire dans la spec.
- Les libellés sont ceux des documents et des professionnels (« Amnios », « G/l ») : la spec ne
  « corrige » pas un vocabulaire métier, elle le signale.
