# Prototype HTML — SIGH-CNT

Prototype d'interface du **Système Intégré de Gestion Hospitalière** de la
CLINIQUE NASSIERA TOO SARL (Natitingou, Bénin), couvrant les quatorze modules
du Cahier des Charges Technique ainsi que les modules MECeF, Gestion
documentaire et Rapports.

## Ouvrir le prototype

Deux façons, et elles ne donnent pas la même chose.

### Avec la base de données — recommandé

```
npm run serveur        →  http://127.0.0.1:8080/index.php
```

Le magasin vit alors dans **PostgreSQL** (base `sigh_prototype`). Trois
conséquences, et la troisième est celle qui compte :

- plus de plafond de 5 Mo ;
- les données survivent au navigateur et se sauvegardent (`pg_dump`) ;
- **plusieurs postes voient le même magasin** — c’est cela, simuler une
  clinique, et le stockage par navigateur en est incapable.

Les identifiants se mettent dans `api/config.local.php` (non versionné) ;
`api/config.local.exemple.php` dit quoi y écrire. L’accès passe par PDO :
MySQL ne tient qu’à la ligne du DSN.

> La base du prototype est `sigh_prototype`. **`sigh_cnt` appartient à la
> cible** (`sigh_web/`, Laravel, 173 tables) : le prototype n’y écrit jamais.

### Sans rien installer

Double-cliquer sur **`index.php`**, ou servir le dossier avec n’importe quel
serveur statique. Tout fonctionne — le prototype **retombe sur le stockage du
navigateur** dès qu’il ne trouve pas son API. C’est ce repli qui préserve la
contrainte hors ligne.

> Ouvert par double-clic (protocole `file://`), Chrome refuse selon sa
> configuration l’accès au stockage local. Le prototype bascule alors sur un
> stockage en mémoire : tout reste fonctionnel, mais les saisies ne survivent
> pas au rechargement.

Le prototype s'ouvre sur l'écran de connexion. Le sélecteur **« Profil de
connexion »** ouvre la session avec le périmètre RBAC correspondant ; le menu
profil, en haut à droite, permet d'en changer à tout moment.

### Se déplacer dans l'application

La navigation est un **méga-menu horizontal en ruban**, dans l'esprit du ruban
de Microsoft Word : une rangée d'onglets correspondant aux domaines
fonctionnels, et sous elle un panneau qui déploie les modules du domaine
**une rangée par module**, chaque écran figurant en pastille avec son icône.

- Le panneau est **déployé par défaut** sur le domaine de l'écran affiché, où
  l'écran courant apparaît en surbrillance. Disposé en rangées, il occupe deux à
  trois hauteurs de texte au lieu du tiers de l'écran.
- Il **se replie de lui-même dès que l'on descend dans la page** : la lecture
  reprend le dessus sans un clic. Un clic sur l'onglet actif, sur le chevron de
  droite ou la touche Échap le replie également, et ce choix est mémorisé.
- L'intitulé d'un module ouvre sa **page d'accueil de module** : tous ses écrans
  y sont présentés en cartes (icône, titre, description). Le fil d'Ariane y
  ramène depuis n'importe quel écran, de sorte qu'on circule d'un écran à
  l'autre sans repasser par le menu.
- Quatre **raccourcis permanents** — Patients, Consultations, Pharmacie,
  Facturation — restent visibles même menu replié.
- Un compteur rouge signale les modules ayant des alertes en cours.
- La barre supérieure réunit la recherche globale (`Ctrl K`), les actions
  rapides, le **plein écran**, les notifications et le profil.

### Saisir sans faire défiler

Toute liste de plus de huit entrées s'ouvre en **liste déroulante à recherche** :
on tape « tchou » pour trouver le patient, « amox » pour l'article, « 601 » pour
le compte comptable. Chaque proposition porte son icône et une ligne de détail
— code dossier et couverture pour un patient, stock disponible et prix pour un
article, numéro pour un compte. La navigation au clavier (flèches, Entrée,
Échap) est complète.

### Consulter, puis corriger

