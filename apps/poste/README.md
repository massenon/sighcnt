# apps/poste — application Flutter desktop (poste fileul **et** poste mère)

> **Remplace** l'ancienne coque Tauri (ADR-0003, ADR-0005). Windows par défaut, Linux pris en charge.

Un seul code, deux modes (`--dart-define=SIGH_MODE=fileul|mere`) :

| Mode | Contenu |
|---|---|
| **fileul** | tous les modules autorisés au rôle ; SQLite chiffré (SQLCipher) ; file d'envoi ; synchronisation avec la mère (P1) |
| **mère** | le **service** (serveur HTTP local + PostgreSQL + moteur de synchronisation + pont vers le relais, P2) et la **console** (DAF/admin : appareils, jetons, conflits, supervision, sauvegardes) |

Le service de la mère tourne **sans session ouverte** (service Windows / `systemd`) ; la console s'y connecte.

**État : squelette non compilé** — aucun SDK Flutter dans l'environnement de rédaction. Premier geste :
`flutter create --platforms=windows,linux .` dans ce dossier **en conservant** `pubspec.yaml` et `lib/`, puis
`flutter pub get` pour figer les versions.

Spécifications : `docs/specs/SPEC-protocole-synchronisation.md` · exécutable de référence du protocole :
`packages/sync/banc/` · règles : `packages/domaine/` · maquette (recette) : `prototype_html/`.
