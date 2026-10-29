# apps/mobile — application Flutter mobile (version minimale)

Deux profils sur la même application (spec §11) :

| Profil | Contenu |
|---|---|
| **Soignant** | agenda du jour, dossier en lecture, constantes, notes, prescription selon droits, **consultation à domicile** |
| **Réception de secours** | module Réception seulement, utilisable quand les postes fileuls sont hors service ; ni caisse, ni comptabilité, ni stock |

**Jamais sur le réseau local** : le mobile échange **uniquement par le relais** (`apps/web`), en enveloppes
**chiffrées de bout en bout** (clé de clinique), avec un lot préparé par la mère (tournée du jour), base chiffrée,
PIN/biométrie, expiration du lot. Android d'abord.

**État : squelette non compilé** (pas de SDK Flutter ici). Premier geste :
`flutter create --platforms=android .` en conservant `pubspec.yaml` et `lib/`, puis `flutter pub get`.

Référence du protocole : `packages/sync/banc/` (scénarios mobile : `packages/sync/banc/README.md`).
