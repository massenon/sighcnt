# ADR-0008 : Passerelle SMS tenue par le relais avec un cron, exception bornée à « relais opaque »

Statut : **accepté le 16/11/2026** par la Direction (`docs/decisions/DECISIONS-A-VALIDER.md` section AQ points 13, 27 et 28). Il **déroge** à « le relais ne lit rien » **pour la seule passerelle SMS**, comme l'ADR-0007 l'a fait pour la seule sauvegarde.
Date : 2026-11-16
Concerne : relais (apps/web), poste mère, sécurité, vie privée, hébergement.

## Contexte

Pour envoyer un SMS, la passerelle d'un fournisseur (Twilio, Vonage) doit lire le numéro et le texte. Seul le relais est joignable depuis Internet (cPanel, ADR-0005) et seul il peut tenir une tâche planifiée à la minute. Le poste mère calcule les envois (rappel la veille d'un rendez-vous, vœux d'anniversaire des patients et du personnel) mais n'ouvre aucun port et peut être éteint à l'heure d'envoi. Sans exception, aucun SMS automatique ne partirait de façon fiable.

## Options examinées

1. **La mère appelle le fournisseur directement.** Aucune exception, mais l'envoi dépend de l'allumage du poste mère à l'heure dite, et les identifiants du fournisseur descendent sur un poste de la clinique. Écartée par la Direction (« le relais web prend ce module en charge avec un cron »).
2. **Le relais reçoit l'annuaire et calcule lui-même.** Écartée : il lirait noms, dates de naissance, rendez-vous. C'est le renversement complet de l'opacité.
3. **La mère calcule et dépose des messages DÉJÀ COMPOSÉS ; le relais les garde planifiés et les envoie** (retenue). Le relais voit le strict nécessaire, le temps de l'envoi.

## Décision

1. **Ce que le relais voit** : le numéro (E.164), le texte final (320 caractères au plus), l'heure d'envoi, le type (`rappel_rdv`, `anniversaire_patient`, `anniversaire_personnel`, `test`) et un **identifiant opaque** : l'HMAC-SHA256 de la clé de clinique sur une clé naturelle de l'envoi, calculé à la mère (64 caractères hexadécimaux). La clé de clinique n'est jamais envoyée : le relais ne peut ni défaire l'identifiant ni le relier à une personne ou à un rendez-vous. Un identifiant qui n'a pas cette forme (un code de patient, un numéro de rendez-vous) est **refusé** (`IDENTIFIANT_NON_OPAQUE`).
2. **Ce que le relais ne voit jamais** : l'annuaire, une date de naissance, un code patient ou de dossier, un rendez-vous, le médecin, le service, le motif, une donnée de santé. Les modèles de message ne contiennent que les variables `{{nom}} {{date}} {{heure}} {{clinique}} {{telephone}}` ; un rappel ne nomme jamais le médecin, le service ni le motif ; la règle est appliquée à la mère, qui compose (une seule source : le relais ne porte aucune règle métier, ni consentement, ni heures calmes, ni liste de mots).
3. **Effacement du clair** : dès qu'un message est dans un état final (envoyé, refusé, retiré), le numéro et le texte sont **effacés** de la base ; il reste l'identifiant opaque, l'heure, le type, l'état, le code, les quatre derniers chiffres du numéro et l'identifiant du fournisseur. Le journal rendu à la mère et au panneau ne porte jamais le clair.
4. **Famille de routes `/sms/*` réservée à la mère** (en-tête `x-mere`) : `etat`, `deposer`, `annuler`, `tester`, `journal`. Un appareil appairé (téléphone, fileul) reçoit **403 `sms_reserve_mere`** ; sans identité, 403 `mere_requise`.
5. **Idempotence** : un identifiant déjà connu n'est jamais redéposé (un message retiré peut être replanifié, un message parti ou refusé jamais). La mère peut redéposer toute l'heure sans doublon.
6. **Retrait** : un rendez-vous annulé ou déplacé, un consentement retiré, un numéro corrigé retire l'envoi planifié (`/sms/annuler`). **Un envoi parti ne se retire pas** : la réponse le dit (`deja_parti`).
7. **Envoi** : tâche planifiée `relais:sms-envoyer` chaque minute, sans chevauchement. Plafond du jour compté à l'**heure du Bénin** (défaut 200, en base) : un message bloqué par le plafond est **refusé** (`PLAFOND_ATTEINT`), **pas reporté** au lendemain. Fournisseur injoignable : **5 tentatives** (en base), puis refus (`FOURNISSEUR_INJOIGNABLE`). Un message resté planifié trop longtemps après son heure (défaut 3 heures, **proposition à valider**) n'est plus envoyé (`HEURE_DEPASSEE`) : un rappel de la veille ne part pas le lendemain.
8. **Fournisseurs** par leurs bibliothèques officielles (`twilio/sdk`, `vonage/client`), dont le transport HTTP est celui de Laravel, remplaçable par un faux dans les tests : aucun envoi réel hors recette. Les **identifiants** sont dans le `.env` du relais (`RELAIS_SMS_*`), jamais en base, jamais rendus ; le panneau dit « défini » ou « non défini ».
9. **Réglages en base** (plafond, tentatives, délai entre tentatives, péremption, conservation du journal : 12 mois), semés, bornés, journalisés au panneau superadmin. Les réglages de clinique côté mère (heure du rappel 18 h la veille, heure des vœux 9 h, heures calmes, modèles, activation) restent à la mère, jamais vers un téléphone.

## Conséquences

- Le relais détient des numéros et des textes **pendant la fenêtre entre le dépôt et l'envoi** (au plus : de la veille 18 h au lendemain pour un rappel). C'est la contrepartie acceptée. Une fuite de la base pendant cette fenêtre exposerait des numéros et des messages (qui peuvent porter le prénom de la personne, variable `{{nom}}`) sans donnée de santé, sans code patient et sans rendez-vous autre que la date et l'heure d'un rappel.
- La passerelle ne dépend plus de l'allumage de la mère à l'heure d'envoi, mais dépend du cron du relais (surveillé par `relais:surveiller`).
- Un compte superadmin du relais peut lire les numéros des messages planifiés en base (pas au panneau, qui les masque). À reconnaître dans le registre des accès.
- Non vérifié : couverture du Bénin, expéditeur alphanumérique, coût par message chez les deux fournisseurs (vérification de confort en recette, non bloquante) ; correspondance exacte des codes d'erreur de chaque fournisseur (relevée dans leurs bibliothèques, à confirmer avec un vrai compte).
