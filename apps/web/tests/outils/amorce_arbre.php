<?php

/*
| Amorce d'un ARBRE DE TRAVAIL dont `vendor` est un lien vers un autre dépôt (lots menés en parallèle) : le chargeur de classes de `vendor` connaît le code de CET AUTRE dépôt
| (classmap et PSR-4). On l'amorce pour que `App\`, `Tests\` et `Database\` se chargent depuis l'arbre où ce fichier se trouve. Sans effet dans un dépôt dont `vendor` est le sien.
| Usage : php -d auto_prepend_file=tests/outils/amorce_arbre.php vendor/bin/phpunit --bootstrap tests/outils/amorce_arbre.php
*/
$racine = dirname(__DIR__, 2).'/';
$chargeur = require $racine.'vendor/autoload.php';
(function () {
    foreach (array_keys($this->classMap) as $k) {
        if (preg_match('/^(App|Tests|Database)\\\\/', $k)) {
            unset($this->classMap[$k]);
        }
    }
})->call($chargeur);
$chargeur->setPsr4('App\\', [$racine.'app/']);
$chargeur->setPsr4('Tests\\', [$racine.'tests/']);
$chargeur->setPsr4('Database\\Factories\\', [$racine.'database/factories/']);
$chargeur->setPsr4('Database\\Seeders\\', [$racine.'database/seeders/']);
