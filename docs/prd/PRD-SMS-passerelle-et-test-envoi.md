# PRD : Passerelle SMS (Vonage ex-Nexmo et Twilio) et test d'envoi (maquette, poste, relais)

Statut : **proposé le 07/11/2026** à la demande de la Direction (« un module, écran ou section de formulaire Passerelle SMS, avec Nexmo et Twilio, et un module Test SMS »). Les décisions de la section 9 sont à valider avant le premier code.
Sources : relevés dans le dépôt le 07/11/2026 (`configuration.js` ~2081 et ~4094, `cfb_notifications.dart`, `cfa_rappels.dart`, `api/smtp.php`, `apps/web` panneau SMTP, `file_courriels.dart`) ; décisions de la Direction du 06/11/2026 sur le courriel ; doctrine de `CLAUDE.md` (notifications : aucune donnée médicale dans un message ; une restriction s'annonce ; hors ligne d'abord).
Règle de rédaction : pas de tiret cadratin comme ponctuation. Doctrine : maquette d'abord, puis vecteurs, domaine Dart, poste, relais.

## 1. Problème

**Ce qui existe (relevé le 07/11/2026).**

- Au prototype comme au poste, l'écran `cfg-notifications` porte une matrice « application, SMS, courriel » par type d'alerte. Ce sont des **préférences** : le moteur d'alertes ne les relit pas, et aucune passerelle ne les exécuterait.
- `cfg-rappels` porte les modèles de message (anniversaire du patient, nouvel an, fêtes, rendez-vous) et les rappels à échéance. Ils sont **composés et mis en file, jamais envoyés** ; l'écran le dit.
- Le courriel, lui, est réel : `api/smtp.php` (maquette), panneau SMTP du relais avec test d'envoi, file du poste avec reprise.
- **Aucun** élément ne configure ni n'exécute un SMS : ni fournisseur, ni identifiant d'expéditeur, ni clé, ni test, ni journal d'envoi, ni consentement du destinataire.

