# Guide : cloner la branche et tout lancer en local (maquette, relais web, poste)

Branche de travail : `claude/sighcnt-monorepo-offline-first-i0v3v9`. Dépôt privé : être connecté à GitHub avec un accès au dépôt.
Commandes pour Linux/macOS ; sous Windows (PowerShell), remplacer `cp` par `Copy-Item` et `export X=Y` par `$env:X='Y'`.

## 0. Prérequis

| Outil | Version | Pour |
|---|---|---|
| Git, Node.js | Node ≥ 22 | clone, outillage, maquette |
| PHP | ≥ 8.2 avec `pdo_pgsql` | maquette et relais web |
| PostgreSQL | 14+ (16 conseillé) | maquette (`sigh_prototype`) et relais (`sigh_relais`) |
| Composer | 2.x | relais web |
| Flutter | 3.47 (Dart 3.13), bureau Windows ou Linux activé | poste, mobile, domaine |
| Chrome ou Chromium | récent | bancs d'essai (`CHROME_PATH`) |

## 1. Cloner la branche

```bash
git clone --branch claude/sighcnt-monorepo-offline-first-i0v3v9 https://github.com/massenon/sighcnt.git
cd sighcnt
npm install
npm run prototype:install
```

## 2. Maquette (PHP + PostgreSQL), pour voir et tester le logiciel

```bash
service postgresql start                      # Linux ; sous Windows démarrer le service PostgreSQL
psql -U postgres -c "CREATE DATABASE sigh_prototype;"
cp prototype_html/api/config.local.exemple.php prototype_html/api/config.local.php
# éditer prototype_html/api/config.local.php : dsn, utilisateur, mot de passe (fichier jamais commité)
npm run prototype:serveur                     # http://127.0.0.1:8080/index.php
```

Comptes de démonstration : identifiants de la table `utilisateurs` (par exemple `c.bassongui`), mot de passe d'origine `demonstration`, à changer à la première connexion.
Vérifier : `cd prototype_html && npm run lint && npm run check && npm run test`.

## 3. Relais web (Laravel 12, `apps/web`)

```bash
psql -U postgres -c "CREATE USER sigh_relais WITH PASSWORD 'choisir-un-mot-de-passe';"
psql -U postgres -c "CREATE DATABASE sigh_relais OWNER sigh_relais;"
cd apps/web
composer install
cp .env.example .env
# éditer .env : DB_PASSWORD, RELAIS_SECRET_MERE (texte long et aléatoire)
php artisan key:generate
php artisan migrate
php artisan relais:superadmin votre@courriel.bj --mot-de-passe='douze-caracteres-minimum'
php artisan serve                             # http://127.0.0.1:8000, panneau superadmin
php artisan test                              # SQLite en mémoire, aucune base requise
```

## 4. Poste Flutter (`apps/poste`)

```bash
cd packages/domaine && dart pub get && dart analyze && dart test && cd ../..
cd apps/poste
flutter config --enable-linux-desktop         # ou --enable-windows-desktop
flutter pub get
flutter analyze && flutter test
flutter run -d linux                          # ou -d windows
```

- Premier démarrage sans compte : l'assistant de première installation (premier administrateur, code de secours à 25 caractères).
- Poste **mère** : « Activer la mère » demande l'adresse du relais (`http://127.0.0.1:8000` en local), le secret de la mère (= `RELAIS_SECRET_MERE` du `.env`) et la clé de clinique (16 caractères minimum, à ranger sur papier).
- Poste **fileul** : « Rejoindre une clinique » depuis l'assistant.
- En développement, `SIGH_CHIFFREMENT=non` désactive le chiffrement du magasin du poste.
- Installateur Windows : `apps/poste/build_windows.bat` (voir `apps/poste/installer/`).

## 5. Mobile (`apps/mobile`)

```bash
cd apps/mobile && flutter pub get && flutter analyze && flutter test && flutter run
```

Le mobile passe uniquement par le relais.

## 6. Banc d'essai isolé (à connaître avant de lancer deux bancs)

Le serveur PHP d'un banc écoute sur `SIGH_PORT_PHP`, pas sur `SIGH_PORT_TEST` ; la base se choisit par `SIGH_BASE_TEST`. Pour un passage isolé :

```bash
cd prototype_html
SIGH_PORT_PHP=8931 SIGH_BASE_TEST=sigh_banc_a SIGH_PORT_TEST=8932 CHROME_PATH=/usr/bin/chromium \
  node build/test-fonctionnel.js --seul=...
```

Ne jamais lancer deux bancs avec les valeurs par défaut en même temps.

## 7. Dossier de spécimens d'impression

`npm run prototype:presentation` (ou `npm run presentation` dans `prototype_html/`) régénère `presentation/` ; ouvrir `presentation/index.html`.
