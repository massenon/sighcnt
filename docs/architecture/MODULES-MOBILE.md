# Modules du mobile — simulateur et pages de prototype

Prototype : `prototype_html/mobile/` (servi par `npm run serveur`, ouvrir `/mobile/index.php`). **Le simulateur montre le téléphone dans son cadre** — iPhone 14 (390 × 844, iOS 18) et Pixel 8 (412 × 880, Android 15), seuls ou côte à côte — avec le **même design system** que la maquette (jetons `docs/design/design-tokens.json` : navy, vert/orange/rouge, Inter, texte ≥ 11 pt).

Le mobile passe **uniquement par le relais** (jamais par le réseau local). Chaque écran fonctionne **hors ligne** : la saisie est visible aussitôt, part à la première occasion, et le bandeau dit toujours où l'on en est.

| Profil | Écrans propres |
|---|---|
| **Soignant (infirmier)** | Ma tournée · Dossier du patient · Constantes |
| **Médecin** | Mes visites · Consultation à domicile · Prescription · Demande d'analyses (+ dossier, constantes) |
| **Sage-femme** | Mes suivis · Visite prénatale (CPN) · Visite post-natale (CPoN) · Surveillance mère-bébé (+ dossier, constantes) |
| **Réception de secours** | Accueil de secours · Nouveau dossier · Dossiers ouverts · Orienter un patient |
| **Tous** | Appairage · Code PIN · Synchronisation · À traiter · Réglages · (Lot de tournée : profils cliniques) |

21 écrans, 4 profils — manifeste unique `mobile/manifeste.js` ; les pages `mobile/ecrans/*.php` sont **engendrées** (`node build/gen-mobile.js`, appelé par `npm run pages`).

## Règles que le prototype fait respecter (et que `npm run mobile:check` vérifie)

- **Un écran fermé à un profil se nomme**, il ne s'ouvre pas à moitié (la caisse n'est pas couverte par la réception de secours). Dans le simulateur, il reste visible mais grisé.
- **Une valeur improbable est refusée en la nommant** (température 57 °C, âge 200 ans…), sans écraser la saisie.
- **Un homonyme n'est pas refusé** : le dossier est ouvert et signalé « doublon possible » à la mère (RG-01 : le code ne change jamais).
- **Le numéro vient de la plage réservée au téléphone** ; plage épuisée → numéro **provisoire** `PROV-` réconcilié à l'arrivée.
- **Aucune donnée de santé dans une notification** ; le lot de tournée **expire** et s'efface du téléphone, sauf ce qui n'est pas parti.
- **Rien ne se prélève avant le paiement** : la demande d'analyses part, le patient règle à la caisse de la clinique.
- Dossier → fiche → prescription (même ordre que le poste de bureau).

## Ce que ce prototype n'est pas

Une maquette navigable, pas l'application : pas de coffre sécurisé, pas de biométrie, pas de notifications push réelles, pas de base chiffrée. L'application Flutter est `apps/mobile` ; ces pages en fixent le contenu et le comportement avant portage.
