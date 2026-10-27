# ADR-0005 — Hub Laravel (API + panneau d'administration), poste Flutter, PWA Vue : réévaluation d'ADR-0003

| | |
|---|---|
| **Statut** | **proposé** — demandé par la Direction le 27/10/2026 ; **ne remplace pas ADR-0003 tant qu'il n'est pas accepté** |
| **Date** | 27/10/2026 |
| **Décideurs** | Direction, ingénierie |
| **Lié à** | ADR-0001 (local-first, hub en étoile, journal d'opérations), ADR-0003 (Flutter + hub Dart), `docs/prd/PRD-FLUTTER-poste-fidelite-maquette.md` |

## Contexte

ADR-0003 recommandait un seul langage (Dart) pour le poste, le mobile et le hub, afin que RG-03 / RG-09 / RG-10 n'existent qu'en **un** exemplaire. La Direction demande désormais une pile différente pour le serveur et le web :

- **Flutter desktop** (poste Windows/Linux) et mobile ;
- **Laravel** comme **API de synchronisation** et comme **panneau d'administration complet** (Livewire) ;
- **PWA** (Vue) pour les utilisateurs qui n'ont pas le poste installé ; la fin de cette exigence est tronquée dans la demande (« …pour des utilisateurs qui ont des… ») — voir Q1.

Un projet Laravel 12 + Inertia/Vue existe déjà hors dépôt (`sigh_web/`, ~70 000 lignes de PHP, base `sigh_cnt` de 173 tables ; cf. `CLAUDE.md`, « Architecture cible »). Il n'est pas versionné ici : son état réel est à vérifier avant de décider d'en reprendre quoi que ce soit.

## Le point qui décide : où vivent les règles métier ?

Avec Laravel côté serveur et Dart côté poste, **chaque règle existerait deux fois** (PHP + Dart) — exactement la divergence que ce dépôt a payée à chaque règle écrite en double (code patient, `carteValide`, date du jour). Trois façons de la contenir ; il faut en choisir **une** :

| Option | Principe | Coût | Risque |
|---|---|---|---|
| **A. Serveur autoritaire, poste en saisie** | Le poste capte et affiche ; les règles qui engagent (RG-03 stock, RG-09 assurance, RG-10 équilibre, RG-01 code) sont **appliquées par Laravel** à la synchronisation et leur refus revient en **conflit nommé**. Le poste n'exécute qu'un sous-ensemble de contrôles de confort. | Moyen | Hors ligne, le poste ne peut pas toujours *calculer* (part assureur, avoir) : l'agent voit un montant provisoire |
| **B. Règles en double + vecteurs de tests partagés** | PHP et Dart implémentent les mêmes règles ; des cas JSON (entrée → sortie) exportés de la maquette sont rejoués des **deux** côtés en CI | Élevé, permanent | La divergence est détectée, pas empêchée |
| **C. Un seul exemplaire exécutable partout** | Domaine en Dart appelé aussi par le serveur (ADR-0003) | — | C'est l'option que la demande écarte |

**Recommandation : A pour les invariants qui engagent, B (vecteurs) pour tout ce que le poste doit calculer hors ligne** (répartition assureur/patient, totaux, écritures). Les vecteurs de tests viennent de la maquette, exécutable de référence.

## Répartition des responsabilités

| Composant | Rôle | Hors ligne ? |
|---|---|---|
| **Flutter poste** (Windows/Linux) | Saisie et caisse à plein débit, impression (A4, 80 mm, CR80), boîtier MECeF, SQLite chiffré | **Oui** (autonome) |
| **Laravel API** | Autorité des données (PostgreSQL), endpoint de synchronisation par journal d'opérations, RBAC serveur, notifications, planificateur (`schedule:run`), journal d'audit | — |
| **Laravel + Livewire** | Panneau d'administration complet (utilisateurs, rôles/RBAC, référentiels, tarifs, modules actifs, audit, sauvegardes, tâches planifiées, supervision) | Non (en ligne) |
| **PWA Vue** | Accès navigateur/téléphone pour les profils qui n'ont pas le poste ; consultation + saisie ciblée ; mise en cache et file d'envoi hors ligne limitées | **Partiel** |

**Contrainte à écrire noir sur blanc** : la PWA n'est **pas** un support de données de santé hors ligne durable (ADR-0003, option F écartée : le cache du navigateur n'est pas un coffre). Elle met en file des opérations non sensibles ; le reste exige la connexion.

