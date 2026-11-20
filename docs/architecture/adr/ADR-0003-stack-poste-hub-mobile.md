# ADR-0003 — Un seul langage, Dart : poste Windows/Linux et smartphone en Flutter, hub en Dart, règles métier partagées
Statut : **proposé** (21/10/2026) — à accepter par la Direction après le banc de validation (§ « Comment on vérifiera »)
Date : 2026-10-21
Concerne : poste, hub, mobile, synchronisation, MECeF, impression
Remplace, **pour la pile technique seulement** : le choix Tauri 2 / Node-TypeScript / réutilisation de l'interface JavaScript de `ARCHITECTURE-CIBLE.md` §4-§5 et la phrase « l'interface et les moteurs du prototype sont repris » d'ADR-0001. **Ne remplace pas** la décision d'architecture d'ADR-0001 (postes autonomes, hub en étoile, journal d'opérations) : elle est indépendante du langage.

## Contexte

La Direction a demandé (21/10/2026) de **repartir de zéro** sur la pile, « sans considérer le stack défini ». Les réponses données :

- **Systèmes** : postes Windows **et** Linux ;
- **Interface** : une seule base de code pour le poste et le **smartphone** ;
- **Panne du serveur de la clinique** : les postes continuent de travailler, puis **synchronisent** ;
- **Compétence de l'équipe** : **Flutter / Dart**.

Un fait nouveau, qui change l'architecture et pas seulement la pile : la clinique utilise **la machine MECeF physique** (le boîtier de facturation normalisée), et non le service en ligne e-MECeF que supposait `ARCHITECTURE-CIBLE.md` §8 (« la passerelle du hub soumet à e-MECeF dès qu'Internet répond »). Voir « Le boîtier MECeF » plus bas.

