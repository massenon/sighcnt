# PLAN : Passerelle SMS (Vonage et Twilio) et test d'envoi

Statut : **proposé le 07/11/2026**, à lancer après validation des décisions Q1 à Q8 du PRD (`docs/prd/PRD-SMS-passerelle-et-test-envoi.md`). Décisions du 07/11/2026 : Twilio par défaut, Vonage disponible, couverture du Bénin déclarée par la Direction, gardes conservées ; bibliothèques déjà installées (relais et maquette). La vérification de couverture et d'expéditeur devient une vérification de confort en recette, non bloquante.
Méthode : maquette d'abord, puis vecteurs, domaine Dart, relais, poste. Un agent Sonnet par étape, brief court, relecture par le responsable pour l'**argent** (coût, plafond) et les **droits** (secrets, consentement). Banc isolé (`SIGH_PORT_PHP`, `SIGH_BASE_TEST`, `SIGH_PORT_TEST` distincts, piège E2263). Un seul passage complet en fin de série.

## Vue d'ensemble

| Étape | Livrable | Où | Preuve |
|---|---|---|---|
| S0 | Décisions Q1 à Q8, vérification de la couverture Bénin | Direction, fournisseurs | réponses écrites |
| S1 | Passerelle SMS de la maquette : API, puits de test, écran, Test SMS, journal | `prototype_html` | scénario Vague 85, mutations |
| S2 | Moteur : consentement, plafond, heures calmes, matrice relue, rappels et anniversaires | maquette + `parcours.js` | scénario Vague 86 |
| S3 | Vecteurs et domaine Dart (règles pures) | `packages/domaine` | `dart test` |
| S4 | Relais : section « Passerelle SMS » du panneau, envoi, secrets chiffrés, PHPUnit | `apps/web` | `php artisan test` |
| S5 | Poste : `cfg-sms`, `m13-sms-journal`, file avec reprise, consentement au dossier | `apps/poste` | parité N1 100 %, tests d'écran |
| S6 | Intégration : de bout en bout contre le puits, puis recette avec un vrai compte | tous | recette sur site |

## S0. Décisions et vérification (sans code)
- Obtenir les réponses Q1 à Q8.
- Vérification de confort chez Vonage et Twilio (non bloquante, la Direction a déclaré la couverture) : couverture du Bénin, coût par message, expéditeur alphanumérique accepté ou non, procédure d'enregistrement éventuelle auprès des opérateurs, délai. **Rien de ce qui précède n'est établi dans le dépôt** : ne rien inventer, marquer « à confirmer » dans l'écran tant que non confirmé.
- Sortie : ce document mis à jour, ADR courte si le relais n'est pas le seul point d'envoi.

## S1. Maquette : passerelle, puits, écran, test, journal
Fichiers : `api/sms.php` (nouveau, calqué sur `api/smtp.php`), `api/sms_client.php` (fournisseurs Vonage et Twilio, appel HTTPS par cURL, un adaptateur par fournisseur), `api/sms.cle.local.php` et `api/sms.local.php` (ignorés par git, exemple fourni, chiffrement comme `smtp.cle.local.php`), `assets/js/modules/configuration.js` (écran `cfg-sms` : formulaire en cartes, champs propres au fournisseur choisi, interrupteur, **Test SMS** en modale), `assets/js/modules/m13-administration.js` (journal `m13-sms-journal`, filtres avancés, export), `assets/js/nav.js` (deux entrées, droits de la section 7 du PRD), `assets/js/store.js` (`VERSION` 70, collections `reglagesSms`, `messagesSms`, `consentementsSms` dans `LIBELLES`), `api/schema/` régénéré (`gen-schema-pg.js`).
Règles : secret jamais relu (réponse « enregistré » seulement) ; refus nommés (liste du PRD, P0 n° 2) ; **puits de test** `api/banc.php` étendu pour simuler le fournisseur (succès, identifiants refusés, solde insuffisant, injoignable) ; commande absente sans droit ; texte d'écran sans tiret cadratin.
Vérifs : `node --check`, `php -l`, `npm run build` (pages, safelist, CSS), scénario **Vague 85** (PRD section 8, points 1 à 5, 9) avec au moins 6 mutations des protections ; `ECARTS-MAQUETTE.md` mis à jour.

