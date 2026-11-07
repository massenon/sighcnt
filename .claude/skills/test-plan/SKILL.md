---
name: test-plan
description: Définir la stratégie de vérification d'un chantier SIGH-CNT — scénarios de bout en bout, audit RBAC par profil, bancs d'essai de coupure et de synchronisation à deux postes, sondes d'invariants. Utiliser quand on demande « comment on teste », « plan de tests », « stratégie de vérification », ou quand un plan touche un invariant ou la synchronisation.
---

# /test-plan — stratégie de vérification

Produit : `docs/plans/TESTS-<sujet>.md`. Entrée : une spec ou un plan.

## Les cinq niveaux

| Niveau | Outil | Prouve |
|---|---|---|
| Statique | `npm run lint` (node --check), typage TS dans `packages/*` | que ça se charge |
| Chargement | `npm run check` | 0 erreur JS, 0 lien cassé, 0 ressource manquante sur toutes les pages |
| Parcours | `npm run test` (scénarios Puppeteer) | que le geste produit l'effet, AU GESTE (clic, changement de rôle) |
| Droits | `npm run audit-rbac`, `npm run inventaire-rbac` | 0 promesse, 0 commande cachée, par écran × profil |
| Synchronisation | banc à DEUX postes + hub (à construire dans `packages/sync`) | invariants sous coupure, convergence, aucun geste perdu |

## Comment écrire une sonde (leçons payées, à relire)

- **Sonder le geste, pas l'affichage** : un onglet non ouvert n'est pas testé ; `check` ne clique pas.
- **Lire une colonne par son NOM**, jamais par son rang.
- **Un scénario qui change de rôle le RESTAURE** ; un scénario qui vide ou mute une collection ou
  une fiche RBAC la **restaure** (sauvegarde en `sessionStorage`, `window` est balayé à la navigation).
- **Ne jamais recopier le manifeste** dans une assertion : dériver le compte de `N.tree()`.
- **Comparer les chiffres seuls** : `C.money` compose en espaces insécables.
- **Une sonde écrite sur une lecture fausse verrouille l'erreur** : vérifier la position ou la
  valeur, pas « l'absence » déduite d'une interprétation.
- `page.evaluate` gardé (document complet, socle chargé) ; chaque échec nommé sur-le-champ.
- **Mesurer** ce qui se mesure : taille du magasin en ko, nombre de sondages, nombre de pièces.

## Banc de synchronisation (obligatoire dès qu'un plan touche RG-03, RG-10, la numérotation ou une pièce émise)

1. Deux postes A et B hydratés, hub en marche : A écrit, B voit après synchronisation.
2. Hub coupé : A et B écrivent chacun ; A et B continuent de fonctionner (0 erreur, impression possible).
3. Hub rétabli : les deux journaux arrivent ; vérifier :
   - aucune opération perdue (compte des opérations = somme des deux journaux) ;
   - fiche descriptive modifiée des deux côtés → fusion par champ, les deux versions au journal ;
   - journal append-only (mouvements, constantes) → les deux lignes présentes ;
   - pièce émise des deux côtés → deux pièces, deux numéros, jamais une qui écrase l'autre ;
   - invariant violé (stock, RG-10) → opération « en suspens / à régulariser », **tâche nommée**,
     rien d'appliqué en silence ;
   - tranche de numéros épuisée hors ligne → numéro provisoire, régularisé, pièce réimprimable.
4. Poste réinstallé à vide → ré-hydratation complète depuis le hub, même état que son voisin.

## Gabarit

```markdown
# TESTS — <sujet>
Spec / plan : …

## Ce qu'on doit prouver
Liste des assertions (depuis la spec §8), chacune avec son niveau.

## Scénarios de parcours
Scénario NN — <titre> : rôle, pré-conditions, gestes, assertions, restauration.

## Audit des droits
Rôles concernés, écrans, commandes attendues présentes / absentes.

## Banc de synchronisation
Les étapes ci-dessus instanciées sur les collections du chantier.

## Attendu avant livraison
lint 0 · check 0/0 · test N/N (M vérifications) · audit-rbac 0 promesse · banc sync vert.
```
