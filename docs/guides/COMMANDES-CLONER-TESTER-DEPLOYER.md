# Commandes : cloner, installer, tester, mettre en production

Public : l'administrateur et le développeur de la clinique. Toutes les commandes se copient telles quelles. Chacune a été relue dans le dépôt (`package.json`, scripts, README, guides). Ce qui n'a pas pu être vérifié est dit dans l'encadré « Non vérifié » de chaque section et récapitulé en section 6.

Légende : ℹ️ information, ⚠️ attention, 🛑 alerte (perte de données ou geste irréversible), ✅ astuce.

Les commandes sont écrites pour Linux et macOS. Sous Windows (PowerShell), remplacez `cp` par `Copy-Item` et `export X=Y` par `$env:X='Y'`. Les bancs et la maquette se lancent de préférence sous Linux.

Guides détaillés du dépôt : `docs/guides/LANCER-EN-LOCAL.md`, `GUIDE-LANCEMENT-LOCAL.md`, `GUIDE-DEMARRAGE.md`, `DEPLOIEMENT-CPANEL.md`, et la doctrine dans `CLAUDE.md`.

---

## 1. Cloner

Guide détaillé : `docs/guides/LANCER-EN-LOCAL.md` §1, `GUIDE-DEMARRAGE.md` §2.

```bash
git clone https://github.com/massenon/sighcnt.git
cd sighcnt
git branch -r                                   # liste les branches distantes
git switch claude/sighcnt-monorepo-offline-first-i0v3v9   # la branche de travail poussée
```

Pour cloner directement une branche :

```bash
git clone --branch claude/sighcnt-monorepo-offline-first-i0v3v9 https://github.com/massenon/sighcnt.git
```

Pour récupérer la suite du travail :

```bash
git fetch origin
git pull --ff-only origin claude/sighcnt-monorepo-offline-first-i0v3v9
```

