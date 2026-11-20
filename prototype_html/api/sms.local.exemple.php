<?php
/* =============================================================================
 * Modèle de ce que `api/sms.local.php` contient, SANS valeur réelle.
 * -----------------------------------------------------------------------------
 * NE JAMAIS recopier ce modèle à la main : le fichier réel est écrit par le
 * panneau « Paramètres système, Passerelle SMS » (écran cfg-sms), qui chiffre les
 * identifiants du fournisseur (AES-256-GCM) avec la clé locale `sms.cle.local.php`
 * (tirée au sort au premier enregistrement). Les deux fichiers sont ignorés par git
 * (`*.local.php`) et commencent par une garde qui les fait taire s'ils sont
 * demandés par HTTP.
 *
 * Forme du contenu JSON (après la garde « <?php http_response_code(403); exit; ?> ») :
 *   {
 *     "fournisseur": "twilio",                 // ou "vonage"
 *     "actif": true,
 *     "expediteur": "+229XXXXXXXX",            // numéro E.164 ou identifiant alphanumérique (1 à 11 caractères)
 *     "serviceSid": "",                        // Twilio : Messaging Service SID (MG…) à la place de l'expéditeur
 *     "plafondJour": 200, "calmeDebut": 21, "calmeFin": 7,
 *     "sec": { "twilioSid": "<chiffré>", "twilioToken": "<chiffré>",
 *              "vonageCle": "<chiffré>", "vonageSecret": "<chiffré>" },
 *     "compteur": { "jour": "AAAA-MM-JJ", "n": 0 }
 *   }
 *
 * `SIGH_SMS_DIR` (variable d'environnement) déplace ces fichiers ailleurs que dans api/.
 * Les identifiants ne se mettent NI dans le dépôt NI dans `.env` : ils se saisissent au panneau.
 * ========================================================================== */

return [];
