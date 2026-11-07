---
name: sigh-maitre
description: Instructions maîtres du projet SIGH-CNT — à charger AVANT tout travail sur la cible (Flutter, Laravel, synchronisation) ou sur un portage depuis la maquette. Méthode, règles de qualité, ce qui ne se devine jamais. Utiliser dès qu'une tâche touche apps/, packages/ ou docs/architecture/.
---

# SIGH-CNT — instructions maîtres

Le projet remplace un parc cloisonné par un logiciel de gestion de clinique. La **maquette** (`prototype_html/`) est l'exécutable de référence ; la **cible** (`apps/poste`, `apps/mobile`, `apps/web`, `packages/*`) la porte. Ces instructions tiennent en une idée : **on extrait, on ne devine pas.**

## Les cinq règles

1. **Une source, jamais deux.** Droits → `packages/rbac/data/rbac.json`. Navigation → `packages/referentiels/data/manifeste.json`. Couleurs → `docs/design/design-tokens.json` (et `packages/domaine/lib/src/design/jetons.dart`). Règles chiffrées → vecteurs `packages/domaine/test/vecteurs/*.json`. Ces fichiers sont **engendrés** par `prototype_html/build/*.js` (`npm run prototype:referentiels` à la racine) : on régénère, on n'édite pas.
2. **Une règle sans vecteur n'est pas portée.** Porter une règle = l'écrire en Dart dans `packages/domaine`, exporter ses vecteurs depuis la maquette (`build/vecteurs.js`), faire passer `dart test`. Le premier port a déjà attrapé un défaut (espace insécable avant « % »).
3. **Aucune règle en double.** Les règles vivent en Dart (`packages/domaine`) et s'exécutent au poste, au mobile **et** à la mère. Le relais Laravel n'en contient **aucune**.
4. **Un refus se nomme.** Toute opération refusée porte un `code`, un `motif` lisible et un `geste` de correction ; une commande interdite est **absente**, pas grisée ; « non calculable » n'est pas zéro ; un tiret n'est ni zéro ni exclusion.
5. **Ce qui n'a pas de source se dit.** Valeur, libellé ou règle sans document : marquer « proposition à valider » et le dire à l'écran. Ne jamais inventer un tarif, un numéro d'urgence, une borne de laboratoire.

## Invariants (CLAUDE.md, RG-01→14)

RG-01 code patient `CNT/n/AA` jamais modifié · RG-02 médicaments au prix d'achat · RG-03 stock jamais négatif · RG-09 couverture valide **à la date** · RG-10 écriture équilibrée · RG-12 aucune action anonyme · RG-13 cloisonnement · **RG-14 aucune suppression physique** (« supprimer » = archiver, annulable). Une pièce émise ne se réécrit jamais ; une donnée de référence qui change se **versionne par date**.

## Avant de dire « c'est fait »

- Lancer ce qui prouve : `dart test` (domaine), `flutter analyze && flutter test` (apps), `php artisan test` (relais), `npm run banc:cible` à la racine (protocole de bout en bout), `node --test` dans `packages/rbac`.
- Dire ce qui n'est **pas** vérifié (PostgreSQL pour la mère, SQLCipher, service Windows, charge, revue de sécurité). Un rapport qui ne nomme pas ses limites est faux.
- Ne jamais committer : `.env`, `vendor/`, `node_modules/`, `*.sqlite`, exports `*.sql`, mots de passe.

## Pièges déjà payés

`pkill -f "motif"` tue son propre shell si le motif figure dans la commande (utiliser `[x]motif`, dans une commande à part) · un test qui recopie le manifeste finit par diverger de lui (le dériver) · une sonde écrite sur une lecture fausse verrouille l'erreur · un test d'opacité qui cherche du texte clair passe sur du base64 (décoder et mesurer l'entropie) · un test de « portée » doit créer ses données **après** l'appairage.

## Où lire ensuite

`CLAUDE.md` (doctrine de la maquette) · `docs/architecture/adr/ADR-0005-*` (architecture cible) · `docs/specs/SPEC-protocole-synchronisation.md` · `docs/architecture/PARITE-MAQUETTE.md` (ce qui reste à porter) · `docs/guides/BIBLIOTHEQUE-DOCUMENTAIRE.md`.
