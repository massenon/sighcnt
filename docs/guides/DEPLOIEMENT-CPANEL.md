# Déployer le relais sur un cPanel mutualisé (sans SSH)

Application : `apps/web` (Laravel 12 + Livewire). Contraintes (ADR-0005) : PHP ≥ 8.2, PostgreSQL, `cron` chaque minute, **pas de SSH, pas de Redis, pas de WebSocket, pas de `npm`**. Le panneau n'utilise aucune ressource externe ni compilation d'actifs.

> Le relais est **opaque** : il stocke des enveloppes chiffrées de bout en bout et des indicateurs sans nom de patient. Il ne détient **aucune clé**. Même compromis, il ne livre pas de dossier — mais il porte l'accès aux boîtes des mobiles : protégez-le comme un serveur de santé (HTTPS obligatoire, mot de passe long, secret de la mère long).

## 1. Préparer le dossier sur le poste de développement

```bash
cd apps/web
composer install --no-dev --optimize-autoloader      # produit vendor/ (cPanel n'a ni Composer ni SSH)
php artisan key:generate --show                        # copier la valeur dans APP_KEY du .env de production
```

Téléverser **tout le dossier `apps/web`** (Gestionnaire de fichiers cPanel, ou « Git™ Version Control » si l'hébergeur le propose) **hors** de `public_html` — par exemple `~/sigh-relais/` — puis faire pointer le **domaine (ou le sous-domaine) vers `~/sigh-relais/public`**. Ne jamais exposer le reste du dossier : il contient `.env`, `vendor/` et le code.

## 2. Base PostgreSQL et configuration

1. cPanel → *PostgreSQL Databases* : créer la base, l'utilisateur, accorder tous les privilèges.
2. Copier `production.env.exemple` en `.env` à la racine du dossier téléversé et le renseigner (base, `APP_KEY`, `RELAIS_SECRET_MERE`).
3. Vérifier que PHP est en 8.2 ou plus (*MultiPHP Manager*) et que les extensions `pdo_pgsql`, `mbstring`, `openssl`, `ctype`, `json` sont actives (*Select PHP Version*).
4. Droits d'écriture : `storage/` et `bootstrap/cache/` en 755 (775 si l'hébergeur l'exige).

## 3. Commandes ponctuelles : par `cron`, pas par terminal

Sans SSH, une commande Artisan se lance par une **tâche cron à usage unique** (cPanel → *Cron Jobs* ; régler l'heure à la minute suivante, puis **supprimer la tâche**) :

| Besoin | Commande (chemin PHP : `/usr/local/bin/php`, ou `ea-php82`) |
|---|---|
| Créer les tables | `cd ~/sigh-relais && /usr/local/bin/php artisan migrate --force` |
| Créer le compte superadmin | `cd ~/sigh-relais && /usr/local/bin/php artisan relais:superadmin dg@exemple.bj --mot-de-passe='…12 caractères au moins…'` |
| Vider les caches après mise à jour | `cd ~/sigh-relais && /usr/local/bin/php artisan optimize:clear` |

**Sauvegarde automatique avant chaque migration** : exporter la base (*phpPgAdmin* ou `pg_dump` via cron) avant de lancer `migrate`. Après la création du compte, effacer la ligne de cron qui contient le mot de passe.

## 4. Tâche récurrente

Une seule tâche permanente, chaque minute :

```
* * * * * cd ~/sigh-relais && /usr/local/bin/php artisan schedule:run >> /dev/null 2>&1
```

(Rien n'est planifié aujourd'hui côté relais ; la ligne est posée pour les tâches à venir — rétention des enveloppes, rappels FCM.)

## 5. Brancher la mère

Sur la console de la mère (`apps/poste`, mode mère) : adresse du relais (`https://relais.exemple.bj`) et **le même** `RELAIS_SECRET_MERE`. Le relais n'appelle jamais la mère (elle est derrière le routeur de la clinique) : c'est elle qui vient relever, toutes les 10 à 15 secondes. Contrôle : le **tableau de bord** du panneau doit afficher « Poste mère · En ligne » ; sinon, le seuil est de 5 minutes.

## 6. Contrôles avant mise en service

- [ ] `https://relais…/panneau` redirige vers la connexion ; l'accueil `/` aussi ; aucune autre page publique.
- [ ] `https://relais…/.env` et `…/vendor/autoload.php` renvoient **404** (racine web = `public/`).
- [ ] `RELAIS_BANC=false` (les crochets d'altération des enveloppes sont fermés).
- [ ] `APP_DEBUG=false`, HTTPS forcé (cookie `Secure`).
- [ ] `php artisan route:list` ne montre aucune route `banc/*` accessible (elles répondent 404 sans `RELAIS_BANC`).
- [ ] Une sauvegarde chiffrée de la base du relais est planifiée (sa perte ne perd pas les données de la clinique, qui vivent sur la mère, mais perdrait les boîtes des mobiles non relevées).
- [ ] La **clé de clinique** n'est ni sur le relais, ni dans ce dépôt : copie papier sous scellé chez la Direction (à désigner nommément — voir `SPEC-protocole-synchronisation` Q2).

## 7. Mise à jour

Recommencer l'étape 1 avec le nouveau code, téléverser en écrasant (en conservant `.env` et `storage/`), lancer `migrate --force` par cron à usage unique, puis `optimize:clear`.

## Commandes d'exploitation du relais (30/10/2026)

| Commande | Rôle |
|---|---|
| `php artisan relais:statut` | volumes (appareils, enveloppes par sens, Ko, dernier battement) — aucun contenu, tout est chiffré |
| `php artisan relais:purger` | **simulation** de la purge de l'audit (365 jours par défaut, 30 minimum) ; `--oui` applique. Planifiée chaque jour à 03:10 par `schedule:run` |

**Les enveloppes ne se purgent jamais depuis le relais** : le journal chiffré sert à restaurer la mère, et retirer une enveloppe d'une boîte crée un trou que la mère traite comme une altération. La rétention des enveloppes se règle côté mère. Le secret de la mère se fait tourner en changeant `RELAIS_SECRET_MERE` dans `.env` puis dans la configuration de la mère ; les jetons d'appareil se renouvellent seuls (spec, SYNC-R18).
