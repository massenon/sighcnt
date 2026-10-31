<?php

return [
    /*
    | Le RELAIS est opaque : il ne détient AUCUNE clé. Ce secret n'authentifie que la mère de la clinique auprès
    | du relais (déposer dans les boîtes, relever les enveloppes des mobiles, révoquer). À poser dans .env.
    */
    'secret_mere' => env('RELAIS_SECRET_MERE', ''),

    // Silence de la mère au-delà duquel le relais lève l'alerte « battement ». 5 minutes par défaut (spec §13).
    'seuil_battement_ms' => (int) env('RELAIS_SEUIL_BATTEMENT_MS', 300000),

    // Crochets réservés au banc d'essai (altérer / retirer une enveloppe). JAMAIS en production.
    'banc' => (bool) env('RELAIS_BANC', false),
];