## Ce qui ne change pas

Journal d'opérations (ADR-0001), archivage au lieu de suppression (RG-14), aucune action anonyme (RG-12), boîtier MECeF branché à la **caisse** (pas au serveur), pas d'exposition du serveur à Internet sans passerelle/VPN, fidélité à la maquette (PRD Flutter).

## Conséquences

- **Positives** : écosystème Laravel/Livewire mûr côté API et administration ; panneau d'administration quasi gratuit ; recrutement PHP plus large que Dart serveur ; un panneau web sans installation.
- **Négatives** : deux langages et deux exemplaires de règles (voir ci-dessus) ; trois interfaces à tenir à parité (Flutter, Livewire, Vue) — **l'ergonomie doit venir d'un seul système de conception** (jetons partagés, §« Système de conception ») ; le moteur de synchronisation (ADR-0004) change de nature : un **endpoint** Laravel remplace PowerSync/ElectricSQL-sur-Dart, ou les complète.
- **Impose** : schéma unique source de vérité (migrations Laravel → PostgreSQL, **et** SQLite poste dérivé du même dictionnaire) ; suite de vecteurs de tests partagée ; RBAC exprimé **une fois** (matrice exportable en JSON) et lu par Laravel, Flutter et Vue ; règles de nommage des identifiants techniques figées (cf. doctrine « on ne renomme pas un identifiant technique »).

## Banc de validation avant acceptation

1. Synchronisation bidirectionnelle hors ligne sur deux postes Flutter : zéro doublon de code patient, conflit visible sur stock (critères 1–2 d'ADR-0003).
2. **Vecteurs de tests** : 100 % identiques maquette ↔ Laravel ↔ Dart sur les moteurs exposés (`PR.repartir`, `PR.encaisser`, `emettreAvoir`, `exercice`…).
3. Boîtier MECeF + impression 80 mm / A4 / CR80 depuis Flutter (critères 3–4 d'ADR-0003).
4. Performance : liste de 20 000 lignes < 1 s côté poste ; API p95 < 500 ms avec 15 postes + 5 téléphones.
5. PWA : installation, mise à jour du service worker, file d'envoi, **aucune donnée de santé en cache clair**.
6. Reprise : arrêt brutal d'API et de poste en pleine écriture, restauration depuis sauvegarde.

**Seuil de bascule** : si les critères 1, 2 ou 3 échouent de façon non corrigeable en deux semaines, retour à ADR-0003 (hub Dart).

## Questions ouvertes

- **Q1 (Direction)** — « …des utilisateurs qui ont des… » : quelle contrainte décrit la fin de la phrase (faible connexion, pas d'ordinateur, téléphone seul) ? Elle fixe ce que la PWA doit faire hors ligne.
- **Q2 (ingénierie)** — Que contient réellement `sigh_web/` (version, tests, dernier état) ? Reprise partielle ou base propre ?
- **Q3 (ingénierie)** — Livewire **et** Vue : Livewire pour le panneau, Vue pour la PWA — ou un seul des deux ? Le prix d'un second framework d'interface est à chiffrer.
- **Q4 (Direction)** — Les exigences non fonctionnelles génériques de la demande (« 100 000 utilisateurs simultanés », 99,99 %) sont des chiffres de gabarit : la clinique compte ~30 agents et ~15 postes. Quels objectifs retient-on réellement ? (proposition dans le plan)
- **Q5 (fournisseur / DGI)** — Protocole du boîtier MECeF (inchangé depuis ADR-0003).
