# Commandes : cloner, installer, tester, mettre en production

Public : l'administrateur et le développeur de la clinique. Toutes les commandes se copient telles quelles. Chacune a été relue dans le dépôt (`package.json`, scripts, README, guides). Ce qui n'a pas pu être vérifié est dit dans l'encadré « Non vérifié » de chaque section et récapitulé en section 8. Mise à jour du 17/11/2026, d'après le dépôt (lots SMS-R, SAT, IDENT, IDENT-MIG et suivants).

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

🛑 Ne lancez jamais `git clean -fd` sans `-n` d'abord (simulation), et ne faites jamais `git pull` sur un poste en service sans sauvegarde (voir section 4.6).

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

ℹ️ `schedule:work` lance AUSSI `relais:sms-envoyer` chaque minute. Sans les variables `RELAIS_SMS_*` du `.env`, aucun SMS ne part : le relais refuse avec un code nommé (`SECRET_NON_DEFINI`, `SMS_NON_CONFIGUREE`). C'est le comportement voulu en local.

Commandes d'exploitation :

```bash
php artisan relais:statut                         # volumes (appareils, enveloppes, Ko, dernier battement), aucun contenu
php artisan relais:exporter                       # export de la base dans storage/app/exports
php artisan relais:purger                         # SIMULATION de la purge de l'audit
php artisan relais:purger --oui                   # applique (365 jours par défaut, 30 minimum)
php artisan relais:surveiller                     # marque le passage du cron et évalue les alertes
php artisan relais:sms-envoyer                    # envoie les SMS arrivés à l'heure (voir 4.3 c et e)
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

⚠️ **La maquette lit l'horloge du jour.** Certains vecteurs et certaines fiches dérivent selon la date (exercice, années des références, mois glissants, échéances). Un banc ou un test qui passait hier peut échouer aujourd'hui sans que le code ait changé. Après un changement de date, régénérez les fichiers engendrés (`node build/gen-poste-jeu.js` et les extracteurs, depuis `prototype_html/`) avant de conclure à une régression.

⚠️ **`node build/extraire.js` réécrit `packages/domaine/lib/src/design/jetons.dart`** (et `gen-poste-assets.js` réécrit `apps/poste/lib/core/jetons_shell.dart`). Ces deux fichiers peuvent changer de contenu après un passage des extracteurs : vérifiez `git status`, puis restaurez-les (`git checkout -- <fichier>`) si la différence n'est pas voulue.

⚠️ **Dans un arbre de travail git (`git worktree`) dont `vendor/` ou `node_modules` est un lien** vers le dépôt principal, `php artisan test` charge et teste le code du dépôt PRINCIPAL, pas celui de l'arbre. Constaté en session ; la variable à poser est `APP_BASE_PATH` (valeur : le dossier `apps/web` de l'arbre que vous voulez tester). Contrôlez en lisant le chemin affiché dans une trace d'erreur. Ne commitez jamais le lien `node_modules`.

⚠️ **Le dossier `apps/web/tests/Unit` doit exister, vide** : git ne suit pas un dossier vide, et PHPUnit s'arrête net sans lui. Après un clone : `mkdir -p apps/web/tests/Unit`.

⚠️ **Les exécutables de `packages/sync_dart/build/` se reconstruisent** par `packages/sync_dart/construire.sh` (`dart build cli`, un bundle par cible : mere, fileul, mobile). Un binaire périmé donne de FAUX résultats aux bancs `banc:dart` et `banc:cible`, sans erreur visible. Reconstruisez après toute modification de `packages/sync_dart` ou de `packages/domaine`. Le dossier `build/` n'existe pas après un clone.

⚠️ **Un test du poste qui passe isolé peut être fragile sous charge** (horloge, ordre, ports). Un vert isolé ne dit pas que la suite complète passe : relancez le fichier derrière ses voisins, puis la suite entière.

✅ Après un banc, relisez le nombre de scénarios et de vérifications MESURÉ dans le rapport. Les chiffres du CLAUDE.md sont des ordres de grandeur.

### 3.2 La maquette (depuis `prototype_html/`)

| Commande | Ce qu'elle prouve | Durée indicative |
|---|---|---|
| `npm run lint` | syntaxe des sources JS et gardes de doctrine (`garde-listes-prix`, `garde-roles-en-dur`, `garde-tableaux`) | quelques minutes |
| `npm run build` | pages, safelist Tailwind, CSS | quelques minutes |
| `npm run check` | 306 pages dans Chrome : 0 erreur JS, 0 lien cassé | longue |
| `npm test` | 233 scénarios de bout en bout (mesuré au dernier passage complet, voir 3.8) | environ 60 minutes ou plus |
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

ℹ️ Durée : 60 minutes ou plus (233 scénarios au dernier passage). Le motif de fin de la boucle `until` est une proposition : ajustez-le à la dernière ligne que votre version du banc écrit.

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
| Banc de protocole | `npm run banc:sync` (racine) | environ 140 s (durée de `CLAUDE.md`, non remesurée avec les 475 scénarios actuels) |
| Banc de la cible | `npm run banc:cible` (racine) | longue |
| Passerelle SMS et satisfaction (relais) | `cd apps/web && php artisan test --filter=SmsTest` puis `--filter=SatisfactionEnLigneTest` | courte, AUCUN envoi réel |

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

⚠️ Avant l'étape 8, reconstruisez les exécutables du moteur : `packages/sync_dart/construire.sh` (voir 3.1). Après l'étape 6, restaurez aussi `jetons.dart` et `jetons_shell.dart` s'ils ont changé sans que vous l'ayez voulu.

✅ Notez pour chaque étape le résultat MESURÉ (nombre de pages, de scénarios, de tests). Une étape non lancée se dit « non lancée », jamais « verte ».

### 3.8 Chiffres MESURÉS du dernier passage complet

Mesurés par la session de vérification complète du 16 au 17/11/2026, rapportés ici tels qu'on les a reçus (ils ne sont pas remesurés par cette page) :

| Suite | Résultat mesuré |
|---|---|
| Maquette, `npm test` | 233 scénarios |
| `npm run banc:sync` | 475 |
| `npm run banc:cible` | 434 |
| Domaine (`dart test`) | 4 721 tests |
| Relais (`php artisan test`) | 205 tests |
| Moteur (`packages/sync_dart`, `dart test`) | 148 |
| Droits (`packages/rbac`, `node --test`) | 33 |

ℹ️ Ces nombres montent à chaque lot. Un écart vers le haut est normal ; un écart vers le bas est une alerte (scénario perdu ou suite interrompue). Une suite non lancée se dit « non lancée ».

> **Non vérifié ici** : aucune commande de cette section n'a été exécutée par la présente mise à jour (consigne : une vérification complète tourne). Elles ont été relues dans `package.json` (maquette, racine, `packages/sync`, `packages/rbac`), dans `prototype_html/build/test-fonctionnel.js` (variables `SIGH_PORT_TEST`, `SIGH_FICHIERS_DIR`, `SIGH_SAUVEGARDES_DIR`, `--seul`) et dans `CLAUDE.md`. Les durées sont celles écrites dans `CLAUDE.md`. Les chiffres de 3.8 sont rapportés, non remesurés. Le nom de la variable `APP_BASE_PATH` et son effet sur `php artisan test` viennent du retour de la session de vérification, non essayés ici. Les motifs des boucles `until`, le nom `sigh_banc_a` et les dossiers `/tmp/banc-a` sont des propositions. `banc:pg` exige `SIGH_PG_URL` (lisible dans `packages/sync/banc/run.js`).

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

ℹ️ Les valeurs `mail.sighcnt.nassieratoo.com` et `admin@sighcnt.nassieratoo.com` sont désormais celles du dépôt (`apps/web/.env.example`, corrigé). `MAIL_REPLY_TO_ADDRESS` y porte l'adresse de réponse de la clinique. Confirmez quand même le nom du serveur de messagerie auprès de l'hébergeur avant de coller, puis testez (4.3 f).

ℹ️ Le panneau superadmin (Paramètres, carte « Messagerie ») permet aussi de saisir le mot de passe SMTP en saisie à sens unique (chiffré, jamais relu), puis « Envoyer un message de test ». La décision du 07/11/2026 (`docs/prd/PRD-SMS-passerelle-et-test-envoi.md`) a ensuite placé les secrets dans le `.env`. Le PRD dit que ce point est à valider : suivez la décision de la Direction du moment.

**SMS (Twilio, Vonage)** : la passerelle existe dans le relais (lot SMS-R, ADR-0008). Variables du `.env` (modèles : `apps/web/.env.example` et `production.env.exemple`, identifiants VIDES dans le dépôt), à saisir sur le serveur uniquement :

```dotenv
RELAIS_SMS_FOURNISSEUR=twilio          # twilio (défaut) ou vonage
RELAIS_SMS_EXPEDITEUR=                 # numéro E.164 ou identifiant alphanumérique accepté pour le Bénin
RELAIS_SMS_TWILIO_SID=                 # à saisir sur le serveur
RELAIS_SMS_TWILIO_TOKEN=               # à saisir sur le serveur
RELAIS_SMS_VONAGE_KEY=                 # à saisir sur le serveur
RELAIS_SMS_VONAGE_SECRET=              # à saisir sur le serveur
```

- Les deux fournisseurs passent par leur bibliothèque officielle, déjà déclarée dans `apps/web/composer.json` : `twilio/sdk` (`^8.14`) et `vonage/client` (`^4.4`). `composer install --no-dev` du paragraphe a les installe ; rien d'autre à ajouter.
- Le relais refuse en nommant la cause : fournisseur inconnu ou expéditeur absent (`SMS_NON_CONFIGUREE`), identifiants absents (`SECRET_NON_DEFINI`), identifiants rejetés, plafond du jour atteint (`PLAFOND_ATTEINT`, jamais reporté au lendemain).
- Les routes `/sms/etat`, `/sms/deposer`, `/sms/annuler`, `/sms/tester` (10 appels par minute au plus) et `/sms/journal` sont RÉSERVÉES au poste mère (en-tête du secret de la mère). Un mobile ou un fileul n'y accède pas.
- Le relais voit numéro, texte, heure, type et un identifiant opaque, le temps de l'envoi, puis efface le clair. Le journal lu par la mère masque le numéro (quatre derniers chiffres) et ne contient jamais le texte. Les règles (consentement, heures calmes, mots interdits) sont décidées à la mère ; les SMS automatiques sont DÉSACTIVÉS par défaut (paramètres `sms` du poste mère, écran « cfg-sms »).
- Aucun envoi réel en test : `apps/web/tests/Feature/SmsTest.php` remplace le client HTTP par `Http::fake()`. Un test d'envoi réel se fait seulement depuis l'écran du poste mère (bouton de test) ou `POST /sms/tester`, avec de vrais identifiants, et coûte un SMS.

**Satisfaction en ligne (lot SAT, ADR-0009)** : aucune variable `.env` propre. Le formulaire public du relais est `GET /s/{jeton}` (dépôt : `POST /s/{jeton}`), sans cookie ni session ; un jeton inconnu, expiré ou révoqué reçoit une seule réponse générique (404). Les réponses sont chiffrées DANS LE NAVIGATEUR (X25519, HKDF-SHA-256, AES-256-GCM) : le relais ne les lit jamais. La paire de clés est dérivée de la clé de clinique de la mère (jamais envoyée au relais, seule la clé publique est publiée). `POST /satisfaction/publier` et `GET /satisfaction/releve` sont réservées à la mère ; un appareil appairé reçoit 403 `satisfaction_reservee_mere`. La collecte est DÉSACTIVÉE par défaut (réglage de clinique `satisfaction.enLigne`) ; la mère relève chaque minute. Pour l'ouvrir : activez le réglage au poste mère, publiez la clé et les liens, puis testez un lien dans un navigateur.

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
| `relais:sms-envoyer` | chaque minute, sans chevauchement (verrou de 10 minutes) | envoie les SMS arrivés à l'heure, efface le clair |

Tableau complet des tâches planifiées du relais (source : `apps/web/routes/console.php`, quatre tâches) :

| Commande | Fréquence | Effet si elle ne tourne pas |
|---|---|---|
| `relais:surveiller` | chaque minute | l'écran Hébergement dit que le cron ne passe pas, les alertes ne se lèvent plus |
| `relais:sms-envoyer` | chaque minute | aucun SMS programmé ne part (ils restent en attente) |
| `relais:exporter` | 03:00 | pas d'export quotidien de la base |
| `relais:purger --oui` | 03:10 | l'audit grossit (jamais les enveloppes) |

ℹ️ Si votre hébergeur préfère des lignes cron séparées, remplacez l'unique ligne par ces quatre, mais ne combinez jamais les deux : les tâches tourneraient en double.

```
* * * * * cd ~/sigh-relais && /usr/local/bin/php artisan relais:surveiller >> /dev/null 2>&1
0 3 * * * cd ~/sigh-relais && /usr/local/bin/php artisan relais:exporter >> /dev/null 2>&1
10 3 * * * cd ~/sigh-relais && /usr/local/bin/php artisan relais:purger --oui >> /dev/null 2>&1
* * * * * cd ~/sigh-relais && /usr/local/bin/php artisan relais:sms-envoyer >> /dev/null 2>&1
```

ℹ️ Contrôle de la version déployée : `php artisan list | grep relais` (par cron à usage unique, sortie dans un fichier) doit montrer `relais:sms-envoyer`. Un relais déployé avant le lot SMS-R ne l'a pas : mettez-le à jour (4.5).

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
- [ ] Le journal de la passerelle SMS (panneau, « Passerelle SMS ») montre un passage récent de `relais:sms-envoyer`, et le test d'envoi depuis la mère n'est lancé qu'avec de vrais identifiants posés sur le serveur.
- [ ] `curl -s -o /dev/null -w "%{http_code}\n" https://sighcnt.nassieratoo.com/s/jeton-inconnu` répond 404 (réponse générique du formulaire de satisfaction).
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