**Ce qui manque.** Une passerelle SMS réglable, testable, qui envoie vraiment, dont le journal est lisible et dont les déclencheurs (événements, notifications, rappels, souhaits d'anniversaire) lisent enfin la matrice des canaux.

## 2. Objectifs

- **O1.** Un écran **« Passerelle SMS »** (maquette, poste) et une section équivalente au panneau du relais : choix du fournisseur (**Vonage** ou **Twilio**), identifiants, expéditeur, plafonds, heures calmes, activation. Critère : un administrateur configure et active la passerelle sans toucher un fichier.
- **O2.** Un **Test SMS** : envoi d'un message de contrôle à un numéro saisi, avec le résultat NOMMÉ (accepté par le fournisseur, refusé, étape en échec) et l'identifiant du message. Critère : un identifiant faux donne un refus nommé, jamais un succès.
- **O3.** **Les secrets ne sont ni dans le dépôt, ni relus à l'écran, ni dans le journal** (même doctrine que le mot de passe SMTP). Ils vivent sur le relais, chiffrés ; le poste et le mobile ne les connaissent jamais.
- **O4.** Un **journal des envois** (qui, quand, motif, état, fournisseur), sans le texte médical ni le numéro en clair au-delà des quatre derniers chiffres.
- **O5.** Les **déclencheurs lisent la matrice** : une alerte dont la case SMS est cochée envoie un SMS aux destinataires concernés ; les rappels et les souhaits d'anniversaire envoient à l'échéance, avec consentement.
- **O6.** **Hors ligne** : un poste sans Internet met le message en file avec reprise ; il ne prétend jamais l'avoir envoyé.

## 3. Hors périmètre de la v1

- Réception de SMS (réponses des patients), conversation, campagnes de masse.
- Plus de deux fournisseurs (l'interface est faite pour en ajouter).
- Envoi depuis le mobile (le mobile passe par le relais ou par la mère).
- Rapports de livraison poussés par webhook vers le poste (le relais seul est joignable : voir section 6).

## 4. Utilisateurs

| Profil | Besoin |
|---|---|
| Administrateur système, DA | configure la passerelle, active, teste, lit le journal |
| Direction | lit le journal et les plafonds |
| Réception | déclenche (sans le savoir) les rappels de rendez-vous ; ne voit ni clé ni configuration |
| Patient, agent | reçoit ; son consentement est enregistré et retirable |

## 5. Exigences

**P0 (la v1 ne sort pas sans)**

1. **Écran de configuration** (ouvert aux seuls `admin` et `da`, lecture pour `direction`) : fournisseur (liste fermée Vonage, Twilio), champs propres à chaque fournisseur (Vonage : clé API et secret, ou application et clé privée ; Twilio : Account SID et jeton d'authentification, ou clé API ; numéro expéditeur ou Messaging Service SID), identifiant d'expéditeur alphanumérique si le pays l'autorise, plafond par jour, heures calmes, interrupteur d'activation. Les champs secrets s'affichent **« enregistré »** sans jamais rendre la valeur.
2. **Test SMS** : numéro au format international (E.164, `+229…`), message court imposé, bouton absent sans droit, **refus nommés** par étape (`SMS_NON_CONFIGUREE`, `NUMERO_INVALIDE`, `IDENTIFIANTS_REFUSES`, `EXPEDITEUR_NON_AUTORISE`, `SOLDE_INSUFFISANT`, `PLAFOND_ATTEINT`, `FOURNISSEUR_INJOIGNABLE`) avec le geste qui corrige.
3. **Envoi par le relais** : le relais tient les secrets, parle au fournisseur et rend l'état ; le poste lui demande l'envoi (appareil authentifié, comme pour le courriel du coffre). Aucun secret ne descend au poste ni au mobile.
4. **File avec reprise** au poste : envoi direct d'abord, file persistée avec reprises seulement en cas d'échec ; identifiant de message stable (pas de doublon à la reprise).
5. **Consentement** : champ de consentement SMS sur le patient et sur l'agent (daté, retirable, journalisé RG-12) ; sans consentement, aucun SMS d'anniversaire ni de relance n'est envoyé, et l'écran le dit. Les alertes internes vers le personnel suivent leur propre règle (numéro professionnel renseigné).
6. **Aucune donnée médicale** dans un SMS : ni diagnostic, ni résultat, ni motif de venue. Un modèle qui en contient est refusé à l'enregistrement.
7. **Journal des envois** (`messagesSms`) : lecture seule, filtres avancés (période, motif, état, destinataire masqué), export ; corbeille RG-14 (archivage, jamais suppression).
8. **La matrice est relue** : `cfg-notifications` écrit un réglage que le moteur d'alertes consulte ; une case décochée n'envoie pas.
9. **Plafond et heures calmes** respectés au moteur (refus nommé `PLAFOND_ATTEINT`, report à la fin des heures calmes pour les rappels non urgents).

**P1**

- Rapport de livraison (état final remonté par webhook au relais, affiché au journal).
- Gabarits par langue et variables contrôlées (`{{nom}}`, `{{clinique}}`, `{{date}}`).
- Solde du compte lu chez le fournisseur et alerte sous un seuil.

**P2**

- Autres fournisseurs, réponses entrantes, campagnes.

## 6. Contraintes d'architecture

- **Seul le relais est joignable depuis Internet** (cPanel mutualisé) : il porte les secrets, l'appel au fournisseur et, plus tard, le webhook de livraison. Le poste n'ouvre aucun port.
- **Le prototype ne peut pas appeler un vrai fournisseur sans clé** : comme pour le SMTP, il utilise un **puits de test local** (faux fournisseur HTTP) pour le banc, et un vrai fournisseur seulement quand l'administrateur saisit ses identifiants.
- **Identifiants chiffrés au repos** sur le relais (même mécanisme que `smtp.cle.local`) ; jamais dans une réponse, un journal ou une sauvegarde en clair.
- **Données minimales** : le relais reçoit numéro, texte final et motif ; il ne reçoit jamais un dossier.
- **Famille de fusion** : la configuration (non secrète) est de la famille R (mère seule, vers les fileuls, jamais vers les mobiles : RG-13) ; le journal des envois est de la famille B (journal).
- `VERSION` du prototype passe à 70 (collections semées : `reglagesSms`, `messagesSms`, `consentementsSms`).

## 7. Droits (RBAC)

| Écran | admin | da | direction | autres |
|---|---|---|---|---|
| `cfg-sms` (configuration et test) | écrit | écrit | lit | fermé |
| `m13-sms-journal` (journal des envois) | lit | lit | lit | fermé |
| Consentement SMS d'un patient | (écran du dossier) | | | selon le droit d'éditer le dossier |

Une commande interdite est **absente**, jamais grisée. L'écran dit pourquoi il est en lecture seule.

## 8. Sondes et critères d'acceptation

Scénario « Vague 85 » (maquette), avec mutations des protections :

1. Sans configuration : le test rend `SMS_NON_CONFIGUREE`.
2. Avec le puits de test : un envoi réussit, l'identifiant de message est écrit au journal, le numéro est masqué.
3. Identifiants refusés par le puits : refus nommé, rien de « envoyé » au journal.
4. Un secret saisi n'est relu nulle part (réponse API, collection, journal, export de base).
5. Numéro invalide, plafond atteint, heures calmes : refus ou report nommés.
6. Un modèle contenant un mot de la liste médicale est refusé.
7. Sans consentement : l'anniversaire n'est pas envoyé et le dit ; avec consentement : envoyé ; retrait : plus d'envoi.
8. Case SMS décochée dans la matrice : aucun envoi ; cochée : un envoi par destinataire.
9. Droits : `reception` ne voit ni l'écran ni le bouton ; `direction` lit sans modifier.
10. Hors ligne : le message est en file et le dit ; au retour, un seul envoi (pas de doublon).

Au poste : parité N1 à 100 % de `cfg-sms`, tests d'écran, file avec reprise. Au relais : tests PHPUnit (secrets jamais rendus, droits de l'appareil, refus nommés).

## 9. Décisions de la Direction du 07/11/2026 (reçues) et décisions restantes

**Reçues.** Fournisseur par défaut : **Twilio**, avec **Vonage** disponible. **Couverture du Bénin pour les deux : déclarée par la Direction** (non vérifiée par l'équipe : une vérification de confort reste prévue en recette, non bloquante). **Toutes les gardes sont conservées** : consentement, plafond, heures calmes, aucune donnée médicale, refus nommés, secrets jamais relus. **Bibliothèques installées le 07/11/2026** : `twilio/sdk` 8.14 et `vonage/client` 4.4 (relais : `apps/web/composer.json` et `composer.lock` versionnés ; maquette : `prototype_html/api/composer.json`, `vendor/` non versionné, repli sur l'appel REST direct par cURL si `vendor/` est absent ; le poste n'appelle jamais un fournisseur donc n'embarque aucune bibliothèque). Les sept avis de sécurité que `composer audit` signale concernent des composants Symfony **déjà présents** avant cet ajout, aucune bibliothèque nouvelle n'en porte ; mise à jour à traiter à part.

**Secrets (décision du 07/11/2026)** : les clés Twilio (SID et jeton) et Vonage (clé et secret) se renseignent dans le fichier `.env` du relais (`RELAIS_SMS_TWILIO_SID`, `RELAIS_SMS_TWILIO_TOKEN`, `RELAIS_SMS_VONAGE_KEY`, `RELAIS_SMS_VONAGE_SECRET`, `RELAIS_SMS_FOURNISSEUR=twilio`), jamais dans le panneau ni dans le dépôt ; le panneau montre « défini dans .env » et porte le **Test SMS** ; secret absent : refus nommé `SECRET_NON_DEFINI`. Le mot de passe SMTP suit la même règle (à valider : il était saisi au panneau jusqu'ici).

**Restantes** (Q2 devient une vérification de confort, les autres restent à valider).

| # | Question | Proposition |
|---|---|---|
| Q1 | Quels comptes fournisseur la clinique possède-t-elle (Vonage, Twilio, les deux) ? Qui les ouvre et les approvisionne ? | un compte par fournisseur au nom de la clinique ; la DA gère le solde |
| Q2 | Le pays de destination (Bénin, `+229`) est-il couvert par ces deux fournisseurs, et l'**identifiant d'expéditeur alphanumérique** est-il accepté ou faut-il un numéro ou un enregistrement auprès des opérateurs ? | **à vérifier auprès des fournisseurs avant tout code** (aucun document du dépôt ne le dit) ; la v1 accepte un numéro expéditeur |
| Q3 | Quels événements envoient un SMS par défaut ? | uniquement les trois déjà cochés à la maquette (rupture de stock, résultat disponible pour le prescripteur, échec de sauvegarde) ; le reste à l'initiative de la Direction |
| Q4 | Les **souhaits d'anniversaire** exigent-ils le consentement préalable du patient ? | oui, case de consentement datée, retirable |
| Q5 | Plafond quotidien et heures calmes par défaut ? | 200 messages par jour ; calme de 21 h à 7 h pour tout ce qui n'est pas une alerte technique |
| Q6 | Qui est joint par un SMS interne : tout le personnel ou les seuls rôles du type d'alerte ? | les rôles du type d'alerte, sur leur numéro professionnel |
| Q7 | Le texte des rappels de rendez-vous peut-il nommer le médecin et l'heure ? | oui, jamais le motif |
| Q8 | Conservation du journal des envois | 12 mois, puis archivage (RG-14) |

## 10. Risques

- **Réglementaire** : le traitement de numéros de téléphone et les messages de souhaits relèvent de la protection des données ; le consentement et la minimisation sont des exigences, pas des options. À faire relire par la Direction.
- **Délivrabilité** : identifiants d'expéditeur non acceptés sur certains opérateurs ; un envoi « accepté » par le fournisseur n'est pas un message reçu (d'où le rapport de livraison en P1).
- **Coût** : chaque message se paie ; les plafonds et le solde sont des garde-fous, pas un détail.
- **Fournisseur injoignable** : la file avec reprise est la règle ; un échec n'est jamais présenté comme un succès.
