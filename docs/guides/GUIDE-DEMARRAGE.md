# Guide — cloner, tester, mettre à jour, repartir d'une base propre

Public : le développeur ou l'exploitant qui reprend le dépôt `sighcnt` sur un poste neuf.
Tout ce qui suit concerne le **prototype** (`prototype_html/`, PHP + PostgreSQL), qui est
aujourd'hui le seul exécutable : l'application cible (`apps/poste`, `apps/hub`) n'est pas encore
portée (voir [`architecture/adr/ADR-0003`](../architecture/adr/ADR-0003-stack-poste-hub-mobile.md)).

Les commandes sont données pour Linux ; sous Windows, les mêmes `npm run …` fonctionnent, seules
les lignes `psql`, `service` et `export` changent de syntaxe.

---

## 1. Prérequis

| Outil | Version | Pourquoi |
|---|---|---|
| Node.js | ≥ 22 | outillage, bancs d'essai, générateurs |
| PHP | ≥ 8.1, extension **`pdo_pgsql`** | pages `.php` et API (`api/`) |
| PostgreSQL | 14 ou plus (16 recommandé) | le magasin et les tables de module |
| Chrome ou Chromium | récent | `check`, `test`, `audit-rbac` pilotent un vrai navigateur (`CHROME_PATH` pour le désigner) |

Vérifier : `node -v && php -v && php -m | grep pdo_pgsql && psql --version`.

## 2. Cloner et installer

```bash
git clone https://github.com/massenon/sighcnt.git
cd sighcnt
npm install                      # monorepo (workspaces)
npm run prototype:install        # dépendances du prototype (Tailwind, Puppeteer)
```

> `node_modules` n'est jamais versionné. Si l'installation a été faite sous un autre système
> d'exploitation, la supprimer et recommencer : les binaires ne sont pas portables
> (`npx tailwindcss` échoue sinon ; contournement :
> `node node_modules/tailwindcss/lib/cli.js -i src/input.css -o assets/css/tailwind.css --minify`).

## 3. Créer la base et le fichier de configuration

```bash
psql -U postgres -c "CREATE DATABASE sigh_prototype;"
cp prototype_html/api/config.local.exemple.php prototype_html/api/config.local.php
# éditer config.local.php : dsn, user, pass
```

- La base du prototype est **`sigh_prototype`**. `sigh_cnt` appartient à la cible : le prototype
  n'y écrit jamais.
- `config.local.php` est **ignoré par git** et ne doit jamais être commis (mot de passe).
  Le mot de passe PostgreSQL commis par erreur le 17/10/2026 dans l'historique du commit initial
  doit être **changé sur le poste** ; il reste lisible dans l'historique.
- Le schéma se crée seul (`sigh_installer`) et les comptes se sèment au premier appel de
  `api/auth.php`. Aucun import n'est obligatoire pour démarrer.

## 4. Démarrer

```bash
npm run prototype:serveur        # depuis la racine ; http://127.0.0.1:8080/index.php
```

(ou `npm run serveur` depuis `prototype_html/`, port en argument : `node build/serveur.js 9000`).

- Le **premier** accès sème le magasin (jeu de démonstration, version de schéma courante).
- Comptes de démonstration : identifiants de la table `utilisateurs` (`c.bassongui`, `e.orouyo`,
  `a.dieyabidi`…) ; mot de passe d'origine **`demonstration`**, changement exigé à la première
  connexion. C'est un jeu de démonstration, pas un paramétrage de production.
- Sans serveur (double-clic sur `index.php`, serveur statique), le prototype **retombe sur le
  stockage du navigateur** : tout fonctionne, mais un seul poste, avec le plafond de quota.
- Plusieurs postes : ouvrir la même adresse depuis deux machines (ou deux profils de navigateur) —
  ils voient le même magasin ; la pastille de synchronisation du bandeau le dit.

## 5. Tester

Depuis `prototype_html/` (ou `npm run prototype:<nom>` depuis la racine) :