> **Non vérifié ici** : aucun déploiement, aucune construction de l'installateur Windows (pas de Windows, pas d'Inno Setup), aucun appel au relais en ligne. Les commandes viennent de `DEPLOIEMENT-CPANEL.md`, de `apps/web/routes/console.php`, des signatures des commandes `relais:*`, de `build_windows.bat` et de `sigh_poste.iss`. Les lignes cron séparées, la commande `tar`, les `curl` de contrôle, le chemin `~/sigh-relais` et le nom de l'installateur en `/VERYSILENT` sont des propositions. Les valeurs de messagerie sont celles de `.env.example`, jamais essayées sur le serveur de l'hébergeur. Les routes SMS et satisfaction, les variables `RELAIS_SMS_*` et la tâche `relais:sms-envoyer` sont relues dans le code, aucun SMS réel n'a été envoyé, le formulaire public n'a pas été ouvert sur un relais en ligne. Le mode silencieux de l'installateur est décrit par le PRD (R6) ; il n'a pas été essayé. Le retour arrière du relais par restauration de l'export `.jsonl.gz` a désormais son outil (`relais:relire-export --restaurer`, 4.7), essayé seulement sur la base de test du relais.

### 4.7 Mettre à jour le logiciel (pas à pas, sans perdre une donnée)