ℹ️ Le dépôt est privé : connectez-vous à GitHub avec un compte qui y a accès (jeton d'accès personnel ou `gh auth login`).

⚠️ Ce qui n'est JAMAIS versionné (voir `.gitignore`) : `node_modules/`, `vendor/`, `.env` et `.env.*` (sauf `.env.example`), `*.local.php` (sauf `*.local.exemple.php`), `prototype_html/api/config.local.php`, `prototype_html/api/fichiers/` (scans de dossiers patient), les exports `*.sql`, `*.dump`, `*.sqlite`, `*.db`, `.dart_tool/`, `apps/poste/build/`. Après un clone, rien de tout cela n'existe : vous le créez en section 2.

🛑 Ne lancez jamais `git clean -fd` sans `-n` d'abord (simulation), et ne faites jamais `git pull` sur un poste en service sans sauvegarde (voir section 5.5).

✅ Les branches de lots s'appellent `claude/sighcnt-lot-<nom>`. Un lot se relit avec `git log --oneline origin/<branche>`.

---

## 2. Installer en local, composant par composant

Guides détaillés : `LANCER-EN-LOCAL.md` §0 à §5, `GUIDE-LANCEMENT-LOCAL.md` §0 à §4, `GUIDE-DEMARRAGE.md` §1 à §4, `apps/web/README.md`.

### 2.1 Prérequis

| Outil | Version | Sert à |
|---|---|---|
| Git | récent | cloner |
| Node.js | 22 ou plus (`engines` de `package.json`) | outillage, maquette, bancs |
| PHP | 8.2 ou plus, extensions `pdo_pgsql`, `mbstring`, `openssl`, `ctype`, `json` | maquette, relais (`composer.json` du relais exige `^8.2`) |
| Composer | 2.x | relais Laravel |
| PostgreSQL | 14 ou plus, 16 conseillé | maquette (`sigh_prototype`), relais (`sigh_relais`) |
| Flutter | 3.47 (Dart 3.13), bureau Linux ou Windows activé | poste, mobile, domaine, moteur |
| Chrome ou Chromium | récent | `check`, `test`, `audit-rbac` pilotent un vrai navigateur |

Vérifier ce qui est installé :

```bash
node -v && npm -v && php -v && php -m | grep pdo_pgsql && composer --version && psql --version
flutter --version && dart --version
```

### 2.2 Script d'installation de l'environnement (poste de développement Linux)

Un script idempotent a servi à rebâtir l'environnement du conteneur de développement : SDK Flutter 3.47.9 dans `/tmp/flutter-dl/flutter`, `pub get` des quatre projets Dart, `npm ci` de la maquette, `composer install` du relais, `.env` du relais, rôle et base PostgreSQL locaux, `config.local.php`. Il est hors du dépôt (dans le dossier de travail de la session) et peut avoir disparu. Pour le refaire à la main, suivez les sections 2.3 à 2.8. L'essentiel :

```bash
export PATH=/tmp/flutter-dl/flutter/bin:$PATH
curl -sSfL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz -o /tmp/flutter.tar.xz
mkdir -p /tmp/flutter-dl && tar -xJf /tmp/flutter.tar.xz -C /tmp/flutter-dl
git config --global --add safe.directory /tmp/flutter-dl/flutter
flutter config --no-analytics
flutter config --enable-linux-desktop            # ou --enable-windows-desktop sous Windows
(cd packages/domaine  && dart pub get)
(cd packages/sync_dart && dart pub get)
(cd apps/poste   && flutter pub get)
(cd apps/mobile  && flutter pub get)
(cd prototype_html && npm ci --no-audit --no-fund)
(cd apps/web && composer install --no-interaction --no-progress)
mkdir -p apps/web/tests/Unit                     # sinon `php artisan test` s'arrête net (dossier vide non suivi par git)
```

⚠️ `composer install` du relais dure environ 11 minutes la première fois.

ℹ️ Le SDK Flutter se réinstalle aussi selon `.claude/skills/sigh-flutter/SKILL.md`.

⚠️ `node_modules` installé sous un autre système d'exploitation n'est pas portable : supprimez-le puis refaites `npm ci`. Si `npx tailwindcss` échoue, compilez la CSS ainsi :

```bash
cd prototype_html
node node_modules/tailwindcss/lib/cli.js -i src/input.css -o assets/css/tailwind.css --minify
```

### 2.3 Dépendances Node de la racine

```bash
npm install                       # monorepo (workspaces)
npm run prototype:install         # dépendances de la maquette (Tailwind, Puppeteer)
```

ℹ️ La racine et `packages/rbac`, `packages/sync` n'ont aucune dépendance à installer. `npm ci` dans `prototype_html` est équivalent à `prototype:install` et suit exactement `package-lock.json`.

### 2.4 La maquette (`prototype_html`, PHP + PostgreSQL)

Guide détaillé : `GUIDE-DEMARRAGE.md` §3 et §4.

```bash
service postgresql start                          # Linux ; sous Windows, démarrer le service PostgreSQL
psql -U postgres -c "CREATE DATABASE sigh_prototype;"
cp prototype_html/api/config.local.exemple.php prototype_html/api/config.local.php
# éditer prototype_html/api/config.local.php : dsn, user, pass (fichier ignoré par git)
npm run prototype:serveur                         # http://127.0.0.1:8080/index.php
```

Depuis `prototype_html/`, la même chose s'écrit `npm run serveur`, avec un autre port possible : `node build/serveur.js 9000`.

- Le schéma se crée seul au premier appel, et le premier accès sème le jeu de démonstration.
- Comptes de démonstration : identifiants de la table `utilisateurs` (par exemple `c.bassongui`), mot de passe d'origine `demonstration`, changement exigé à la première connexion.
- Régénérer les pages, la safelist et la CSS : `cd prototype_html && npm run build`.

🛑 La base de la maquette est `sigh_prototype`. Elle ne porte que de la démonstration. N'y mettez jamais de données réelles, et la maquette n'écrit jamais dans `sigh_cnt`.

⚠️ Le mot de passe PostgreSQL commis le 17/10/2026 dans le premier commit est à changer sur chaque poste (il reste lisible dans l'historique).

ℹ️ Pour le planificateur de la maquette (sauvegardes, contrôle des fichiers) : `sh api/planificateur/installer-linux.sh`, ou sous Windows `.\api\planificateur\installer-windows.ps1 -Racine <dossier> -Php <php.exe>` (PowerShell administrateur). Essai à blanc : `php api/cron.php --force`.

ℹ️ Passerelle SMS de la maquette (optionnelle) : `cd prototype_html/api && composer install`, et `sms.local.exemple.php` comme modèle.

### 2.5 Le poste Flutter (`apps/poste`)

Guide détaillé : `LANCER-EN-LOCAL.md` §4, `GUIDE-LANCEMENT-LOCAL.md` §2, `GUIDE-DEMARRAGE.md` §8 bis, `apps/poste/README.md`.

```bash
export PATH=/tmp/flutter-dl/flutter/bin:$PATH     # si Flutter est posé à cet endroit
cd apps/poste
flutter config --enable-linux-desktop             # ou --enable-windows-desktop
flutter pub get
flutter run -d linux                              # ou : flutter run -d windows
```

Mode (défaut `fileul`) et réglages de développement, passés par `--dart-define` :

```bash
flutter run -d linux --dart-define=SIGH_MODE=mere
flutter run -d linux --dart-define=SIGH_MODE=fileul
flutter run -d linux --dart-define=SIGH_CHIFFREMENT=non          # développement : magasin non chiffré
flutter run -d linux --dart-define=SIGH_DONNEES=donnees-fileul2  # un second poste sur la même machine, dossier de données séparé
```

Au premier démarrage sans compte, l'assistant s'ouvre :

1. Poste mère : créer le premier administrateur (mot de passe de 8 caractères au moins) et noter le **code de secours**, affiché une seule fois. Puis « Configurations à faire », « Activer la mère » : adresse du relais (`127.0.0.1:8000` en local, `sighcnt.nassieratoo.com` en production : le poste ajoute `https://`), secret de la mère (le même texte que `RELAIS_SECRET_MERE` du relais) et clé de clinique (16 caractères au moins).
2. Poste fileul : « Rejoindre une clinique », adresse de la mère (`http://hôte:9000`, la mère écoute par défaut sur `http://127.0.0.1:9000`) et code d'appairage émis par la console de la mère (8 caractères, valable 15 minutes, usage unique).

🛑 La clé de clinique et le code de secours se rangent sur papier, sous scellé, chez la Direction. Sans la clé, aucune copie de sauvegarde n'est lisible. Sans le fichier `cle-poste.bin` du poste, les données du poste sont illisibles.

ℹ️ Pas de Visual Studio nécessaire pour Linux. Pour Windows : Visual Studio 2022, charge de travail « Développement Desktop en C++ ».

### 2.6 L'application mobile (`apps/mobile`)

Guide détaillé : `LANCER-EN-LOCAL.md` §5, `GUIDE-LANCEMENT-LOCAL.md` §4.

```bash
cd apps/mobile
flutter pub get
flutter devices                                   # liste les appareils et émulateurs
flutter run -d <identifiant-appareil> --dart-define=SIGH_RELAIS=http://10.0.2.2:8000
```

ℹ️ Le mobile ne parle jamais au réseau local : il passe par le relais seul. `10.0.2.2` est l'adresse de l'ordinateur vue depuis l'émulateur Android. Sur un téléphone réel, donnez l'adresse du relais joignable depuis ce téléphone. Le relais et la mère activée doivent exister avant (sections 2.7 et 2.5). Sans `SIGH_RELAIS`, l'adresse par défaut est `https://relais.exemple.bj`.

### 2.7 Le relais Laravel (`apps/web`)

Guide détaillé : `LANCER-EN-LOCAL.md` §3, `GUIDE-LANCEMENT-LOCAL.md` §1, `apps/web/README.md`.

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
php artisan serve --host=127.0.0.1 --port=8000    # http://127.0.0.1:8000, panneau superadmin
```

Tâche planifiée en local (à laisser tourner dans un terminal, équivalent du cron de production) :

```bash
php artisan schedule:work
```

Commandes d'exploitation :

```bash
php artisan relais:statut                         # volumes (appareils, enveloppes, Ko, dernier battement), aucun contenu
php artisan relais:exporter                       # export de la base dans storage/app/exports
php artisan relais:purger                         # SIMULATION de la purge de l'audit
php artisan relais:purger --oui                   # applique (365 jours par défaut, 30 minimum)
php artisan relais:surveiller                     # marque le passage du cron et évalue les alertes
php artisan route:list
```

⚠️ Le guide `LANCER-EN-LOCAL.md` écrit 12 caractères au minimum pour le mot de passe superadmin, `DEPLOIEMENT-CPANEL.md` écrit 8. Le code de `CreerSuperadmin` indique « 8 caractères au moins ». Prenez 12 caractères ou plus.

✅ `php artisan test` (SQLite en mémoire) n'exige aucune base. Voir section 3.

### 2.8 Les paquets Dart (domaine, moteur de synchronisation)

Guide détaillé : `LANCER-EN-LOCAL.md` §4, `GUIDE-LANCEMENT-LOCAL.md` §3.

```bash
export PATH=/tmp/flutter-dl/flutter/bin:$PATH
cd packages/domaine    && dart pub get && dart analyze && dart test
cd ../sync_dart        && dart pub get && dart test
```

ℹ️ Mesure de l'assistant (lecture seule) : `cd packages/domaine && dart run tool/mesure_assistant.dart`.

> **Non vérifié ici** : ces commandes ont été relues, non exécutées dans cette session (Dart et Flutter ne sont pas installés dans l'environnement de rédaction). Le mot de passe superadmin, les ports et les chemins viennent des guides existants. `php artisan schedule:work` est une commande standard de Laravel 12, non essayée sur ce dépôt.

---

## 3. Tester

Guides détaillés : `GUIDE-DEMARRAGE.md` §5 et §9, `LANCER-EN-LOCAL.md` §6, `CLAUDE.md` (section Commandes), skill `.claude/skills/test-plan`.

### 3.1 Règles d'or avant tout banc

⚠️ **Jamais deux bancs à la fois** : ils se disputent les ports et les bases. Vérifiez qu'aucun serveur ne reste vivant : `ps aux | grep "[p]hp -S"`.

⚠️ **PostgreSQL doit tourner** avant tout banc de la maquette ou du relais : `service postgresql start` (il s'arrête à chaque redémarrage d'un conteneur).

⚠️ Les bancs travaillent sur une **base jetable** : son nom doit contenir `test`, `essai` ou `banc`, faute de quoi la remise à zéro est refusée. Par défaut `sigh_prototype_test`. La base de travail n'est jamais touchée.

⚠️ Ne modifiez pas `prototype_html/api/` pendant qu'un banc tourne : le serveur PHP relit les fichiers à chaque requête.

⚠️ Le serveur PHP d'un banc écoute sur `SIGH_PORT_PHP` (8099 par défaut), PAS sur `SIGH_PORT_TEST` (8096 par défaut, port du pilote du banc). La base se choisit par `SIGH_BASE_TEST`.

⚠️ `rapport-tests.json` et `rapport-controle.json` (dans `prototype_html/build/`) sont réécrits par chaque banc. Ne les commitez jamais. Restaurez-les :

```bash
git checkout -- prototype_html/build/rapport-tests.json prototype_html/build/rapport-controle.json
```

⚠️ Un port occupé (`EADDRINUSE`) vient presque toujours d'un banc précédent resté vivant : tuez son processus.

⚠️ Disque serré (environ 4 Go) : supprimez vos dossiers et bases temporaires après chaque banc (voir 3.6).

✅ Après un banc, relisez le nombre de scénarios et de vérifications MESURÉ dans le rapport. Les chiffres du CLAUDE.md sont des ordres de grandeur.

### 3.2 La maquette (depuis `prototype_html/`)

| Commande | Ce qu'elle prouve | Durée indicative |
|---|---|---|
| `npm run lint` | syntaxe des sources JS et gardes de doctrine (`garde-listes-prix`, `garde-roles-en-dur`, `garde-tableaux`) | quelques minutes |
| `npm run build` | pages, safelist Tailwind, CSS | quelques minutes |
| `npm run check` | 306 pages dans Chrome : 0 erreur JS, 0 lien cassé | longue |
| `npm test` | environ 175 scénarios de bout en bout | environ 60 minutes |
| `npm run audit-rbac` | chaque écran sous chaque profil : 0 promesse, 0 lecture non dite | longue |
| `npm run verify` | lint, build, check, test à la suite | plus de 60 minutes |

```bash
cd prototype_html
service postgresql start
npm run lint
npm run build
npm run check
npm run audit-rbac
```

Sous-ensemble de pages :

```bash
node build/check.js --pages=m6-,m8-
```

### 3.3 Un scénario ou un module seul (isolé)

Variables d'un passage isolé : `SIGH_PORT_PHP` et `SIGH_PORT_TEST` (deux ports libres), `SIGH_BASE_TEST` (une base à soi, au nom contenant `test`, `essai` ou `banc`), `CHROME_PATH`, `SIGH_FICHIERS_DIR` et `SIGH_SAUVEGARDES_DIR` (deux dossiers à soi).

```bash
cd prototype_html
service postgresql start
mkdir -p /tmp/banc-a/fichiers /tmp/banc-a/sauvegardes
SIGH_PORT_PHP=8931 SIGH_BASE_TEST=sigh_banc_a SIGH_PORT_TEST=8932 \
CHROME_PATH=/opt/pw-browsers/chromium \
SIGH_FICHIERS_DIR=/tmp/banc-a/fichiers SIGH_SAUVEGARDES_DIR=/tmp/banc-a/sauvegardes \
node build/test-fonctionnel.js --seul=<fragment>
```

`--seul=<fragment>[|<autre>…]` joue les scénarios dont le titre contient un des fragments, dans l'ordre du fichier. Un `_` vaut une espace : `--seul=Vague_79|Vague_80|Vague_81`.

⚠️ Une sonde isolée peut cacher une dépendance d'ordre : rejouez-la derrière des scénarios voisins. Une sonde se cherche par la référence d'une ligne, jamais par son rang. Un scénario qui vide une collection ou change de rôle la RESTAURE.

ℹ️ Sous Windows, `CHROME_PATH` peut rester vide : le banc cherche aussi `C:/Program Files/Google/Chrome/Application/chrome.exe`.

### 3.4 La suite complète de la maquette

Même environnement, sans `--seul`. Lancez-la en arrière-plan et attendez-la par une boucle :

```bash
cd prototype_html
mkdir -p /tmp/banc-a/fichiers /tmp/banc-a/sauvegardes
setsid nohup env SIGH_PORT_PHP=8931 SIGH_BASE_TEST=sigh_banc_a SIGH_PORT_TEST=8932 \
  CHROME_PATH=/opt/pw-browsers/chromium \
  SIGH_FICHIERS_DIR=/tmp/banc-a/fichiers SIGH_SAUVEGARDES_DIR=/tmp/banc-a/sauvegardes \
  node build/test-fonctionnel.js > /tmp/banc-a/journal.txt 2>&1 &
until grep -qE "scénarios|Échec|ECHEC" /tmp/banc-a/journal.txt; do sleep 30; done; tail -n 30 /tmp/banc-a/journal.txt
```

ℹ️ Durée : environ 60 minutes. Le motif de fin de la boucle `until` est une proposition : ajustez-le à la dernière ligne que votre version du banc écrit.

### 3.5 Les composants de la cible

| Composant | Commande | Durée indicative |
|---|---|---|
| Domaine (Dart) | `cd packages/domaine && dart pub get && dart analyze && dart test` | quelques minutes |
| Moteur (Dart) | `cd packages/sync_dart && dart test` | quelques minutes |
| Poste, analyse | `cd apps/poste && flutter analyze` | quelques minutes |
| Poste, tests | `cd apps/poste && flutter test` | environ 17 minutes |
| Poste, un fichier | `cd apps/poste && flutter test test/cfg_pair_test.dart` | courte |
| Mobile | `cd apps/mobile && flutter analyze && flutter test` | courte |
| Droits (RBAC) | `cd packages/rbac && node --test` (ou `npm run test:rbac` à la racine) | courte |
| Relais | `cd apps/web && php artisan test` | SQLite en mémoire, aucune base |
| Banc de protocole | `npm run banc:sync` (racine) | environ 140 s |
| Banc de la cible | `npm run banc:cible` (racine) | longue |

Poste complet, en arrière-plan (environ 17 minutes) :

```bash
export PATH=/tmp/flutter-dl/flutter/bin:$PATH
cd apps/poste
setsid nohup sh -c "flutter analyze && flutter test" > /tmp/poste-test.log 2>&1 &
until grep -qE "All tests passed|Some tests failed|issues? found|No issues found" /tmp/poste-test.log; do sleep 30; done; tail -n 30 /tmp/poste-test.log
```

⚠️ La boucle `until` peut se terminer sur « No issues found » (fin de l'analyse) avant la fin des tests. Relisez le journal jusqu'à « All tests passed » ou « Some tests failed ».

Bancs de synchronisation (depuis la racine, PostgreSQL démarré) :

```bash
service postgresql start
npm run banc:sync                 # protocole, mère Node
npm run banc:cible                # mère, fileuls et mobile en Dart contre le relais Laravel
npm run banc:dart                 # mère, fileuls et mobile en Dart, relais Node
npm run banc:laravel              # relais Laravel seul
node --no-warnings packages/sync/banc/run.js P1 P2   # seulement certains scénarios
```

ℹ️ `banc:pg` (mère sur PostgreSQL) et `banc:cible` lancent des processus Dart et PHP : le même verrou s'applique, jamais deux bancs à la fois.

### 3.6 Nettoyer après un banc

```bash
ps aux | grep "[p]hp -S"                           # un serveur PHP de banc resté vivant ?
pkill -f "php -S 127.0.0.1:8931" || true           # ATTENTION : donnez le port exact, un motif trop large peut tuer votre propre shell
psql -U postgres -c "DROP DATABASE IF EXISTS sigh_banc_a;"
rm -rf /tmp/banc-a
git checkout -- prototype_html/build/rapport-tests.json prototype_html/build/rapport-controle.json
git status --short                                 # doit être vide
```

🛑 Ne supprimez que vos propres bases `sigh_banc_*` ou `*_test`. Jamais `sigh_prototype` ni `sigh_relais`.

### 3.7 Parcours « vérification complète », dans l'ordre

À lancer sur un arbre propre, un seul banc à la fois. Durée totale : plusieurs heures. Les étapes 1 à 5 sont rapides, les étapes 6, 8 et 10 sont longues.

```bash
export PATH=/tmp/flutter-dl/flutter/bin:$PATH
service postgresql start
git status --short                                                  # 1. arbre propre

(cd packages/rbac && node --test)                                   # 2. droits
(cd packages/domaine && dart pub get && dart analyze && dart test)  # 3. règles de gestion
(cd packages/sync_dart && dart pub get && dart test)                # 4. moteur
(cd apps/web && php artisan test)                                   # 5. relais

(cd prototype_html && npm run lint && npm run build && npm run check)   # 6. maquette : lint, build, 306 pages
(cd prototype_html && npm run audit-rbac)                               # 7. droits sur chaque écran

npm run banc:sync                                                   # 8. protocole (environ 140 s)
npm run banc:cible                                                  # 9. mère, fileuls, mobile contre le relais Laravel

(cd apps/poste && flutter analyze && flutter test)                  # 10. poste (environ 17 minutes)
(cd apps/mobile && flutter analyze && flutter test)                 # 11. mobile

# 12. suite fonctionnelle de la maquette (environ 60 minutes) : voir 3.4

git checkout -- prototype_html/build/rapport-tests.json prototype_html/build/rapport-controle.json
git status --short                                                  # 13. à nouveau vide
```

✅ Notez pour chaque étape le résultat MESURÉ (nombre de pages, de scénarios, de tests). Une étape non lancée se dit « non lancée », jamais « verte ».

> **Non vérifié ici** : aucune commande de cette section n'a été exécutée (consigne : disque serré, fusion en cours). Elles ont été relues dans `package.json` (maquette, racine, `packages/sync`, `packages/rbac`), dans `prototype_html/build/test-fonctionnel.js` (variables `SIGH_PORT_TEST`, `SIGH_FICHIERS_DIR`, `SIGH_SAUVEGARDES_DIR`, `--seul`) et dans `CLAUDE.md`. Les durées sont celles écrites dans `CLAUDE.md`. Les motifs des boucles `until`, le nom `sigh_banc_a` et les dossiers `/tmp/banc-a` sont des propositions. `banc:pg` exige `SIGH_PG_URL` (lisible dans `packages/sync/banc/run.js`).

---

## 4. Mise en production

Guides détaillés : `DEPLOIEMENT-CPANEL.md`, `GUIDE-LANCEMENT-LOCAL.md` (installateur, messagerie), `docs/prd/PRD-POSTE-installateur-windows.md`, `docs/architecture/adr/ADR-0007-sauvegarde-hors-site-par-blocs-opaques.md`, skill `.claude/skills/release`.

### 4.1 Construire l'installateur Windows du poste

⚠️ À exécuter sur un PC Windows. Prérequis : Flutter 3.47 avec « Desktop Windows », Visual Studio 2022 (C++), Inno Setup 6 (`ISCC.exe`), le Microsoft Visual C++ Redistributable 2015-2022 x64.

```powershell
git switch claude/sighcnt-monorepo-offline-first-i0v3v9
cd apps\poste
.\build_windows.bat
```

Le script fait neuf étapes et s'arrête à la première qui échoue, en la nommant : prérequis, fermeture de l'application, lecture de la version, `flutter pub get`, génération de code si `build_runner` est déclaré, `flutter build windows --release`, copie des runtimes Visual C++, vérification des fichiers à installer, compilation Inno Setup (`installer\sigh_poste.iss`).

Résultat : `apps\poste\build\installer\SIGH_Poste_Setup_<version>.exe` et son `.sha256`.

```powershell
Get-FileHash -Algorithm SHA256 build\installer\SIGH_Poste_Setup_0.1.0.exe   # comparer avec le .sha256 (adaptez la version)
```

ℹ️ La version se change à un seul endroit : la ligne `version:` de `apps\poste\pubspec.yaml` (aujourd'hui `0.1.0+1`).

ℹ️ Les données du poste vivent hors du dossier d'installation : `%LOCALAPPDATA%\SIGHCNT\donnees` (base, magasin, clé de chiffrement, configuration `poste.json`, sauvegardes de la mère).

### 4.2 Installer la mère, puis les fileuls

1. Sur le PC de la mère : lancez `SIGH_Poste_Setup_<version>.exe`. L'assistant d'installation propose notamment un raccourci du bureau.
2. Premier lancement : l'assistant crée le premier administrateur et affiche le code de secours. Rangez-le au coffre (case « je l'ai rangé » obligatoire).
3. « Configurations à faire », « Activer la mère » : adresse du relais `sighcnt.nassieratoo.com`, secret de la mère (la même valeur que `RELAIS_SECRET_MERE` du relais), clé de clinique (16 caractères au moins, copie papier sous scellé).
4. Configurez la clinique, créez les comptes dont un second administrateur, puis émettez les codes d'appairage depuis la console de la mère.
5. Sur chaque poste fileul : installez le même `.exe`, puis dans l'assistant choisissez « Rejoindre une clinique » : adresse de la mère et code d'appairage (8 caractères, 15 minutes, usage unique). La configuration et les comptes sont repris tout seuls.
6. Mobiles : même code d'appairage, par le relais.

Installation et désinstallation silencieuses (déploiement à distance) :

```powershell
.\SIGH_Poste_Setup_0.1.0.exe /VERYSILENT        # adaptez la version
```

🛑 Le mode silencieux GARDE les données. Une désinstallation interactive propose une sauvegarde et un avertissement Oui/Non avec « Non » par défaut ; sur une mère, la base est la copie de référence. Ne désinstallez jamais une mère sans sauvegarde de `%LOCALAPPDATA%\SIGHCNT\donnees`.

ℹ️ Un poste Flutter n'a qu'un code : le mode (mère ou fileul) se décide dans l'assistant. Le détail du choix pour un poste installé est dans `docs/prd/PRD-POSTE-premiere-installation.md`.

### 4.3 Déployer le relais sur cPanel (`sighcnt.nassieratoo.com`)

Guide détaillé : `docs/guides/DEPLOIEMENT-CPANEL.md`. Contraintes : PHP 8.2 ou plus, PostgreSQL, cron chaque minute, PAS de SSH, PAS de Redis, PAS de `npm`.

**a. Préparer l'archive sur le poste de développement**

```bash
cd apps/web
composer install --no-dev --optimize-autoloader        # produit vendor/ (cPanel n'a pas de Composer)
php artisan key:generate --show                        # affiche la valeur de APP_KEY ; à copier dans le .env de production
cd ..
tar -czf /tmp/sigh-relais.tar.gz --exclude=apps/web/.env --exclude=apps/web/storage/logs --exclude=apps/web/node_modules apps/web
```

Téléversez l'archive par le Gestionnaire de fichiers cPanel, extrayez-la dans `~/sigh-relais/` (le contenu de `apps/web`), HORS de `public_html`. Faites pointer le domaine `sighcnt.nassieratoo.com` vers `~/sigh-relais/public`.

🛑 Ne jamais exposer le reste du dossier : il contient `.env`, `vendor/` et le code.

**b. Base PostgreSQL et PHP**

1. cPanel, *PostgreSQL Databases* : créez la base et l'utilisateur, accordez tous les privilèges.
2. *MultiPHP Manager* : PHP 8.2 ou plus. *Select PHP Version* : extensions `pdo_pgsql`, `mbstring`, `openssl`, `ctype`, `json`.
3. Droits d'écriture : `storage/` et `bootstrap/cache/` en 755 (775 si l'hébergeur l'exige).

**c. Le `.env` de production**

Copiez `production.env.exemple` en `.env` à la racine du dossier téléversé, puis renseignez-le dans le Gestionnaire de fichiers cPanel. Écrivez les valeurs secrètes UNIQUEMENT sur le serveur : jamais dans le dépôt, jamais dans un message, jamais dans cette page.

```dotenv
APP_NAME="SIGH-CNT Relais"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://sighcnt.nassieratoo.com
APP_KEY=                       # valeur produite par `php artisan key:generate --show`
APP_LOCALE=fr
APP_FALLBACK_LOCALE=fr

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=                   # nom de la base cPanel
DB_USERNAME=                   # utilisateur cPanel
DB_PASSWORD=                   # à saisir sur le serveur

SESSION_DRIVER=database
SESSION_LIFETIME=60
SESSION_SECURE_COOKIE=true
CACHE_STORE=database
QUEUE_CONNECTION=database
LOG_CHANNEL=daily
LOG_LEVEL=warning

RELAIS_SECRET_MERE=            # long, aléatoire ; le même est saisi sur la console de la mère
RELAIS_SEUIL_BATTEMENT_MS=300000
RELAIS_BANC=false
```

Messagerie (valeurs non secrètes demandées pour la clinique, mot de passe à saisir sur le serveur) :

```dotenv
MAIL_MAILER=smtp
MAIL_SCHEME=smtp               # 587 en STARTTLS ; smtps pour le port 465
MAIL_HOST=mail.sighcnt.nassieratoo.com
MAIL_PORT=587
MAIL_USERNAME=admin@sighcnt.nassieratoo.com
MAIL_PASSWORD=                 # à saisir sur le serveur
MAIL_TIMEOUT=20
MAIL_FROM_ADDRESS=admin@sighcnt.nassieratoo.com
MAIL_FROM_NAME="Clinique Nassièra Too"
```

⚠️ **Écart à trancher.** `apps/web/.env.example` propose encore `mail.sigh.nassieratoo.com` et `contact@sigh.nassieratoo.com`. Cette page donne `mail.sighcnt.nassieratoo.com` et `admin@sighcnt.nassieratoo.com`, comme demandé. Confirmez le nom exact du serveur de messagerie auprès de l'hébergeur avant de coller, puis testez (4.3 f). Le manuel de l'administrateur signale déjà ce double nom.

ℹ️ Le panneau superadmin (Paramètres, carte « Messagerie ») permet aussi de saisir le mot de passe SMTP en saisie à sens unique (chiffré, jamais relu), puis « Envoyer un message de test ». La décision du 07/11/2026 (`docs/prd/PRD-SMS-passerelle-et-test-envoi.md`) a ensuite placé les secrets dans le `.env`. Le PRD dit que ce point est à valider : suivez la décision de la Direction du moment.

**SMS (Twilio, Vonage)** : variables prévues par le PRD pour le `.env` du relais, à saisir sur le serveur uniquement :

```dotenv
RELAIS_SMS_FOURNISSEUR=twilio          # twilio (défaut) ou vonage
RELAIS_SMS_TWILIO_SID=                 # à saisir sur le serveur
RELAIS_SMS_TWILIO_TOKEN=               # à saisir sur le serveur
RELAIS_SMS_VONAGE_KEY=                 # à saisir sur le serveur
RELAIS_SMS_VONAGE_SECRET=              # à saisir sur le serveur
```

⚠️ **Constaté dans le dépôt le 16/11/2026** : aucune de ces variables n'est lue dans `apps/web/app` ou `apps/web/config`, et la commande `relais:sms-envoyer` n'existe pas (les commandes du relais sont `relais:superadmin`, `relais:statut`, `relais:purger`, `relais:exporter`, `relais:surveiller`, `relais:copie-volume`). La passerelle SMS n'existe aujourd'hui que dans la maquette (`prototype_html/api/sms.php`). Ne posez pas la tâche `relais:sms-envoyer` tant que la commande n'existe pas : voir 4.3 e.

**d. Créer les tables et le compte superadmin (cron à usage unique)**

Sans SSH, une commande se lance par une tâche cron créée pour la minute suivante, puis SUPPRIMÉE. Chemin PHP : `/usr/local/bin/php`, ou `ea-php82`.

```bash
cd ~/sigh-relais && /usr/local/bin/php artisan migrate --force
cd ~/sigh-relais && /usr/local/bin/php artisan relais:superadmin dg@exemple.bj --mot-de-passe='douze-caracteres-minimum'
cd ~/sigh-relais && /usr/local/bin/php artisan optimize:clear
```

🛑 Avant chaque `migrate` en production, exportez la base (4.6). Après la création du compte superadmin, supprimez la ligne de cron : elle contient le mot de passe.

**e. Les tâches cron permanentes**

Une seule ligne permanente suffit : le planificateur de Laravel lance les tâches de `apps/web/routes/console.php`.

```
* * * * * cd ~/sigh-relais && /usr/local/bin/php artisan schedule:run >> /dev/null 2>&1
```

Ce que `schedule:run` déclenche (relu dans `routes/console.php`) :

| Tâche | Heure | Rôle |
|---|---|---|
| `relais:surveiller` | chaque minute | marque le passage du cron (écran Hébergement), lève et résout les alertes |
| `relais:exporter` | 03:00 chaque jour | export de la base dans `storage/app/exports` |
| `relais:purger --oui` | 03:10 chaque jour | purge de l'audit (jamais des enveloppes) |

ℹ️ Si votre hébergeur préfère des lignes cron séparées, remplacez l'unique ligne par ces trois, mais ne combinez jamais les deux : les tâches tourneraient en double.

```
* * * * * cd ~/sigh-relais && /usr/local/bin/php artisan relais:surveiller >> /dev/null 2>&1
0 3 * * * cd ~/sigh-relais && /usr/local/bin/php artisan relais:exporter >> /dev/null 2>&1
10 3 * * * cd ~/sigh-relais && /usr/local/bin/php artisan relais:purger --oui >> /dev/null 2>&1
```

⚠️ `relais:sms-envoyer` : à planifier seulement si la commande existe dans la version déployée. Contrôle : `php artisan list | grep relais` (par cron à usage unique, sortie dans un fichier).

**f. Brancher la mère et tester la messagerie**

Sur la console de la mère : adresse `sighcnt.nassieratoo.com` (le poste ajoute `https://`) et le MÊME `RELAIS_SECRET_MERE`. Le relais n'appelle jamais la mère : elle vient relever toutes les 10 à 15 secondes. Panneau superadmin, Paramètres, « Messagerie », « Envoyer un message de test » avec votre adresse : l'étape en échec est nommée.

### 4.4 Vérifications après la mise en service

À faire dans un navigateur et par la liste de `DEPLOIEMENT-CPANEL.md` §6 :

```bash
curl -sI https://sighcnt.nassieratoo.com/panneau | head -n 5            # redirige vers la connexion
curl -sI https://sighcnt.nassieratoo.com/ | head -n 5                   # redirige aussi
curl -s -o /dev/null -w "%{http_code}\n" https://sighcnt.nassieratoo.com/.env                 # attendu : 404
curl -s -o /dev/null -w "%{http_code}\n" https://sighcnt.nassieratoo.com/vendor/autoload.php  # attendu : 404
curl -s -o /dev/null -w "%{http_code}\n" https://sighcnt.nassieratoo.com/banc/anything        # attendu : 404 (RELAIS_BANC=false)
```

- [ ] Le tableau de bord du panneau affiche « Poste mère : En ligne » (seuil de 5 minutes sans battement).
- [ ] L'écran Hébergement montre le passage du cron (`relais:surveiller`).
- [ ] `APP_DEBUG=false`, `RELAIS_BANC=false`, cookie `Secure`, HTTPS forcé.
- [ ] Le message de test de la messagerie arrive.
- [ ] Une sauvegarde de la base du relais est planifiée (4.6).
- [ ] La clé de clinique est ailleurs que sur le relais et que dans le dépôt : copie papier sous scellé chez la Direction.

🛑 Ne consignez jamais le `.env` de production, `APP_KEY`, le secret de la mère, la clé de clinique ou un mot de passe dans un ticket, un courriel ou le dépôt.

### 4.5 Mettre à jour

Relais :

1. Exportez la base (4.6), avec `--avant-migration`.
2. Refaites l'étape 4.3 a avec le nouveau code. Téléversez en écrasant, en CONSERVANT `.env` et `storage/`.
3. Par cron à usage unique : `migrate --force`, puis `optimize:clear`.
4. Rejouez les vérifications de 4.4.

```bash
cd ~/sigh-relais && /usr/local/bin/php artisan relais:exporter --avant-migration
cd ~/sigh-relais && /usr/local/bin/php artisan migrate --force
cd ~/sigh-relais && /usr/local/bin/php artisan optimize:clear
```

Poste : construisez un nouvel installateur (4.1), puis installez-le par-dessus sur la mère d'abord, puis sur les fileuls. Sauvegardez la mère avant (4.6).

ℹ️ Rotation du secret de la mère : changez `RELAIS_SECRET_MERE` dans le `.env` du relais, puis dans la configuration de la mère. Les jetons d'appareil se renouvellent seuls.

### 4.6 Sauvegarde, retour arrière et restauration

**Relais**

```bash
cd ~/sigh-relais && /usr/local/bin/php artisan relais:exporter      # fichier relais-AAAAMMJJ-HHMMSS.jsonl.gz dans storage/app/exports
```

L'export est un fichier gzip, une ligne JSON par enregistrement, déjà chiffré de bout en bout. Il ne contient ni comptes ni sessions, ni les copies de sauvegarde hors site. Faites aussi un export complet de la base par phpPgAdmin ou `pg_dump`, et copiez-le HORS du serveur.

ℹ️ Le relais ne détient aucune clé. Sa perte ne perd pas les données de la clinique (elles vivent sur la mère), mais perdrait les boîtes des mobiles non relevées.

**Retour arrière du relais** : remettez l'ancien code (archive précédente, `.env` et `storage/` conservés) et, si la migration a changé le schéma, restaurez l'export complet de la base pris avant la mise à jour (phpPgAdmin, ou `psql` sur la base vidée). Puis `optimize:clear` par cron à usage unique.

**Mère (poste)** : sauvegardez ensemble le dossier `%LOCALAPPDATA%\SIGHCNT\donnees` ET le fichier de clé du poste. Dans l'application : « Paramètres système », « Sauvegarder la clé de chiffrement » (phrase de passe de 12 caractères, `.cle` et phrase rangés séparément au coffre).

🛑 Sans la clé de clinique et sans la clé du poste, une copie de sauvegarde ne se lit pas. Il n'existe aucun contournement.

**Sauvegarde hors site de la mère (ADR-0007)** : réglage de clinique `horssite.*`, DÉSACTIVÉ par défaut, activé par l'administrateur ou la DAF. Blocs chiffrés au poste mère par la clé de clinique ; destination : le relais (`storage/app/sauvegardes`, hors base) ou un dossier distant monté. La restauration se vérifie dans un dossier neuf. Voir la page « Sauvegarde du relais » du panneau.

**Maquette (démonstration seulement)**

```bash
cd prototype_html
php api/restaurer.php api/sauvegardes/magasin-AAAA-MM-JJ.json.gz           # simulation : ne modifie rien
php api/restaurer.php api/sauvegardes/magasin-AAAA-MM-JJ.json.gz --oui     # remplace le magasin
php api/controler_fichiers.php                                             # contrôle des fichiers numérisés
pg_dump -U postgres --clean --if-exists --no-owner --no-privileges sigh_prototype > sigh_prototype.sql
```

🛑 Une restauration remplace TOUTES les collections. L'état précédent est conservé dans `api/sauvegardes/avant-restauration-<date>.json.gz`. Les `*.sql` ne sont jamais versionnés.

> **Non vérifié ici** : aucun déploiement, aucune construction de l'installateur Windows (pas de Windows, pas d'Inno Setup), aucun appel au relais en ligne. Les commandes viennent de `DEPLOIEMENT-CPANEL.md`, de `apps/web/routes/console.php`, des signatures des commandes `relais:*`, de `build_windows.bat` et de `sigh_poste.iss`. Les lignes cron séparées, la commande `tar`, les `curl` de contrôle, le chemin `~/sigh-relais` et le nom de l'installateur en `/VERYSILENT` sont des propositions. Les valeurs `mail.sighcnt.nassieratoo.com` et `admin@sighcnt.nassieratoo.com` viennent de la demande de la Direction, pas du dépôt. Le mode silencieux de l'installateur est décrit par le PRD (R6) ; il n'a pas été essayé. Le retour arrière du relais par restauration de l'export `.jsonl.gz` n'a pas d'outil : seule la restauration d'un export complet de la base est documentée ici.

---

## 5. Pièges à ne pas réapprendre

- Régénérez la safelist AVANT la CSS (`npm run build` le fait dans le bon ordre). `gen-safelist.js` retire les commentaires : une apostrophe isolée dans un commentaire JS fait disparaître des classes.
- Écrire des fichiers par un script Python sous Windows les passe en CRLF : utilisez Node ou l'outil d'édition.
- `pkill -f <motif>` peut tuer son propre shell si le motif figure dans sa ligne de commande.
- Un `rapport-tests.json` modifié n'est pas un travail : restaurez-le.
- Toute modification de forme de la maquette incrémente `VERSION` dans `prototype_html/assets/js/store.js` (un seul endroit), sinon les postes gardent l'ancien jeu.
- `flutter run` sous Windows : fermez l'application et tout `flutter_tester` avant `flutter build windows`, un `sqlite3.dll` verrouillé fait échouer la construction.

## 6. Récapitulatif de ce qui n'est pas vérifié

- Aucune commande de test, de banc ou de déploiement n'a été exécutée pour écrire cette page (consigne). Seules des lectures de scripts et des commandes légères ont servi.
- Les durées sont celles du `CLAUDE.md`, non remesurées.
- Windows (`build_windows.bat`, installateur, `/VERYSILENT`), SQLCipher, le relais en ligne, deux machines réelles et la charge ne sont pas vérifiés.
- Les variables `RELAIS_SMS_*` et la commande `relais:sms-envoyer` ne sont pas implémentées dans `apps/web` au 16/11/2026.
- Le domaine de messagerie `sighcnt.nassieratoo.com` diffère de celui du dépôt (`sigh.nassieratoo.com`) : à confirmer auprès de l'hébergeur.
- Les guides `LANCER-EN-LOCAL.md`, `GUIDE-LANCEMENT-LOCAL.md` et `GUIDE-DEMARRAGE.md` datent d'octobre et de novembre 2026 et ne mentionnent ni `relais:surveiller` ni `relais:exporter` dans leurs sections de déploiement : cette page est plus à jour sur ce point.
