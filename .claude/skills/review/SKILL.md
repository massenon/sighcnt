---
name: review
description: Revoir une modification de SIGH-CNT (diff, branche ou fichiers) contre les règles de gestion RG-01→14, la doctrine du prototype et les pièges connus, avant commit ou fusion. Utiliser quand on demande « relis », « revue », « c'est bon pour commit ? », ou après tout chantier touchant les droits, le schéma, la synchronisation ou une pièce imprimée.
---

# /review — revue contre la doctrine du projet

Entrée : `git diff`, une branche ou une liste de fichiers. Sortie : constats classés
**bloquant / à corriger / remarque**, chacun avec fichier:ligne et la règle enfreinte.

## Liste de contrôle

### Règles de gestion
- RG-01 : aucun code patient construit à la main ; `C.codePatient()` (ou son équivalent) seul.
- RG-02 : aucune remise ni marge sur un médicament.
- RG-03 : toute sortie de stock porte un justificatif ; stock jamais négatif ; refus NOMMÉ.
- RG-09 : la validité de carte se lit À LA DATE, via la couverture datée.
- RG-10 : équilibre contrôlé AVANT écriture ; une pièce = toutes ses lignes plates ; naît en brouillon.
- RG-12 : aucune écriture anonyme ; une entrée d'audit et une seule par geste.
- RG-13 : les commandes d'écriture passent par `K.commande` / `K.droits()` sans argument ; le
  contrôle est refait au moteur (un champ désactivé ne protège rien).
- RG-14 : aucune suppression physique ; archivage ; une pièce émise ne se réécrit pas (avoir, rectification).

### Doctrine du prototype
- Une règle vit à UN endroit (fabrique unique) ; un référentiel semé au bon niveau (socle / écran).
- `VERSION` incrémentée si la forme des données change ; la semence garde son marquage.
- « Une restriction s'annonce » : tout filtre, verrou ou lecture seule dit qui, quoi, pourquoi, où.
- Aucune valeur inventée : tarif, seuil, numéro, objectif → marqué provisoire ou à valider.
- Total d'un état = `somme` sur la colonne, jamais fourni ; on ne totalise que ce qui a un sens.
- `U.texteEnrichi` pour tout HTML venant d'une saisie (échapper D'ABORD).
- Pas de `&amp;` écrit à la main ; typographie française dans les chaînes ; apostrophe dans un
  commentaire = safelist cassée.
- `var` déclaré AVANT le premier rendu qui le lit ; pas de deux clés `actions` dans un même littéral.
- `String.replace` scripté sur une ancre UNIQUE.

### Hors ligne et synchronisation
- L'opération est idempotente (identifiant d'opération), horodatée par HLC, attribuée (poste,
  utilisateur, session).
- Famille de fusion déclarée ; invariant vérifié au hub ; conflit rendu visible, jamais résolu en silence.
- Aucun appel réseau bloquant sur le chemin d'un geste de guichet.

### Secrets et sécurité
- Aucun identifiant, mot de passe, jeton, DSN en clair dans le diff (`git diff | grep -iE "pass|secret|jeton"`).
- Aucune donnée médicale dans un message d'alerte, un son, une adresse ou un QR.

### Vérification
- `lint`, `build`, `check`, `test`, `audit-rbac` lancés ; résultats cités dans la revue.
- Scénario ajouté pour tout nouveau geste ; `CLAUDE.md` mis à jour pour toute leçon nouvelle.

## Forme de la réponse

1. Verdict en une ligne (prêt / pas prêt).
2. Bloquants, puis corrections, puis remarques — chacun : `fichier:ligne`, règle, correction proposée.
3. Ce qui n'a pas pu être vérifié (et pourquoi).