Spécification : `docs/prd/PRD-MISE-A-JOUR-sauvegarde-export-reimport.md`. Écarts E3080 à E3099, décisions section BG. Ordre à respecter : **relais, puis mère, puis fileuls, jamais l'inverse.** Les deux écrans (« Mettre à jour le logiciel » et, sur un poste neuf, « clé de chiffrement ») sont écrits et testés par des tests de widgets ; **aucun n'a été vu sur un vrai poste Windows**, ni l'installateur avec une vraie migration.

**Avant de commencer** : choisir la fenêtre (question ouverte BG 8) et prévenir les agents ; vérifier que la clé de clinique est sauvegardée sous scellé et la clé du poste exportée (« Paramètres système », « Sauvegarder la clé de chiffrement ») : sans elles aucune copie ne se lit, c'est voulu. Le droit de lancer une mise à jour est le geste réservé `lancer_mise_a_jour` (administrateur et Directrice Administrative par défaut) : sans lui l'écran est en lecture seule, les commandes sont absentes.

**1. Le relais (si le code du relais change)**

```bash
cd ~/sigh-relais && /usr/local/bin/php artisan relais:mise-a-jour --essai    # ne fait rien, dit ce qui serait fait
cd ~/sigh-relais && /usr/local/bin/php artisan relais:mise-a-jour           # exporte, RELIT l'export, puis migrate --force
```