| Commande | Ce qu'elle prouve | Attendu au 21/10/2026 |
|---|---|---|
| `npm run lint` | syntaxe de toutes les sources JS | 0 erreur |
| `npm run build` | pages, safelist Tailwind, CSS | pages engendrées sans erreur |
| `npm run check` | ouvre chaque page dans Chrome : erreurs JS, liens, ressources | 306 pages conformes |
| `npm run test` | parcours fonctionnels de bout en bout | 74/74 scénarios, 1 185 vérifications |
| `npm run audit-rbac` | chaque écran sous chaque profil : commandes offertes vs droits réels | 0 promesse, 0 lecture non dite |
| `npm run verify` | lint + build + check + test | tout vert |

À savoir avant de lancer un banc :

1. **PostgreSQL doit tourner** (`service postgresql start`) : sinon 503 « base indisponible » et
   sondes sans objet. Il s'arrête à chaque redémarrage d'un conteneur.
2. Les bancs travaillent sur une **base jetable** (`sigh_prototype_test` par défaut, variable
   `SIGH_BASE_TEST`) : le nom doit contenir `test`, `essai` ou `banc`, faute de quoi la remise à
   zéro est refusée. La base de travail n'est **jamais** touchée par un test.
3. Plusieurs bancs en parallèle exigent des ports et des bases distincts :
   `SIGH_PORT_TEST`, `SIGH_PORT_PHP`, `SIGH_BASE_TEST`.
4. **Ne pas modifier `api/` pendant qu'un banc tourne** : le serveur PHP relit les fichiers à
   chaque requête et le banc mesurerait un état intermédiaire.
5. Sous-ensemble : `node build/check.js --pages=m6-,m8-`.
6. Un échec « page non peinte » : regarder d'abord le **statut HTTP** (adresse inexistante = 404)
   avant d'accuser l'hydratation.

## 6. Mettre à jour (récupérer le travail des autres)

```bash
git fetch origin
git switch claude/sighcnt-monorepo-offline-first-i0v3v9      # ou la branche de travail du moment
git pull --ff-only origin claude/sighcnt-monorepo-offline-first-i0v3v9
npm install && npm run prototype:install                      # si package*.json a changé
cd prototype_html && npm run build                            # pages + safelist + CSS
```

Puis, selon ce que la mise à jour a changé :

| Changement | Geste |
|---|---|
| `VERSION` du schéma incrémentée (`assets/js/store.js`, constante unique) | **rien** : au premier accès le magasin se ré-amorce sur la nouvelle version. Les écritures faites **depuis** l'ancienne version ne sont pas migrées — sauvegarder avant (§7) si la base contient autre chose que de la démonstration |
| nouvelle collection | régénérer les tables : `psql -At -c "select json_object_agg(nom, donnees) from collections" > magasin.json && node build/gen-schema-pg.js magasin.json`, puis `php api/projection.php` ; sans cela la collection est **nommée** dans `projection_erreurs` et le magasin continue de fonctionner |
| nouvel écran | `npm run pages` (le manifeste `nav.js` est la source unique des liens) |
| nouveau fichier dans `api/planificateur/` | relancer l'installeur (rejouable) |

Vérifier ensuite : `npm run verify` (ou au moins `check` + `test`).

**Production (poste de la clinique)** : ne jamais `git pull` sur un poste en service sans avoir
sauvegardé (§7) et sans avoir lu `RELEASE-<version>.md` s'il existe.

## 7. Sauvegarder

- **Automatique** : le planificateur écrit `api/sauvegardes/magasin-AAAA-MM-JJ.json.gz`
  (7 derniers jours). Installer la tâche système :
  `sh api/planificateur/installer-linux.sh` (Linux) ou
  `.\api\planificateur\installer-windows.ps1 -Racine <dossier> -Php <php.exe>` (Windows, PowerShell
  administrateur). Essai à blanc : `php api/cron.php --force`. Un planificateur arrêté se voit à
  l'écran **Tâches planifiées** (M14).
- **Complète** : `pg_dump -U postgres --clean --if-exists --no-owner --no-privileges sigh_prototype > sigh_prototype.sql`.
  Elle porte aussi les comptes et les sessions. Les exports `*.sql` ne sont **jamais versionnés**.

## 8. Repartir d'une base propre

Quatre niveaux, du plus doux au plus radical. Choisir le plus doux qui suffit.

### 8.1. Vider les données de test, garder le paramétrage (depuis l'application)