## S2. Moteur : consentement, limites, déclencheurs
Fichiers : `parcours.js` (`PR.envoyerSms(motif, destinataire, texte)` fabrique UNIQUE, appelée par tous les déclencheurs ; contrôle consentement, plafond, heures calmes, absence de donnée médicale ; écrit le journal), `notifications.js` (lit `notifications.matrice`, corrigeant l'écart signalé en E2278), `configuration.js` (`cfg-rappels` : envoi à l'échéance, consentement), `m1-patients.js` (champ de consentement SMS du patient et de l'agent, daté, retirable, RG-12).
Vérifs : scénario **Vague 86** (PRD section 8, points 6 à 8 et 10) avec mutations ; audit RBAC : `reception` ne voit rien de la configuration.

## S3. Vecteurs et domaine Dart
Fichiers : `prototype_html/build/vecteurs-sms.js` (capture depuis l'écran réel : refus nommés, masquage du numéro, plafond, heures calmes, mot médical, consentement), `packages/domaine/lib/src/sms/` (règles pures), `packages/domaine/test/vecteurs/sms.json`, `packages/domaine/test/sms_test.dart`.
Vérifs : `dart analyze`, `dart test` (rejoue les vecteurs).

## S4. Relais (Laravel)
Fichiers : `app/Http/Controllers/SmsController.php` (réglage, enregistrement, test, envoi), `routes/web.php` (panneau, calqué sur `/smtp`), `routes/relais.php` (`POST /sms/envoyer`, appareil authentifié, débit limité), migration `reglages_sms` (secrets chiffrés par la clé d'application, jamais rendus), vue Blade de la section « Passerelle SMS » avec Test SMS, `tests/Feature/SmsTest.php`.
Règles : le relais ne contient aucune règle métier (consentement et heures calmes décidés par le poste, plafond et refus fournisseur rendus par le relais) ; secret jamais dans une réponse, un journal, une sauvegarde ; 401 sans appareil, 429 au-delà du débit.
Vérifs : `php artisan test`, curl de chaque refus.

## S5. Poste (Flutter)
Fichiers : `lib/modules/cfg/cfg_sms.dart` (écran, formulaire et Test SMS), `lib/modules/m13/sms_journal.dart`, `lib/sync/service_sms.dart` et `file_sms.dart` (calqués sur `service_smtp.dart` et `file_courriels.dart` : envoi direct d'abord, file persistée avec reprise, identifiant de message stable), consentement au dossier patient, branchement de `cfb_notifications.dart` et `cfa_rappels.dart`, `registre.dart` et manifeste, fiches d'écran `docs/architecture/ecrans/cfg-sms.json` (extraites **sous l'horloge du 30/10/2026**, écart E2284), `parite-statuts.json` (statut « porté » refusé tant que N1 < 100 %).
Vérifs : `flutter analyze`, tests d'écran, parité N1, un seul `flutter test` complet en fin de série.

## S6. Intégration et recette
- Banc de bout en bout contre le puits (maquette, relais, poste), y compris la coupure puis le retour (un seul envoi).
- Recette avec un vrai compte Vonage ou Twilio sur le site de la clinique : identifiants saisis dans le panneau, jamais dans le dépôt ; test vers un numéro de la Direction ; **première semaine en plafond bas**.
- `GUIDE-LANCEMENT-LOCAL.md` : section SMS ; `CLAUDE.md` : paragraphe de vague.

## Risques de régression
- `cfg-notifications` change de portée (la matrice devient exécutoire) : relire les trois alertes cochées par défaut et vérifier qu'aucun envoi ne part sans passerelle active.
- `VERSION` 70 : les fiches RBAC et les collections semées se réamorcent ; mesurer le quota du magasin avant d'ajouter des collections (leçon de la vague 64).
- Fiches d'écran : extraction sous l'horloge fixe, sinon dérive du mois et des compteurs (écart E2284).
- `reception` : ne doit voir ni la configuration ni le journal (audit RBAC à rejouer).

## Hors plan
Réponses entrantes, campagnes, rapports de livraison par webhook (P1), autres fournisseurs (P2).