La commande exporte la base (`--avant-migration`), relit l'export et ne migre PAS si la relecture échoue (`MAJ_SANS_SAUVEGARDE`). Téléversez le nouveau code avant, en conservant `.env` et `storage/` (4.5).

**Retour arrière du relais** : remettre l'ancien code, créer une base neuve, puis relire et restaurer l'export d'avant la migration.

```bash
cd ~/sigh-relais && /usr/local/bin/php artisan relais:relire-export storage/app/exports/relais-AAAAMMJJ-HHMMSS-avant-migration.jsonl.gz            # relit, ne modifie rien
cd ~/sigh-relais && /usr/local/bin/php artisan relais:relire-export storage/app/exports/relais-AAAAMMJJ-HHMMSS-avant-migration.jsonl.gz --restaurer # base neuve seulement
```

Refus nommés : `EXPORT_INTROUVABLE`, `EXPORT_ILLISIBLE`, `EXPORT_ANOMALIES`, `RESTAURATION_BASE_NON_VIDE` (rien n'est écrasé). La restauration ne remet pas les copies de sauvegarde hors site (elles ne sont pas dans l'export).

**2. La mère : une copie vérifiée avant l'installateur**

1. Sur la mère, ouvrez « Mettre à jour le logiciel » (module « Sécurité et utilisateurs ») puis **« Préparer la mise à jour »** : copie chiffrée du magasin, restauration vérifiée dans un dossier neuf, comptes et empreintes consignés. L'écran dit la date de la dernière copie vérifiée. Sans copie de moins de 24 h (réglage `maj.ageMaxCopieHeures`), la migration refuse (`MAJ_SANS_SAUVEGARDE`).
2. En plus, « Sauvegardes et restauration » : « Sauvegarder maintenant » puis « Vérifier la dernière ». Copiez `%LOCALAPPDATA%\SIGHCNT\donnees` ET le fichier de clé du poste sur un support externe.
3. Facultatif : « Exporter la base » écrit UN fichier `.sighexp` chiffré par la clé de clinique (base, fichiers numérisés, manifeste signé, format).