Contraintes qui pèsent, issues du dépôt : ~30 agents, ~15 postes, un bâtiment ; coupures d'électricité et d'Internet ; CDCT §4.3 (pas de dépendance à Internet ni au cloud pour l'usage courant) ; RG-01 → RG-14, dont **RG-03** (stock jamais négatif), **RG-10** (écriture équilibrée), **RG-12** (aucune action anonyme), **RG-14** (archivage, jamais de suppression) ; l'impression est une exigence critique (A4, rouleau 80 mm, carte CR80) ; la maquette `prototype_html/` pèse **84 000 lignes de JavaScript** (dont 61 600 dans les modules d'écran), 305 écrans, 333 appels d'impression, **71 scénarios** de recette.

Si l'on ne décide pas : l'équipe code en Dart pendant que l'architecture cible l'attend en Rust, TypeScript et JavaScript — trois langages dont elle n'en pratique aucun.

## Ce que la pile doit tenir : les exigences non fonctionnelles

| Exigence | Cible proposée (à confirmer par la Direction) | Ce qui la porte vraiment |
|---|---|---|
| **Performance** | écran courant peint en < 1 s ; recherche patient < 300 ms ; 95ᵉ centile mesuré sur le matériel réel de la clinique | lecture **locale** (SQLite) : aucun aller-retour réseau pour lire. Le réseau ne pèse que sur la synchronisation, hors du chemin du geste |
| **Sécurité** | SQLite chiffré au repos, secret du poste dans le coffre du système, TLS mutuel poste ↔ hub, RBAC au hub **et** au poste, journal d'audit chaîné, double authentification (TOTP) pour l'administration et tout accès distant | le chiffrement et le RBAC ne dépendent pas du langage ; **l'endroit où vit la règle** compte (voir ci-dessous) |
| **Disponibilité** | côté soignant : le poste ne dépend pas du hub pour ses gestes courants. Côté hub : 99,5 % (≈ 3 h 36 par mois) | 99,95 % ≈ **21,6 minutes par mois**. Aucun cadre technique ne le garantit seul ; sur un hub unique avec coupures électriques, viser 99,95 % serait une promesse que rien ne soutient. C'est l'**autonomie du poste** qui donne la disponibilité perçue |
| **Scalabilité** | 15 postes simultanés + 5 smartphones, marge ×3 | dimensionnement d'un seul hub PostgreSQL : sans objet de chercher plus |
| **Maintenabilité** | une règle métier = **un seul exemplaire** exécuté au poste et au hub ; mises à jour de poste en une action ; migrations de schéma rejouables | **un seul langage** pour les règles, les trois clients et le hub |
| **Portabilité** | poste Windows 10/11 et Linux ; hub Linux ou Windows ; smartphone Android (iOS à confirmer) | cible de compilation native de chaque plateforme |
| **Ergonomie** | saisie au clavier, raccourcis, état de synchronisation toujours visible, accessibilité (contraste, taille de texte), tableaux denses lisibles à 11 pt | composants natifs desktop + dispositions adaptatives pour le téléphone |

## Le boîtier MECeF : ce qu'il change

`ARCHITECTURE-CIBLE.md` §8 suppose une certification **en ligne et différée** (e-MECeF). Avec un **boîtier physique** sur place, la logique s'inverse, **à confirmer par la fiche technique du boîtier et la DGI** :

1. **La certification devient locale** : elle ne dépend plus d'Internet, mais d'un **appareil unique** (en panne, sans papier, éteint, mémoire pleine, non branché). La file « en attente de certification » ne se vide plus quand Internet revient, mais quand **le boîtier répond**.
2. **Le boîtier est une autorité de numérotation fiscale** — vraisemblablement ses propres compteurs et sa propre signature. Le hub n'est donc plus l'autorité de **tout** : pour le numéro fiscal d'une facture, le boîtier fait foi. On ne fabrique jamais un numéro fiscal en dehors de lui.
3. **Il ne se joint pas depuis n'importe où** : liaison série, USB ou réseau local selon le modèle. Un smartphone ne l'atteint pas par USB, et rien n'autorise l'émission fiscale hors de la caisse. **Le smartphone n'émet aucune facture normalisée.**
4. **Où le brancher décide de la continuité** : branché au **hub**, un hub arrêté arrête la certification de toute la clinique ; branché au **poste de caisse** (ou joignable en réseau local directement depuis les postes de caisse), la caisse certifie même hub arrêté, et le résultat (code, QR, compteurs) remonte ensuite par le journal comme toute pièce émise. **Recommandation : sur la caisse, pas sur le hub.**
5. **Un adaptateur, deux réalisations** : un port `Mecef` dans `packages/domaine` avec un adaptateur « boîtier » et un adaptateur « e-MECeF » (au cas où la DGI imposerait ou autoriserait le service en ligne). Le reste du logiciel ne sait pas lequel tourne.

**Questions à poser au fournisseur du boîtier et à la DGI avant tout code d'intégration** (aucune n'est tranchée par un document du dépôt) : modèle exact ; interface (série, USB, réseau) et protocole ; existe-t-il un kit de développement et un simulateur ; certification en combien de secondes ; que fait-il hors ligne et quelle est sa mémoire (combien de factures, combien de jours) ; qui transmet à la DGI et quand ; comment s'émet une **facture d'avoir** normalisée (le prototype a `SIGH.emettreAvoir`) ; réimpression d'un duplicata ; panne papier ou coupure en cours d'émission ; réglage de l'horloge ; nombre de boîtiers prévus.

## Options examinées

**A. Flutter (poste Windows/Linux + Android) + hub en Dart, domaine partagé en Dart.**
Une seule langue de bout en bout : un paquet `domaine` (règles RG-xx, calculs de prise en charge, comptabilité) exécuté sur le poste hors ligne **et** sur le hub qui l'arbitre. Avantages : compétence existante, aucune règle en double, un seul outil de test, installeur natif Windows/Linux, interface partagée avec le téléphone. Inconvénients : **l'écosystème serveur Dart est plus étroit** que .NET ou Java (authentification, observabilité, pilotes) ; il faut réécrire l'interface (voir coûts) ; la maturité des greffons de périphériques sur Linux est inégale. Exploitation : un exécutable de hub compilé, un service système, une image conteneur.

**B. Flutter + hub ASP.NET Core / .NET (recommandation de l'analyse du 21/10/2026).**
Hub très solide, outillage d'entreprise complet. Inconvénient décisif **pour ce projet** : les règles doivent s'exécuter **au poste hors ligne** (Dart) **et** faire autorité **au hub** (C#). Deux implémentations de RG-03, RG-09, RG-10, du moteur de prise en charge, des écritures comptables : c'est exactement la divergence que ce dépôt a dû corriger à chaque fois qu'une règle vivait en deux exemplaires (code patient, `carteValide` en trois copies, centres de coûts à deux référentiels). Une compétence C# à acquérir en plus. Coût de maintenance : deux piles, deux chaînes de livraison.

**C. Flutter + hub Spring Boot / Java.** Mêmes qualités et même défaut que B, avec JVM à exploiter. Aucun argument qui le distingue de B ici.

**D. Tauri 2 + interface JavaScript du prototype + hub Node/TypeScript (cible actuelle de `ARCHITECTURE-CIBLE.md`).**
Réutilise les 84 000 lignes de JS et les 71 scénarios ; domaine partagé en TypeScript. Avantage énorme : **pas de réécriture**. Inconvénients : la compétence de l'équipe est Dart, pas TypeScript/Rust ; l'interface téléphone resterait un WebView responsive ; l'accès au boîtier et aux imprimantes passe par du Rust à écrire. **C'est l'option la moins chère en développement et la moins alignée sur l'équipe.** Écartée **par la Direction** (consigne d'oublier le stack défini), non par défaut technique.

**E. .NET (WPF / WinUI / Avalonia / MAUI) de bout en bout.** Un seul langage (C#) et très bon accès Windows ; mais l'équipe n'y est pas, la cible smartphone partagée exige MAUI (jeune pour le desktop Linux) ; écarté.

**F. Application web (navigateur) + hub.** Écarté : le cache navigateur n'est pas un support de données de santé (déjà écarté dans l'architecture cible), l'accès série/USB au boîtier y est fragile, la continuité hors ligne dépend du navigateur.

**G. Ne rien changer** (prototype PHP + PostgreSQL). Reste la maquette et la référence de recette ; ne peut pas être le produit : un seul serveur sans autonomie des postes, RBAC côté navigateur, magasin remplacé par collection entière.

## Décision

**Option A**, sous réserve du banc de validation ci-dessous. Concrètement :

- **Poste** : application Flutter desktop (Windows 10/11, Linux). Base locale SQLite **chiffrée** (SQLCipher), accès par `drift`. Secret de base dérivé d'un secret conservé dans le coffre du système.
- **Mobile** : application Flutter Android (iOS si le parc le demande), **même code d'interface** adaptatif, joignant le hub sur le réseau de la clinique ou par VPN d'entreprise ; **aucune** exposition du hub à Internet.
- **Hub** : service Dart compilé (serveur HTTP `shelf`, accès PostgreSQL), PostgreSQL 16 comme autorité, sauvegardes chiffrées et **réplica hors site** (sans bloquer l'usage courant, CDCT §4.3).
- **Règles métier** : un paquet Dart `packages/domaine` (+ `rbac`, `referentiels`, `impression`, `schema`) **consommé tel quel** par le poste, le mobile et le hub. Un vecteur de tests partagé (cas JSON entrée/sortie) tient lieu d'exécutable de référence.
- **Synchronisation** : le **journal d'opérations** d'ADR-0001, inchangé. Le choix du moteur (PowerSync avec son SDK Flutter, ElectricSQL, ou moteur maison) reste à ADR-0004, après le banc.
- **MECeF** : port `Mecef` + adaptateur boîtier, **branché à la caisse**, numéro fiscal toujours issu du boîtier ; adaptateur e-MECeF en réserve.
- **Prototype** : `prototype_html/` devient l'**exécutable de référence** : ses écrans, ses règles et ses 71 scénarios sont la recette. On porte **par tranches verticales** (caisse + MECeF, puis pharmacie, laboratoire, …), pas écran par écran.

**On ne fait pas** : de backend en C# ou Java en parallèle du domaine Dart (règle en double) ; de microservices, de Kubernetes, de bus d'événements (15 postes) ; de réécriture « tout d'un coup » ; de fusion silencieuse des conflits ; d'émission fiscale depuis le téléphone ; d'exposition du hub à Internet.

## Conséquences

- **Positives** : un langage pour tout ; une règle un exemplaire ; l'équipe travaille dans son outil ; interface partagée poste/téléphone ; installeurs natifs ; l'autonomie du poste donne la disponibilité perçue sans dépendre d'un SLA de serveur.
- **Négatives, et ce qui les compense** :
  - **L'interface se réécrit.** 305 écrans, 333 impressions, 71 scénarios : c'est le poste de coût dominant, de l'ordre de la taille du prototype (≈ 80 à 100 000 lignes). Compensation : tranches verticales, ordre dicté par le risque (caisse + MECeF + impression d'abord), prototype conservé comme spécification vivante, scénarios portés en tests d'intégration.
  - **Écosystème serveur Dart plus étroit.** Compensation : le hub est petit (pas d'API publique, 15 postes), les critères du banc sont explicites, et **le repli est connu** : si le banc échoue sur le hub, bascule vers B avec le domaine protégé par les vecteurs de tests partagés.
  - **Greffons de périphériques** (série, USB, impression thermique 80 mm, carte CR80) inégaux sur Linux. Compensation : ce sont les trois premiers critères du banc, avant tout écran.
  - **Flutter desktop reste jeune pour les tableaux denses** (milliers de lignes, colonnes configurables, impression de pages longues). Compensation : critère de banc dédié.
- **Impose** : `VERSION` du schéma unique dans `packages/schema` (migrations pour SQLite et PostgreSQL) ; `packages/rbac` et `packages/domaine` exécutés au poste **et** au hub ; chaque spec (`/spec`) déclare la famille de fusion de chaque écriture ; chaque plan touchant un invariant porte un banc à deux postes ; le **dictionnaire des données** (`DICTIONNAIRE-DONNEES.md`) et le schéma `packages/schema/postgres/0001_modules.sql` engendrés depuis le prototype sont la base du schéma cible.

## Comment on vérifiera que c'était la bonne décision

**Banc de validation avant acceptation** (aucun écran métier n'est porté avant qu'il passe), sur le **matériel réel** de la clinique, Windows et Linux :

1. **Hors ligne** — création d'un dossier patient sur deux postes hub arrêté, puis rétablissement : zéro doublon de code (RG-01), zéro opération perdue, convergence mesurée.
2. **Invariants concurrents** — deux postes sortent le dernier lot d'un article hub arrêté : au rétablissement, le second geste est mis en **conflit visible**, jamais en stock négatif (RG-03).
3. **Boîtier MECeF** — émission d'une facture sur le poste de caisse **hub arrêté et Internet coupé** ; coupure du boîtier en cours d'émission ; reprise sans doublon fiscal.
4. **Impression** — un ticket 80 mm, un état A4 de 60 lignes avec total, une carte CR80, depuis Windows et Linux, sans pilote exotique.
5. **Performance** — liste de 20 000 lignes paginée et filtrée < 1 s ; recherche patient < 300 ms ; 15 postes + 5 téléphones écrivant en continu : latence de synchronisation 95ᵉ centile < 5 s.
6. **Reprise** — redémarrage brutal du hub et d'un poste en pleine écriture : rien de perdu, rien de dupliqué ; restauration à blanc depuis la sauvegarde.
7. **Sécurité** — disque d'un poste copié : base illisible sans le coffre ; appareil perdu : révocation effective à la reconnexion ; journal d'audit : toute action attribuée (RG-12).

**Seuil de bascule** : si les critères 3, 4 ou 5 échouent sur Dart de façon non corrigeable en deux semaines, on rouvre cette décision (option B pour le hub, ou D pour le poste). **Revue** : à la fin de la première tranche verticale (caisse + MECeF), puis à six mois d'exploitation.