Les fiches ne sont pas des impasses : partout où la donnée appartient à un
registre tenu par la clinique — dossier patient, feuille de soins, présences,
appels, événements, poches de sang, factures fournisseurs, tarifs — la
consultation propose **Modifier** et **Archiver**, avec journalisation (RG-12),
archivage logique (RG-14) et annulation immédiate.

Les écrans qui restent en lecture seule le sont **à dessein** et le disent :
grand livre, balance, analytique, état de caisse, créances, alertes de stock,
écarts de livraison, journal MECeF, journal d'audit et historique des éditions
sont des états calculés ou des preuves. Chacun indique où corriger la donnée
d'origine.

## Ce que contient le prototype

| Domaine | Modules | Écrans |
|---|---|---|
| Pilotage | Tableaux de bord par profil | 14 |
| Soins | M1 Patients · M2 RDV & consultations · M3 Hospitalisation · M4 Maternité · M5 Laboratoire | 32 |
| Logistique | M6 Pharmacie & stocks · M7 Achats | 19 |
| Financier | M8 Facturation · M9 Assurances · MECeF · M12 Comptabilité SYSCOHADA | 33 |
| Ressources humaines | M10 RH · M11 Paie | 19 |
| Administration | M13 Administration & ambulance · GED · Rapports | 12 |
| Système | M14 Sécurité · Configuration clinique | 13 |
| Accès | Connexion, récupération, double facteur, verrouillage, erreurs, plan du site | 8 |

**173 pages** au total : 151 écrans, 19 pages d'accueil de module, l'aide, le
contact éditeur et la page de connexion — toutes fonctionnelles.

### Aide et contact éditeur

Le menu profil, en haut à droite, ouvre deux écrans de documentation :

- **Aide & À propos** — présentation du logiciel, fiche d'identité (version,
  éditeur, IFU, RCCM), les dix-neuf modules en cartes (icône, intitulé, ce que
  fait le module) et une foire aux questions repliable, adossée aux règles de
  gestion.
