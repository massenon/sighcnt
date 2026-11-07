---
name: sigh-laravel
description: Conventions du relais en ligne SIGH-CNT (apps/web, Laravel 12 + Livewire sur cPanel mutualisé) — rôle opaque, contraintes d'hébergement, tests PHPUnit, panneau superadmin. Utiliser pour toute modification sous apps/web.
---

# SIGH-CNT — relais Laravel (apps/web)

Charger d'abord `sigh-maitre`.

## Ce que le relais est — et n'est pas

**Opaque.** Il stocke des enveloppes chiffrées de bout en bout (il ne voit que appareil, sens, rang, taille), des **indicateurs sans nom de patient**, le battement de cœur de la mère. **Aucune clé, aucune règle de gestion, aucun écran métier.** Un test (`test_le_relais_ne_contient_aucun_chiffrement_ni_cle`) interdit tout appel de chiffrement dans le contrôleur : ne pas le contourner.

Contrat : `packages/sync/banc/relais.js` (référence) ; le code Laravel doit passer **les mêmes scénarios** (`SIGH_RELAIS=laravel`).

## Contraintes d'hébergement (ADR-0005)

PHP ≥ 8.2 · PostgreSQL · **pas de SSH, pas de Redis, pas de WebSocket, pas de npm** · `cron` chaque minute. Donc : files et sessions en base ; panneau sans compilation d'actifs (CSS statique, Livewire servi par le paquet) ; commandes ponctuelles par cron à usage unique ; `vendor/` construit sur le poste de développement et téléversé. Guide : `docs/guides/DEPLOIEMENT-CPANEL.md`.

## Règles de code

- **L'autorisation précède la validation** : un appareil non autorisé reçoit le même refus quelle que soit la forme de son corps.
- Jetons et codes **hachés** (sha256) ; comparaison `hash_equals`.
- Routes du contrat dans `routes/relais.php` (sans session ni CSRF) ; panneau dans `routes/web.php` (auth + `throttle:6,1` sur la connexion).
- Crochets d'essai `banc/*` : fermés sauf `RELAIS_BANC=true`, jamais en production (404).
- Tout changement d'état d'administration est **journalisé** (`relais_audit`, RG-12) ; le journal ne contient aucune donnée de santé.
- Langue : français (libellés, messages, journal). Date affichée en `Africa/Porto-Novo`.

## Commandes

```bash
cd apps/web && composer install && php artisan test                       # 23 tests (SQLite) ; refaire avec DB_CONNECTION=pgsql
DB_CONNECTION=pgsql DB_DATABASE=relais_test … php artisan test             # le même, sur PostgreSQL
php artisan relais:superadmin dg@exemple.bj --mot-de-passe='…'             # compte du panneau (12 caractères minimum)
npm run banc:cible   # (racine) pile entière : mère Dart + postes Dart + mobile Dart + CE relais
```
