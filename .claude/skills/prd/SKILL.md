---
name: prd
description: Rédiger ou réviser un PRD (document d'exigences produit) pour un module ou une fonctionnalité de SIGH-CNT à partir des documents de cadrage, du CDCT et du prototype. Utiliser quand on demande « un PRD », « cadrer », « les exigences de », ou avant tout plan d'implémentation d'une fonctionnalité nouvelle.
---

# /prd — document d'exigences produit

Produit : `docs/prd/PRD-<module>-<sujet>.md` (ex. `PRD-M8-facture-avoir.md`), en français.

## Avant d'écrire

1. Lire dans `CLAUDE.md` la section du module concerné et les **arbitrages de la Direction** : un
   PRD ne rouvre pas un arbitrage rendu, il le cite.
2. Ouvrir le module du prototype (`prototype_html/assets/js/modules/<module>.js`) et son entrée
   dans `nav.js` : ce qui existe déjà s'inventorie, il ne se redécrit pas.
3. Chercher dans `docs/cadrage/` (CDCT, rapport de cadrage, notes de service, formulaires
   scannés) la **source documentaire** de chaque exigence. Une exigence sans source se dit
   « proposition à valider », jamais « exigence ».
4. Lister les règles de gestion touchées (RG-01 → RG-14) et les rôles concernés (16 rôles).

## Gabarit

```markdown
# PRD — <module> : <sujet>
Statut : brouillon | en revue | arrêté le <date> par <qui>
Sources : <documents de cadrage cités, avec page ou section>

## 1. Problème
Ce que le poste ne peut pas faire aujourd'hui, avec le geste réel au guichet / au labo / à la caisse.

## 2. Objectifs et non-objectifs
- Objectifs mesurables (un critère de recette chacun).
- Non-objectifs explicites (hors périmètre CDCT §4.3 : portail patient, télémédecine, cloud d'usage courant…).

## 3. Utilisateurs et rôles
Tableau rôle → ce qu'il voit / ce qu'il fait / ce qu'il ne doit PAS voir (RG-13).

## 4. Parcours
Les étapes de bout en bout, poste par poste, avec ce qui naît à chaque étape (tâche, pièce, écriture).

## 5. Exigences fonctionnelles
EF-<module>-NN, chacune : énoncé, source, règle(s) RG, critère d'acceptation vérifiable.

## 6. Données
Collections / champs touchés, nouvelles collections (→ incrément de VERSION), ce qui est référentiel
administrable vs donnée opérationnelle vs règle configurée.

## 7. Hors ligne et synchronisation (OBLIGATOIRE)
Pour chaque donnée écrite : sa famille de fusion (fiche descriptive, journal append-only, pièce
émise immuable, agrégat à invariant) ; ce qui se passe si deux postes agissent sans hub ; ce que
l'écran dit quand une opération est « en suspens » ou « à régulariser ».

## 8. Impression et états
Pièces produites, gabarit (A4 / 80 mm / CR80), mentions obligatoires, totaux calculés.

## 9. Ce qui n'est pas documenté
Les valeurs d'attente, tarifs provisoires, référentiels à faire valider par un professionnel nommé.

## 10. Questions ouvertes pour la Direction
Une ligne par arbitrage attendu, avec l'option recommandée.
```

## Règles

- **Rien d'inventé** : pas de tarif, pas de numéro, pas de seuil sans document ; les valeurs
  d'attente sont marquées comme telles (doctrine `tarifProvisoire`).
- Un critère d'acceptation doit pouvoir devenir une **sonde de scénario** (`/test-plan`).
- Une restriction s'annonce : chaque exigence de RBAC dit ce que l'écran affiche au rôle exclu.
- Terminer par la liste des arbitrages ouverts, jamais par une décision prise à la place de la Direction.