- **Contactez l'éditeur** — envoi d'un message ou signalement d'anomalie
  (module concerné, description, étapes pour reproduire, capture d'écran).
  Chaque envoi reçoit une référence `SUP-2026-nnnn`, est journalisé et reste
  consultable sous les formulaires.

## Données réelles intégrées

Les référentiels sont transcrits des documents de cadrage, non inventés :

| Document | Ce qu'il devient | Écran |
|---|---|---|
| Organigramme | 44 agents, postes et titulaires ; pilote la matrice RBAC | `cfg-organisation` |
| NS 131/07/DM/DA/CNT/2026 | Barème d'évaluation et de sanction (4 critères, retenues 6/10/15 %) | `m10-evaluations` |
| NS 132/07/DM/DA/CNT/2026 | Grille des primes par fonction, aux montants exacts | `m10-primes` |
| Tarifs des analyses (48) | Catalogue de laboratoire | `m5-catalogue` |
| Tarifs des médicaments (144) | Catalogue tarifaire pharmacie | `cfg-tarifs` |
| Inventaire « Grand Stock » SAGE 100 | **184 articles**, 12 080 unités, 3 976 459 FCFA — stock initial | `m6-reprise` |
| Classeur comptable SYSCOHADA | **93 comptes** réellement tenus par la clinique | `m12-plan-comptable` |
| Compte de résultat 2025 | CA 190 830 994 · charges 160 264 063 · résultat 30 566 931 FCFA | `m12-baseline-2025` |
| Liste des assurances partenaires | 13 compagnies, téléphones et courriels | `m9-compagnies` |
| Plannings du personnel | **7 régimes de travail** distincts par catégorie | `m10-planning` |
| Liasse SoBAPS (pro-forma, BL, facture MECeF) | Structure fiscale et workflow d'achat | `mecef-factures`, `m7-receptions` |
| Entête officielle | BP 507, téléphones, autorisation, IFU, RCCM | `cfg-branding` |

L'inventaire et la comptabilité se **réconcilient exactement** avec leurs
documents source : 12 080 unités et 3 976 459 FCFA pour le stock, 190 830 994
FCFA de chiffre d'affaires 2025.

Les données transactionnelles (patients, consultations, factures, écritures)
restent un jeu de démonstration généré de façon déterministe.

### Anomalies relevées dans les documents source

Le prototype les expose plutôt que de les masquer :

- **Tarifs vierges** — les documents « Tarifs des analyses » et « Tarifs des
  médicaments » ne renseignent pas la colonne des prix. Les analyses portent des
  valeurs d'attente signalées ; les médicaments sont valorisés au CMUP de
  l'inventaire lorsqu'ils y figurent.
- **32 articles non valorisés** à l'inventaire SAGE : quantité connue, prix de
  revient absent (`m6-reprise`, onglet « Points à traiter »).
- **Seuils d'alerte absents** du document SAGE : le système propose 20 % de la
  quantité relevée, à arrêter article par article.
- **3 postes de dépense sans numéro de compte** dans le classeur 2025
  (taxe sur emprunt, fonds de garantie, frais de dossier — 3 281 118 FCFA).
- **Écart de 141 667 FCFA** entre la ligne « TOTAL » du classeur 2025 et la
  somme de son propre détail. Le détail ligne à ligne a été retenu.
- **Régime de TVA à confirmer** — sur la facture certifiée MECeF de référence,
  la TVA est portée à zéro (produits de santé exonérés) et le net à payer vaut
  le hors-taxes augmenté du seul AIB 1 %. Le prototype applique ce régime par
  défaut et le signale ; il se change dans `mecef-config`.
- **RCCM divergent selon les documents** : `RB/NAT/2016-B-268` sur la plupart
  des pièces, `RB/NAT/2021/M02-020` sur les plannings de septembre 2024.
  Le premier a été retenu.

### Régimes de travail relevés sur les plannings

| Catégorie | Vacations | Repos | Cycle |
|---|---|---|---|
| Médecins | Garde 24 h (08h→08h) | 48 h | 2 j |
| Infirmiers | Garde soins 08h–18h30 · Garde hospi 08h→08h | 48 h | 3 j |
| Sages-femmes | Garde 24 h | 24 h | 2 j |
| Aides-soignants | Garde 24 h | 48 h | 3 j |
| Secrétaires et caisse | Garde 24 h · Permanence 08h–18h | 24 h | 3 j |
| Agents d'entretien | Permanence (P) · Entretien général (EGJ) | — | 3 j |
| Agents de sécurité | Garde 24 h (G) · Soirée 18h–8h (S) | Repos (R) | 3 j |

## Développement

```bash
npm install          # Tailwind CLI et Puppeteer (contrôle automatisé)

npm run build        # génère les pages, la liste blanche et la feuille de style
npm run pages        # régénère les pages HTML depuis le manifeste de navigation
npm run safelist     # relève les classes produites dynamiquement en JavaScript
npm run compta       # régénère data-compta.js depuis les classeurs Excel du cadrage
npm run css          # compile Tailwind
npm run watch        # compile en continu

npm run lint         # contrôle syntaxique de toutes les sources JavaScript
npm run check        # ouvre chaque page dans Chrome : erreurs JS, liens, ressources
npm run test         # exécute les parcours fonctionnels de bout en bout
npm run verify       # lint + build + check + test
```

`npm run check` et `npm run test` pilotent le navigateur Chrome installé sur le
poste. Si celui-ci n'est pas détecté, renseigner la variable `CHROME_PATH`.

## Organisation des fichiers

```
prototype_html/
├── index.html                  écran de connexion
├── pages/                      172 pages, une par écran et par module du manifeste
├── assets/
│   ├── css/tailwind.css        feuille de style compilée
│   ├── img/logo.jpeg           logo de la clinique
│   └── js/
│       ├── vendor/             Chart.js et Lucide, vendorés localement
│       ├── core.js             formats FCFA et dates, constructeur d'éléments, identité
│       ├── data-compta.js      GÉNÉRÉ — plan comptable et compte de résultat 2025
│       ├── data-sage.js        inventaire SAGE 100 et catalogue tarifaire
│       ├── data.js             référentiels issus des documents de cadrage
│       ├── store.js            persistance, CRUD, archivage logique, journal d'audit
│       ├── ui.js               composants : tableaux, modales, tiroirs, messages
│       ├── charts.js           graphiques
│       ├── print.js            états officiels au papier à en-tête
│       ├── nav.js              manifeste de navigation — source unique des liens
│       ├── app.js              coquille : méga-menu RBAC, barre supérieure, montage
│       └── modules/            un fichier par module métier
├── fonts/                      Inter (woff2), vendorée localement
├── src/input.css               sources Tailwind et styles d'impression
└── build/                      scripts de génération et de contrôle
```

### Comment une page est construite

Chaque page HTML est un gabarit de dix lignes qui appelle `SIGH.mount('<id>')`.
La coquille, le méga-menu, le fil d'Ariane et les liens sont produits à
partir de **`assets/js/nav.js`**, seule source de vérité de la navigation : un
écran ajouté au manifeste puis `npm run pages` suffit à créer la page, et aucun
lien ne peut être cassé puisqu'aucun n'est écrit à la main.

Le contenu d'un écran est déclaré dans son module métier via
`SIGH.screen('<id>', { title, description, regle, actions, render })`. Les
écrans de gestion s'appuient sur `SIGH.kit.crud()`, qui fournit onglets, KPI,
tableau trié et filtré, création, édition, archivage annulable, duplication,
fiche détaillée et impression.

## Règles métier appliquées

Les quatorze règles du cahier des charges sont implémentées et signalées à
l'écran. Cinq d'entre elles sont vérifiées par les tests automatisés :

| Règle | Application |
|---|---|
| RG-01 | Code patient `CNT[n°]/[année]` attribué automatiquement, champ verrouillé |
| RG-02 | Prix de vente des médicaments égal au prix d'achat |
| RG-03 | Sortie de stock refusée si la quantité excède le disponible |
| RG-04 | Commande non transmissible sans validation de la Directrice Administrative |
| RG-05 | Classement FEFO et alertes de péremption à 90 jours |
| RG-06 | Sortie d'hospitalisation bloquée si le solde n'est pas apuré |
| RG-07 | Triple signature exigée : patient, infirmier, gardien |
| RG-08 | Sortie contre avis médical motivée, avis du Procureur consigné |
| RG-09 | Prise en charge refusée si la carte d'assurance est expirée |
| RG-10 | Validation d'écriture refusée tant que débit ≠ crédit |
| RG-11 | Primes calculées depuis le planning validé et la grille NS 132 |
| RG-12 | Journal d'audit alimenté par chaque mutation |
| RG-13 | Cloisonnement RBAC des données médicales, financières et RH |
| RG-14 | Archivage logique uniquement, avec restauration |

## États officiels

Tout document édité reprend automatiquement le papier à en-tête de la clinique
— double logo, dénomination, BP, téléphones, autorisation d'ouverture, IFU,
RCCM, courriel — et un pied de page normalisé portant l'utilisateur
générateur, la date et l'heure d'impression et un identifiant unique.

La prévisualisation s'affiche à l'écran ; le bouton **« Imprimer / Enregistrer
en PDF »** ouvre la boîte d'impression du navigateur, dont la destination
« Enregistrer au format PDF » produit le fichier. Le catalogue complet est
accessible depuis **Rapports & Impression → Bibliothèque des états**.

## Limites connues

- Les **tarifs des analyses et des médicaments** restent à fixer par la clinique
  (colonnes vierges dans les documents source).
- Les échanges **MECeF** sont simulés : la structure de la facture, le code
  DGI, le NIM, les compteurs et l'AIB reproduisent la facture certifiée de
  référence, mais l'interfaçage réel s'effectuera avec la machine électronique
  certifiée de facturation.
- Le **QR code fiscal** est représenté par un cadre : sa génération nécessitera
  les données réelles renvoyées par le dispositif.
- Ce prototype porte l'**interface et les règles de gestion**. La solution cible
  reste une application desktop .NET adossée à PostgreSQL, conformément au
  Cahier des Charges Technique §8.5.
