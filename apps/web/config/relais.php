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

    // Conservation du journal d'audit (jours). Les enveloppes ne sont JAMAIS purgées par le relais.
    'retention_audit_jours' => (int) env('RELAIS_RETENTION_AUDIT_JOURS', 365),

    // Espace disque libre (en %) sous lequel l'alerte « disque » se lève.
    'seuil_disque_pct' => (int) env('RELAIS_SEUIL_DISQUE_PCT', 10),

    // Silence du cron (schedule:run) au-delà duquel l'alerte « cron » se lève.
    'seuil_cron_ms' => (int) env('RELAIS_SEUIL_CRON_MS', 300000),

    // Règles d'alerte du relais. Une alerte porte un type, une heure, un détail technique : jamais un contenu métier.
    'alertes' => [
        ['type' => 'battement', 'libelle' => 'Battement manquant', 'canal' => 'Courriel + panneau', 'active' => true],
        ['type' => 'appareil_bloque', 'libelle' => 'Appareil bloqué', 'canal' => 'Courriel + panneau', 'active' => true],
        ['type' => 'disque', 'libelle' => 'Espace disque faible', 'canal' => 'Courriel', 'active' => true],
        ['type' => 'cron', 'libelle' => 'Tâche cron non exécutée', 'canal' => 'Panneau', 'active' => true],
    ],
];