**3. Installer la nouvelle version**

Lancez `SIGH_Poste_Setup_<version>.exe` par-dessus l'ancienne version (même `AppId`) : **l'installateur ne touche jamais au dossier de données** (`sigh_poste.iss`). Commencez par la mère, puis chaque fileul. Au premier démarrage le poste ramène une migration interrompue par une coupure aux données d'avant (jamais un état mixte) et refuse nommément des données plus récentes que le logiciel (`DONNEES_PLUS_RECENTES` : réinstaller la version qui les a écrites). **Il ne migre rien en silence** : la migration est le geste de l'étape 4.

**4. Migrer les données de la mère, puis des fileuls**

1. « Essai à blanc » : dit ce qui changerait, n'écrit rien.
2. « Migrer les données » : refuse `MAJ_SANS_SAUVEGARDE` sans copie vérifiée de moins de 24 h ; relit et compare : « N fiches avant, N après », toute différence nommée ; en cas d'écart les données d'avant sont remises. L'écran demande ensuite de **redémarrer** le poste (le format stocké est repris au démarrage).
3. Tant que la mère n'est pas migrée, un fileul neuf (déjà au format courant) reçoit `426 schema_incompatible` (« mettre à jour la mère d'abord ») : il n'envoie rien et garde ses saisies hors ligne. Une fois la mère migrée et redémarrée, c'est un fileul resté à l'ancien format qui est refusé (écart de deux versions, la tolérance par défaut est une) : il migre à son tour par le même écran, puis se resynchronise sans doublon. Le réglage `maj.ecartVersionTolere` (« Règles métier versionnées ») peut élargir la tolérance le temps du déploiement.

**5. Retour arrière**

« Annuler la mise à jour » montre la dernière copie vérifiée et la LISTE des saisies faites depuis (créées, modifiées), puis restaure sur confirmation. L'état actuel est rangé à part (`avant-retour-…` à côté du magasin) : rien n'est écrasé en silence. Objectif du PRD : moins de 30 minutes (réglage `maj.retourArriereMinutes`, objectif affiché, non mesuré sur le matériel de la clinique ; sur un jeu généré de 108 000 fiches, les opérations durent entre 5 et 20 secondes). Redémarrez ensuite.

**6. Changer de machine, ou repartir d'une copie : export portable**

Sur la nouvelle machine : au premier démarrage, l'écran « clé de chiffrement » demande **« Restaurer la clé de la clinique »** (fichier `.cle` de « Sauvegarder la clé de chiffrement » et phrase de passe ; refus nommés `CLE_PHRASE_INCORRECTE`, `CLE_FICHIER_INVALIDE`) : ne choisissez « Premier poste de la clinique » que pour la toute première installation. Puis « Préparer la mise à jour » (copie préalable exigée), puis **« Importer une base »** : l'écran montre d'abord un essai à blanc (comptes, avertissements, saisies listées) puis demande confirmation. Refus nommés : `IMPORT_SANS_CLE`, `IMPORT_AUTRE_CLINIQUE`, `IMPORT_ALTERE`, `DONNEES_PLUS_RECENTES`, `IMPORT_SANS_COPIE_PREALABLE`. Sur un fileul rattaché, une base plus ancienne que sa dernière synchronisation déclenche l'avertissement `IMPORT_PLUS_ANCIEN_QUE_SYNC` (non bloquant) : ses saisies postérieures sont listées et gardées dans la copie d'avant l'import, il rejoue le journal de la mère sans rien écrire à sa place (la mère refuse toute « création » d'une fiche qu'elle connaît), et reprend ce rejeu au démarrage si une coupure l'interrompt. Un fileul non rattaché importe comme une mère de lui-même.

