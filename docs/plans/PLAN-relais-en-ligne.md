# PLAN : Relais en ligne (consultation à règles complètes, configuration et journal conservés sans exception) et passerelle SMS

Statut : **proposé le 07/11/2026**. **Rien ne démarre avant la décision Q1** (option A ou B) du PRD `PRD-RELAIS-en-ligne-consultation-et-configuration.md`. Le plan suppose l'option A (recommandée) ; l'option B demande une ADR de renversement, un accord avec l'hébergeur et la réécriture des règles en PHP, donc un autre plan.
Méthode : un agent Sonnet par étape, brief court, relecture du responsable pour les **droits** et l'**argent** ; banc isolé (ports et base propres, piège E2263) ; une seule suite complète en fin de série ; fiches d'écran extraites sous l'horloge du 30/10/2026 (E2284).

## Étapes

| Étape | Livrable | Où | Preuve |
|---|---|---|---|
| R0 | Décisions Q1 à Q7 ; mesure de l'espace disque de l'hébergement | Direction, ingénierie | réponses écrites, relevé de quota |
| R1 | Banc des vecteurs du domaine compilé pour le web | `packages/domaine`, `apps/consultation` (squelette) | 323 vecteurs identiques au navigateur sans tête |
| R2 | Relais : sens `config`, archive froide, archivage et désarchivage, `GET /compteur` enrichi, conservation intégrale (la purge de compaction est retirée) | `apps/web` | `php artisan test`, sonde de conservation |
| R3 | Mère : publication à 5 s, instantané de configuration chaîné et versionné, instantané quotidien | `apps/poste/lib/sync`, `packages/sync_dart` | tests Dart, banc pair P1 à P7 |
| R4 | Restauration depuis le relais seul (console de la mère neuve) | poste, relais | sonde de restauration à empreinte identique, refus nommés |
| R5 | Client de consultation web : connexion, droits `rbac.json`, âge de la donnée, lecture seule, journal RG-12 | `apps/consultation` | parité N1 et N2, sonde RBAC |
| R6 | Passerelle SMS (voir `PLAN-sms-passerelle.md`) en parallèle de R2 à R4 : elle ne touche pas la consultation | maquette, relais, poste | scénarios Vague 85 et 86 |
| R7 | Recette sur site : hébergement réel, latence réelle, un consultant réel, mère détruite puis restaurée | site de la clinique | procès-verbal |

## R0. Décisions et mesures
- Réponses Q1 à Q7 du PRD ; **Q1 est bloquante**.
- Relever l'espace disque et la croissance attendue (enveloppes par jour d'activité) : « sans purge » est un engagement de stockage.
- Sortie : PRD mis à jour ; ADR si B.

## R1. Domaine sur le web (le risque principal d'abord)
Compiler `packages/domaine` pour le web et rejouer **tous** les vecteurs (`packages/domaine/test/vecteurs/*.json`) dans un navigateur sans tête. Si une règle ne se compile pas ou diverge : c'est le moment de le savoir, avant de promettre « 100 % ». Critère de sortie : zéro divergence, ou liste nommée des écarts à corriger au domaine.

## R2. Relais : conserver tout
Fichiers : migration des archives, `RelaisController` (sens `config`, `GET /releve?dir=`), commande d'archivage et de désarchivage (clé d'appareil de la mère), retrait de l'ordre « purger avant le rang N » de la compaction, tests (`tests/Feature/`). Le relais n'embarque aucune règle. Vérifs : `php artisan test`, curl de chaque refus, mesure d'entropie des enveloppes `config`.

## R3. Mère : publier en continu, instantané de configuration
Fichiers : `copie_mere.dart` (cadence 5 s, reprise), nouveau `instantane_config.dart` (périmètre de la spec section 3, chaîne d'empreintes), `pont_pair.dart`, collections du périmètre branchées sur le déclencheur. Vérifs : tests Dart, banc pair (P1 à P7), mutation : un instantané manquant rompt la chaîne et le dit.

## R4. Restauration
Console de la mère neuve : appairage de remplacement avec révocation motivée de l'ancienne ; rejeu de l'instantané puis des journaux de toutes les familles ; empreinte. Refus nommés : `CLE_INCORRECTE`, `RANG_MANQUANT`, `EMPREINTE_DIVERGENTE`, `MERE_ACTIVE`. Vérifs : sonde de bout en bout (mère détruite, mère neuve, état identique), quatre mutations.

## R5. Client web de consultation
Application Flutter web ou PWA (`apps/consultation`) : connexion nominative, clé en mémoire de l'onglet, droits par écran issus de `rbac.json`, collections hors droit **jamais reconstruites**, bandeau d'âge et état « source injoignable », sondage du compteur toutes les 5 s, aucune commande d'écriture. Fiches d'écran des écrans consultables et parité N1 à 100 % ; CSP sans script externe. Vérifs : sonde RBAC, sonde d'âge (mère arrêtée puis relancée), sonde d'opacité.

## R6. SMS en parallèle
Suivre `PLAN-sms-passerelle.md`. Décisions de la Direction du 07/11 : **Twilio par défaut**, Vonage en second, **couverture du Bénin déclarée par la Direction** (le plan garde une vérification de confort en recette, non bloquante), **toutes les gardes conservées** (consentement, plafond, heures calmes, aucune donnée médicale, refus nommés). Bibliothèques installées le 07/11/2026 : `twilio/sdk` 8.14 et `vonage/client` 4.4 (relais, `composer.lock` versionné) ; mêmes paquets dans `prototype_html/api/composer.json` (vendor non versionné, repli cURL sans dépendance).

## R7. Recette sur site
Hébergement réel, latence depuis le Bénin, un consultant réel, mère détruite volontairement puis restaurée depuis le relais seul ; mesure de l'espace consommé sur une semaine. Procès-verbal signé de la Direction.

## Risques de régression
- Retirer la compaction : la croissance du stockage n'est plus bornée ; surveiller.
- Cadence 5 s : charge de la mère et du relais mutualisé ; plafond et reprise testés.
- Le client web importe le domaine : toute règle modifiée change aussi la consultation (voulu, mais à rejouer).
- Aucun changement du protocole pour les mobiles : rejouer les bancs de synchronisation (P1 à P7).

## Hors plan
Écriture depuis le web (Q4, P2), consultation hors ligne (PWA avec cache chiffré, P2), option B.
