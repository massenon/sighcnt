<?php
/* =============================================================================
 * Modèle à recopier en `config.local.php` sur chaque poste.
 * -----------------------------------------------------------------------------
 * `config.local.php` porte les identifiants réels et n'est PAS versionné ;
 * ce modèle-ci l'est, pour que l'on sache quoi renseigner.
 *
 * MySQL       mysql:host=127.0.0.1;port=3306;dbname=sigh_prototype;charset=utf8mb4
 * PostgreSQL  pgsql:host=127.0.0.1;port=5432;dbname=sigh_prototype
 *
 * La base du prototype est `sigh_prototype`. `sigh_cnt` appartient à la CIBLE
 * (Laravel, 173 tables) : le prototype n'y écrit jamais.
 * ========================================================================== */

return [
    'dsn'  => 'pgsql:host=127.0.0.1;port=5432;dbname=sigh_prototype',
    'user' => 'postgres',
    'pass' => 'à renseigner',
];