**Vérifier le service et les écrans sans poste Windows** (développement) :

```bash
export PATH=/tmp/flutter-dl/flutter/bin:$PATH
cd packages/domaine && dart test test/maj_test.dart test/parametres_clinique_test.dart
cd apps/poste && flutter test test/maj_poste_test.dart test/maj_sync_test.dart test/maj_ecran_test.dart test/maj_demarrage_test.dart test/demarrage_cle_test.dart
cd apps/poste && dart run tool/mesure_maj.dart 18000          # jeu généré, aucune donnée réelle
cd apps/web && php vendor/bin/phpunit tests/Feature/MiseAJourRelaisTest.php   # voir la note sur APP_BASE_PATH (arbre de travail)
```

> **Non vérifié** : Windows, l'installateur avec une vraie migration, DPAPI, deux machines physiques, le matériel de la clinique, les volumes réels de fichiers numérisés, `main()` lancé pour de vrai (fenêtre, session). Non fait : P2 (contrôle planifié de la copie hors site, mise à jour guidée des fileuls depuis la mère).

## 5. Chiffrement au repos (poste Windows)

Sources : `apps/poste/lib/donnees/persistance.dart`, `apps/poste/lib/main.dart`, `apps/poste/pubspec.yaml`, `packages/sync_dart/lib/src/commun.dart`, ECARTS-MAQUETTE E2147.

Ce qui est chiffré, par défaut (sans `SIGH_CHIFFREMENT=non`) :

| Quoi | Comment |
|---|---|
| Les fichiers du poste (magasin `magasin/`, `poste.json`, `pair.json`, `smtp.json`, file de courriels, fichiers numérisés `fichiers/`) | AES-256-GCM, un nonce frais à chaque écriture, le nom de la collection lié au chiffré |
| La clé de ces fichiers (`cle-poste.bin`) | 256 bits tirés au hasard, protégée par DPAPI sous Windows (portée utilisateur : liée à la session Windows) |
| Les bases SQLite de la mère (`mere.db`) et du journal du poste (`poste.db`) | SQLite3 Multiple Ciphers (ChaCha20-Poly1305), même clé locale |
| La sauvegarde de la clé | exportée chiffrée par une phrase de passe (PBKDF2-SHA256 200 000 tours, AES-256-GCM, 12 caractères au moins) |

ℹ️ Un magasin ou une base en CLAIR d'avant (poste mis à jour) est chiffré sur place au premier démarrage, et le clair est supprimé : aucune copie lisible ne reste. Une clé fausse est un refus nommé, jamais une base lue de travers.

⚠️ Ce n'est pas un coffre matériel. Qui ouvre la session Windows de l'utilisateur du poste lit les données. Protégez la session (mot de passe Windows, verrouillage).

🛑 Clé perdue, données illisibles. Sauvegardez la clé (« Paramètres système », « Sauvegarder la clé de chiffrement ») et rangez le fichier `.cle` et la phrase séparément. Un poste remplacé réimporte la clé avant tout.

### 5.1 Vérifier le chiffrement sous Windows (procédure à exécuter par vous)

Ces vérifications n'ont JAMAIS été exécutées sur Windows par l'auteur de cette page. Faites-les sur un poste de recette, jamais sur une mère en service.

