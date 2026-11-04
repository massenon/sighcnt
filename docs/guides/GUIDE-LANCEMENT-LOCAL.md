# Guide : cloner la branche et lancer en local (relais web, poste, mobile)

Branche : `claude/sighcnt-monorepo-offline-first-i0v3v9`. Les commandes sont données pour PowerShell (Windows) ; sous Linux, remplacer `Copy-Item` par `cp`.

## 0. Cloner

```powershell
git clone https://github.com/massenon/sighcnt.git
cd sighcnt
git checkout claude/sighcnt-monorepo-offline-first-i0v3v9
git pull origin claude/sighcnt-monorepo-offline-first-i0v3v9
```

Prérequis : Git, Flutter 3.47 (Dart 3.13) avec « Desktop Windows » activé (Visual Studio 2022, charge de travail « Développement Desktop en C++ »), PHP 8.2 ou plus avec `pdo_pgsql`, Composer, PostgreSQL 15 ou plus. Pour Android : Android Studio et un émulateur.

## 1. Relais web (apps/web)

```powershell
# PostgreSQL : créer la base du relais (psql -U postgres)
#   CREATE USER sigh_relais WITH PASSWORD 'choisir-un-mot-de-passe';
#   CREATE DATABASE sigh_relais OWNER sigh_relais;
cd apps\web
composer install
Copy-Item .env.example .env
# éditer .env : DB_PASSWORD=... et RELAIS_SECRET_MERE=<texte long aléatoire>
php artisan key:generate
php artisan migrate
php artisan relais:superadmin votre@courriel.bj --mot-de-passe='un-mot-de-passe-de-12-caracteres-au-moins'
php artisan serve --host=127.0.0.1 --port=8000
```

Relais : `http://127.0.0.1:8000`. Panneau superadmin : même adresse, avec le compte créé ci-dessus. Tests : `php artisan test` (SQLite en mémoire, aucune base nécessaire).

## 2. Poste (apps/poste)

```powershell
cd apps\poste
flutter pub get
flutter run -d windows
```

Variante de développement sans chiffrement : `flutter run -d windows --dart-define=SIGH_CHIFFREMENT=non`. Exécutable : `flutter build windows` (dossier `build\windows\x64\runner\Release`).

Premier démarrage : l'assistant s'ouvre.

1. **Poste mère** : créer le premier administrateur (mot de passe de 8 caractères au moins), noter le code de secours, puis dans la modale « Configurations à faire » choisir « Activer la mère » et renseigner : adresse du relais (`127.0.0.1:8000` en local, ou `sighcnt.nassieratoo.com`), secret de la mère (le même texte que `RELAIS_SECRET_MERE`), clé de clinique (16 caractères au moins, à ranger sur papier).
2. **Poste fileul** (une seconde machine, ou une seconde copie avec `--dart-define=SIGH_DONNEES=donnees-fileul2` pour ne pas partager le dossier de données) : « Rejoindre une clinique existante », avec l'adresse de la mère et le code d'appairage généré par la console de la mère.

La mère écoute par défaut sur `http://127.0.0.1:9000` ; un fileul sur la même machine la joint à cette adresse.

Tests : `flutter analyze` puis `flutter test`.

## 3. Domaine et moteur de synchronisation (sans interface)

```powershell
cd packages\domaine ; dart pub get ; dart test
cd ..\sync_dart    ; dart pub get ; dart test
```

## 4. Application mobile (apps/mobile)

Le mobile ne parle jamais au réseau local : il passe par le relais. Préparer d'abord le relais (§1) et la mère activée (§2), émettre un code d'appairage depuis la console de la mère, puis :

```powershell
cd apps\mobile
flutter pub get
flutter run -d <identifiant-émulateur> --dart-define=SIGH_RELAIS=http://10.0.2.2:8000
```

`10.0.2.2` est l'adresse de l'ordinateur vu depuis l'émulateur Android. Sur un téléphone réel, utiliser l'adresse du relais joignable depuis ce téléphone. Liste des appareils : `flutter devices`. Tests : `flutter analyze` puis `flutter test`.

## 5. Maquette (référence, PHP et PostgreSQL)

Voir `docs/guides/GUIDE-DEMARRAGE.md` (`npm install`, `npm run prototype:serveur`, port 8080).

## Ce qui n'est PAS vérifié ici

`flutter build windows` et la protection DPAPI de la clé n'ont pas été exécutés sur un vrai Windows ; le mobile n'a pas tourné sur un appareil Android ; la synchronisation n'a pas été mesurée sur deux postes physiques. Si une commande échoue, envoyer la sortie complète.