Deux portes vers le même vidage : le bouton **Réinitialiser le jeu de données** (bloc « Maintenance du prototype » des paramètres) et l'onglet **Jeux de test** de **Paramètres système**. La bascule de réinitialisation est **fermée par
défaut** (le bouton est absent tant qu'elle n'est pas ouverte). Le vidage retire l'activité
(patients, factures, écritures, files…) et **conserve** le paramétrage : tarifs, secteurs,
conventions, comptes, droits (matrice RBAC), modules actifs, catalogues du laboratoire et de
l'imagerie, barèmes, modèles. Il est journalisé (RG-12) et ne tient que si les écrans ne
ré-amorcent pas leur collection : le drapeau `_jeuVide` y veille.

### 8.2. Régénérer le jeu de démonstration

Onglet **Jeux de test**, action « Régénérer le jeu de démonstration complet » : le magasin repart du jeu daté de démonstration, version
courante. Les comptes sont conservés.

### 8.3. Base entièrement neuve

```bash
psql -U postgres -c "DROP DATABASE IF EXISTS sigh_prototype;"
psql -U postgres -c "CREATE DATABASE sigh_prototype;"
npm run prototype:serveur        # le premier accès recrée les tables, sème le magasin et les 17 comptes
```

Puis recharger tous les postes ouverts. C'est le geste à faire après une montée de version
douteuse, **jamais** sur une base qui porte autre chose que de la démonstration sans sauvegarde.

### 8.4. Retour à un état connu (restauration)

```bash
cd prototype_html
php api/restaurer.php api/sauvegardes/magasin-2026-10-21.json.gz          # simulation : affiche, ne modifie rien
php api/restaurer.php api/sauvegardes/magasin-2026-10-21.json.gz --oui    # remplace le magasin
```

- Remplace **toutes** les collections et la méta ; **ne touche pas** aux comptes ni aux sessions
  (la sauvegarde ne les porte pas). Recharger les postes ensuite.
- L'état précédent est conservé avant d'être écrasé (`api/sauvegardes/avant-restauration-<date>.json.gz`) :
  une restauration à la mauvaise date se rattrape. Ces fichiers ne sont pas purgés automatiquement.
- Les tables de module sont reconstruites et la parité contrôlée à la fin.
- Pour restaurer un export complet : `psql -U postgres -d sigh_prototype -f sigh_prototype.sql`
  (il porte `DROP … IF EXISTS` et peut être rejoué).

### 8.5. Repartir proprement de la copie de travail

```bash
git status                       # ce qui n'est pas commis
git stash -u                     # le mettre de côté, ou : git restore . && git clean -fdn (simulation)
git fetch origin && git switch -C <branche> origin/<branche>
```

Ne jamais `git clean -fd` sans `-n` d'abord : `api/config.local.php` et `node_modules` sont ignorés
(ils ne sont pas touchés sans `-x`), mais des fichiers de travail non commis le sont.

## 9. Pièges rencontrés (à ne pas réapprendre)

- Régénérer la **safelist avant la CSS** (`npm run build` le fait dans le bon ordre).
- Une **apostrophe française isolée dans un commentaire JS** désynchronise `gen-safelist.js`.
- Écrire des fichiers par un script Python sous Windows les passe en CRLF : utiliser Node ou
  l'outil d'édition.
- `node -e "…"` mange les échappements de classes Tailwind : passer par un fichier.
- `pkill -f <motif>` peut tuer son propre shell si le motif figure dans la ligne de commande.
- Un port déjà occupé (`EADDRINUSE`) = un banc précédent resté vivant : tuer son PID.

## 10. Où lire la suite

- Index des documents : [`../README.md`](../README.md)
- Architecture cible et ADR : [`../architecture/README.md`](../architecture/README.md)
- Synchronisation entre postes, hub et mobile :
  [`../prd/PRD-SOCLE-synchronisation-bidirectionnelle.md`](../prd/PRD-SOCLE-synchronisation-bidirectionnelle.md) et
  [`../plans/PLAN-synchronisation-bidirectionnelle.md`](../plans/PLAN-synchronisation-bidirectionnelle.md)
- Doctrine, règles de gestion RG-01→14 et pièges : `CLAUDE.md` à la racine.
