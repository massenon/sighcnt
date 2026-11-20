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

    // Lot 5 (ADR-0007) : le dossier des blocs opaques de la sauvegarde hors site (sur disque, jamais en base). Les limites (quota, etc.) sont EN BASE, réglables au panneau.
    'sauvegardes_dir' => env('RELAIS_SAUVEGARDES_DIR', storage_path('app/sauvegardes')),

    /*
    | Lot SMS-R (ADR-0008) : la passerelle SMS. Les IDENTIFIANTS du fournisseur ne vivent que dans le .env (RELAIS_SMS_*), jamais en base, jamais dans le dépôt, jamais rendus par une route ou par le panneau
    | (qui dit seulement « défini » ou « non défini »). Les limites (plafond du jour, tentatives, péremption, conservation) sont EN BASE (relais_meta, clés reglage.sms.*), réglables au panneau.
    */
    'sms' => [
        'fournisseur' => env('RELAIS_SMS_FOURNISSEUR', 'twilio'),
        'expediteur' => env('RELAIS_SMS_EXPEDITEUR', ''),
        'twilio_sid' => env('RELAIS_SMS_TWILIO_SID', ''),
        'twilio_token' => env('RELAIS_SMS_TWILIO_TOKEN', ''),
        'vonage_key' => env('RELAIS_SMS_VONAGE_KEY', ''),
        'vonage_secret' => env('RELAIS_SMS_VONAGE_SECRET', ''),
        // Jour du plafond : l'heure du Bénin.
        'fuseau' => env('RELAIS_SMS_FUSEAU', 'Africa/Porto-Novo'),
    ],

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
        // Lot RLS-SYNC : seuils réglés en base (écran Paramètres), pas ici.
        ['type' => 'fileul_silencieux', 'libelle' => 'Fileul silencieux', 'canal' => 'Panneau', 'active' => true],
        ['type' => 'mobile_silencieux', 'libelle' => 'Mobile silencieux', 'canal' => 'Panneau', 'active' => true],
        ['type' => 'boite_grossit', 'libelle' => 'Boîte aux lettres qui grossit', 'canal' => 'Panneau', 'active' => true],
    ],
];
