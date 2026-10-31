---
name: release
description: Préparer une livraison de SIGH-CNT (version du poste, du hub ou du prototype) avec sa liste de contrôle — vérifications, incrément et migration de schéma, compatibilité poste/hub, installeur, sauvegarde préalable, procédure de retour arrière et notes de version en français. Utiliser quand on demande « livrer », « release », « déployer sur les postes », « mettre à jour le hub ».
---

# /release — liste de contrôle de livraison

Produit : `docs/plans/RELEASE-<version>.md` + notes de version. Rien ne se déploie sans elle.

## Avant

- [ ] `npm run prototype:verify` (maquette) et `npm run lint && npm run test` (espaces de travail) verts ; chiffres cités.
- [ ] `audit-rbac` : 0 promesse ; `inventaire-rbac` relu si une fiche RBAC ou un écran a changé.
- [ ] `VERSION` : incrémentée si la forme des données a changé, UNE seule constante ; migration
      numérotée dans `packages/schema`, rejouable, testée sur une base copiée de la production.
- [ ] **Compatibilité poste/hub** : le hub accepte en lecture un poste de la version précédente ;
      un poste en retard de schéma n'écrit pas (il le dit) tant qu'il n'est pas mis à jour.
- [ ] Sauvegarde du hub prise et **restaurée une fois** sur une base jetable (une sauvegarde non
      restaurée n'existe pas).
- [ ] Secrets : aucun dans le dépôt ni dans l'installeur ; `config.local` recopié depuis l'exemple.
- [ ] Notes de version en français : ce qui change pour CHAQUE poste (accueil, caisse, labo…),
      avec le geste nouveau et la capture d'écran si l'écran change.

## Déploiement

1. Hub d'abord (schéma rétro-compatible), puis les postes, un service à la fois — commencer par le
   poste le moins critique, finir par la caisse.
2. Fenêtre : hors heures de garde et jamais pendant une clôture comptable ou une paie.
3. Vérifier sur chaque poste : connexion, hydratation, un geste de son parcours, une impression.

## Retour arrière

- Binaire précédent conservé sur le hub ; migration descendante écrite ou, à défaut, restauration
  de la sauvegarde + rejeu du journal d'opérations depuis l'heure du déploiement.
- Critère de retour arrière écrit AVANT (ex. : « une file de synchronisation en erreur sur un poste »).

## Après

- [ ] Journal des versions : hub et postes affichent la même ; l'écart se voit dans `m14`.
- [ ] Mise à jour de `CLAUDE.md` (vague, écrans, pièges) et des ADR concernées.
- [ ] Rétrospective en cinq lignes : ce qui a surpris, ce qu'on change pour la prochaine.