1. Installez le poste (4.1 et 4.2), lancez-le, créez un administrateur, saisissez quelques données de démonstration, fermez l'application.
2. Ouvrez `%LOCALAPPDATA%\SIGHCNT\donnees` (PowerShell : `explorer $env:LOCALAPPDATA\SIGHCNT\donnees`). Vous devez voir `cle-poste.bin`, `magasin\`, `poste.db`, et `mere.db` sur une mère.
3. Aucun fichier du magasin ne doit se lire en clair :

```powershell
cd $env:LOCALAPPDATA\SIGHCNT\donnees
Get-ChildItem magasin | Select-Object -First 3 | ForEach-Object { Get-Content $_.FullName -TotalCount 1 }   # du binaire illisible, pas du JSON
Select-String -Path magasin\* -Pattern "demonstration|patient" -SimpleMatch -List                           # aucune ligne attendue
Format-Hex poste.db -Count 16                                                                                 # NE doit PAS commencer par « SQLite format 3 »
```

4. `cle-poste.bin` n'est pas une clé brute : c'est une valeur protégée par DPAPI (texte base64). Copiez le dossier entier sur un AUTRE PC ou sous un AUTRE compte Windows : l'application doit refuser de lire (clé non déchiffrable), sans rien écraser.
5. Exportez la clé (« Sauvegarder la clé de chiffrement », phrase de 12 caractères), supprimez `cle-poste.bin` sur un poste de recette, importez la clé : l'application doit rouvrir les données. Avec une mauvaise phrase : refus nommé.
6. Lancement en développement sans chiffrement : `--dart-define=SIGH_CHIFFREMENT=non`. Réservé au développement, jamais en production.

> **Non vérifié ici** : DPAPI, `%LOCALAPPDATA%`, PowerShell, SQLite3 Multiple Ciphers sous Windows et le comportement sur un autre compte n'ont pas été exécutés (pas de Windows). Les chemins et les en-têtes viennent des commentaires et du code. Les tests Dart du chiffrement (`apps/poste/test/chiffrement_et_jeu_test.dart`) tournent sous Linux, où la clé n'est pas protégée par DPAPI. Le démarrage automatique (service Windows) n'est pas fait (écart E8).

---

## 6. Parcours de recette (acceptation) sur un vrai poste Windows

But : une personne de la clinique, sans développeur, constate que le poste fait ce que chaque métier attend. Durée : une demi-journée. À jouer sur un poste de recette (mère) et un second poste (fileul), avec le relais de recette, jamais sur la mère en service. Les comptes et les données sont ceux de la démonstration.

Règle : chaque ligne se coche « conforme » ou « écart » avec une capture. Un écart se note, il n'est pas corrigé sur place. Une ligne non jouée se dit « non jouée ».

**Avant les rôles (administrateur)**

- [ ] Installation de la mère puis du fileul (4.1, 4.2), appairage par code à 8 caractères.
- [ ] Les vérifications de chiffrement de 5.1.
- [ ] Mettre la mère hors réseau : le poste continue de travailler. Rebrancher : la synchronisation reprend.
- [ ] Sauvegarde de la clé de chiffrement faite et rangée.
- [ ] Identité imprimée : le RCCM affiché est `NAT/2021/M02-020` (version 2, effet 16/11/2026) ; l'ancien numéro reste sur les pièces datées d'avant. Sur un poste déjà installé avant le lot IDENT-MIG, la migration automatique au démarrage pose la version 2 sans écraser la version 1. Sur un fileul rattaché, rien ne migre : l'identité vient de la mère.

**Scénarios par rôle** (identifiants de `packages/rbac/data/rbac.json` ; adaptez aux comptes réellement créés)

| Rôle | À exécuter | Résultat attendu |
|---|---|---|
| Réception (`reception`) | Créer un patient, imprimer la carte | Code `CNT/[n°]/[année]` unique, non modifiable ; carte CR80 sans IFU ni RCCM |
| Médecin (`medecin`) | Ouvrir un dossier, prescrire un acte sans prix connu | La prescription est acceptée ; la ligne dit « prix à définir » ou « à valoriser », jamais 0 |
| Caissier (`caissier`) | Encaisser une pièce dont le prix est connu, puis une pièce avec un prix manquant | La première est encaissée avec facture (MECeF selon le mode réglé) ; la seconde est refusée avec un motif nommé, commande absente |
| Pharmacien et Gestionnaire de stock (`stock`) | Délivrer un produit, tenter de sortir plus que le stock | Sortie rattachée à un justificatif, FEFO ; le stock ne devient jamais négatif (RG-03) |
| Biologiste médical (`laborantin`) | Saisir un résultat hors bornes | Alerte nommée ; une borne « à valider » reste marquée tant que le professionnel ne l'a pas validée |
| Infirmier / Sage-femme (`infirmier`), Surveillant (`surveillant`) | Admettre un patient sur un lit déjà occupé ; préparer une sortie avec solde non apuré | Refus nommés (un lit, une admission active ; RG-06 à RG-08) |
| Comptable (`comptable`), Assistant Comptable (`aide_comptable`) | Passer une écriture déséquilibrée ; exporter un tableau | Refus (RG-10) ; l'export n'existe que pour le profil qui en a le geste réservé `exporter_donnees` |
| DAF (`da`) | Valider une commande de stock gros | Seul le geste réservé `valider_commande_stock` permet la validation (RG-04) ; sur un fileul, la décision est signée et appliquée par la mère |
| Direction (`direction`) | Régler un paramètre daté (par exemple le préavis de péremption) ; consulter l'état de la caisse | Valeur datée, journalisée ; « Non calculable » plutôt que zéro quand une source manque |
| Administrateur (`admin`) | Créer un compte, retirer un geste réservé à un rôle, se connecter avec ce rôle | La commande est ABSENTE (jamais grisée) et le moteur refuse aussi ; chaque action est au journal (RG-12) |
| Mère, SMS (`cfg-sms`, `m13-sms-journal`) | Régler la passerelle, envoyer un SMS de test avec de vrais identifiants posés sur le relais | Envoi, ligne au journal avec numéro masqué et sans texte ; sans identifiants : refus nommé, aucun envoi |
| Mère, satisfaction | Activer `satisfaction.enLigne`, publier un lien, répondre depuis un navigateur | La réponse apparaît à la mère après relevé ; une réponse avec un champ d'identité est refusée |

**Fin de recette**

- [ ] Mère arrêtée, fileul rebranché : message clair, aucune perte de saisie.
- [ ] Sauvegarde puis restauration dans un dossier neuf (4.6) vérifiée.
- [ ] Journal d'audit : aucune action anonyme.
- [ ] Écarts consignés, un par ligne, avec rôle, écran, capture.

> **Non vérifié ici** : ce parcours est un MINIMUM proposé par cette page à partir des règles de gestion (`CLAUDE.md`) et des lots listés. Il n'a pas été joué sur Windows. Les résultats attendus décrivent les règles du dépôt ; les libellés exacts des écrans peuvent différer. La liste des scénarios n'a pas été validée par la Direction : elle est une proposition à valider. Le déroulé complet d'une recette contractuelle (cahier des charges, M1 à M14) reste à rédiger.

---

## 7. Pièges à ne pas réapprendre

- Régénérez la safelist AVANT la CSS (`npm run build` le fait dans le bon ordre). `gen-safelist.js` retire les commentaires : une apostrophe isolée dans un commentaire JS fait disparaître des classes.
- Écrire des fichiers par un script Python sous Windows les passe en CRLF : utilisez Node ou l'outil d'édition.
- `pkill -f <motif>` peut tuer son propre shell si le motif figure dans sa ligne de commande.
- Un `rapport-tests.json` modifié n'est pas un travail : restaurez-le.
- Toute modification de forme de la maquette incrémente `VERSION` dans `prototype_html/assets/js/store.js` (un seul endroit), sinon les postes gardent l'ancien jeu.
- Les pièges de test appris au dernier passage complet (horloge du jour, `extraire.js`, `APP_BASE_PATH`, `tests/Unit`, `construire.sh`, test fragile sous charge) sont en 3.1.
- `flutter run` sous Windows : fermez l'application et tout `flutter_tester` avant `flutter build windows`, un `sqlite3.dll` verrouillé fait échouer la construction.

## 8. Récapitulatif de ce qui n'est pas vérifié

- Aucune commande de test, de banc ou de déploiement n'a été exécutée pour écrire cette page (consigne). Seules des lectures de scripts et des commandes légères ont servi.
- Les durées sont celles du `CLAUDE.md`, non remesurées.
- Windows (`build_windows.bat`, installateur, `/VERYSILENT`), DPAPI et le chiffrement des bases, le relais en ligne, deux machines réelles et la charge ne sont pas vérifiés.
- La passerelle SMS (variables `RELAIS_SMS_*`, commande `relais:sms-envoyer`, routes `/sms/*`) et la satisfaction en ligne (`/s/{jeton}`) existent dans `apps/web` au 17/11/2026, relues dans le code. Aucun envoi réel, aucun relais en ligne essayé.
- Les adresses de messagerie du dépôt sont celles de `sighcnt.nassieratoo.com` ; le serveur de l'hébergeur n'a pas été interrogé.
- Les chiffres de 3.8 sont rapportés d'une session de vérification, non remesurés ici ; `APP_BASE_PATH` n'a pas été essayé.
- Le chiffrement au repos (DPAPI, SQLite3 Multiple Ciphers) et la recette de la section 6 ne sont pas vérifiés sous Windows.
- Les guides `LANCER-EN-LOCAL.md`, `GUIDE-LANCEMENT-LOCAL.md` et `GUIDE-DEMARRAGE.md` datent d'octobre et de novembre 2026 et ne mentionnent ni `relais:surveiller` ni `relais:exporter` dans leurs sections de déploiement : cette page est plus à jour sur ce point.
