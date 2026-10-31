---
name: sigh-flutter
description: Conventions du code Flutter/Dart de SIGH-CNT (apps/poste, apps/mobile, packages/domaine, packages/sync_dart) — structure, thème tiré des jetons, base locale, tests, commandes. Utiliser pour toute modification d'un fichier .dart ou d'un pubspec.yaml.
---

# SIGH-CNT — Flutter / Dart

Charger d'abord `sigh-maitre`.

## Structure

| Dossier | Rôle | Dépendances permises |
|---|---|---|
| `packages/domaine` | Règles pures (Dart sans Flutter) : formats, secteurs, périodes, contrat d'opération, jetons | aucune (que `test`) |
| `packages/sync_dart` | Moteur de synchronisation : `Mere` (service), `Fileul`, `Mobile`, `Pont` (relais chiffré) | `sigh_domaine`, `sqlite3`, `cryptography`, `crypto` |
| `apps/poste` | Application desktop : modes `fileul` et `mere` (`--dart-define=SIGH_MODE=mere`) | `sigh_domaine`, `http` ; le moteur s'y branche par une source d'état (`SourceEtatSync`) |
| `apps/mobile` | Application minimale : profils *soignant* et *réception de secours*, **par le relais seul** | idem |

Une interface **n'importe jamais** le moteur directement : elle écoute une valeur (`ValueListenable<EtatSync>`) ou appelle un client injectable (`ClientMere`) — c'est ce qui rend les écrans testables sans réseau.

## Règles

- **Thème** : `ThemeSigh` (apps/poste/lib/core/theme.dart) lit `JetonsSigh` (engendré). **Aucune couleur en dur** ailleurs ; texte jamais sous 11 pt.
- **Formats français** : `money`, `nombre`, `pourcent`, dates — dans `packages/domaine` (U+202F entre milliers, U+00A0 avant la devise et avant « % »). Ne jamais réécrire un format dans un écran.
- **Texte d'écran en français**, libellés repris de la maquette (`docs/guides/GLOSSAIRE.md`).
- **Un geste d'écriture = une opération** (`Operation`) : jamais de `DELETE`, jamais d'écriture directe dans une table de confirmation côté poste.
- **Pas de client d'API écrit à la main** pour un contrat qui existe ailleurs (voir `sigh-sync`).
- **Droits** : lire `packages/rbac/data/rbac.json` ; une commande interdite est absente.
- **Accessibilité** : `Semantics` sur tout état porteur de sens (la pastille de synchronisation le fait).

## Commandes

```bash
# SDK : Dart 3.13 / Flutter 3.47 (storage.googleapis.com/flutter_infra_release) — poser Flutter dans le PATH
cd packages/domaine && dart pub get && dart analyze && dart test        # 14 tests, 323 vecteurs
cd apps/poste       && flutter pub get && flutter analyze && flutter test   # 11 tests
cd apps/mobile      && flutter pub get && flutter analyze && flutter test
cd packages/sync_dart && dart analyze && ./construire.sh                # exécutables natifs (dart build cli : SQLite embarqué)
```

`dart compile exe` **ne marche pas** pour `sync_dart` (hooks natifs de `sqlite3`) : utiliser `construire.sh`.

## Limites connues (à ne pas masquer)

Squelettes `windows/` `linux/` `android/` générés par `flutter create` mais **jamais compilés ici** (pas de chaîne native) · SQLCipher non branché (SQLite en clair dans le banc) · aucune tranche métier portée (voir `PARITE-MAQUETTE.md`).
