<?php
/* =============================================================================
 * Identifiants du poste — CE FICHIER N'EST PAS VERSIONNÉ.
 * -----------------------------------------------------------------------------
 * Il est ignoré par git (voir .gitignore). Sur un autre poste, le recopier
 * depuis `config.local.exemple.php` et y mettre ses propres identifiants.
 *
 * La base est `sigh_prototype`, et JAMAIS `sigh_cnt` : cette dernière porte le
 * schéma de la cible (Laravel, 173 tables) et ne doit rien recevoir du
 * prototype.
 * ========================================================================== */

return [
    'dsn'  => 'pgsql:host=127.0.0.1;port=5432;dbname=sigh_prototype',
    'user' => 'postgres',
    'pass' => 'Rhodes_2026@@@',
];
