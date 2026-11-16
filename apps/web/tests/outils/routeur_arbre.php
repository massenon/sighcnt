<?php

/*
| Routeur du serveur intégré de PHP pour un ARBRE DE TRAVAIL dont `vendor` est un lien (voir `amorce_arbre.php`) : le serveur intégré n'applique pas `auto_prepend_file`, l'amorce est donc
| chargée ici. Usage : cd public && php -S 127.0.0.1:PORT -t . ../tests/outils/routeur_arbre.php
*/
require __DIR__.'/amorce_arbre.php';
$racine = dirname(__DIR__, 2);
$fichier = $racine.'/public'.parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if (php_sapi_name() === 'cli-server' && is_file($fichier)) {
    return false;
}
$_SERVER['SCRIPT_FILENAME'] = $racine.'/public/index.php';
require $racine.'/public/index.php';
