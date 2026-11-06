# Inventaire de reprise (06/11/2026)

Source : mémoire de la session et historique git. Les transcripts n'ont pas été relus en bloc (économie de tokens). Les cases marquées « à vérifier » n'ont pas été rejouées.

## 1. Règles de reprise (économie de tokens)

1. Nouvelle session sur la même branche (contexte de 900 k tokens : chaque tour relit tout).
2. Aucun fork. Un agent frais par lot, modèle Sonnet, brief de 20 lignes maximum, qui cite la spec et ne lit rien en bloc.
3. Aucune relecture par agent, sauf pour l'argent (411, 706, 571, ORTB, paie, avoirs) et les droits (RBAC, pair).
4. Maquette d'abord, puis vecteurs, domaine, poste. Une seule suite complète, en fin de série.
5. Banc isolé : `SIGH_PORT_PHP`, `SIGH_BASE_TEST`, `SIGH_PORT_TEST` distincts (E2263).

## 2. Cible par application

| Application | Ce qu'il reste |
|---|---|
| `prototype_html` | Fausses sauvegardes (85 constats), filtres et CRUD manquants, espace « Mes » de l'agent, mise en page |
| `apps/poste` (Flutter) | Écrans de configuration fiscale, impression et échéances à la date, fausses sauvegardes, espace « Mes », MECeF boîtier |
| `apps/web` (relais) | Resserrer le coffre (décision), aucun lot ouvert sinon |
| `apps/mobile` | Espace « Mes » de l'agent (planning, présences, congés), appairage déjà fait |
| `packages/domaine`, `sync_dart` | Port `Mecef` + trames, mère Dart rejouée sur PostgreSQL en mode pair |

## 3. Lots (ordre de reprise)

| # | Lot | État | Risque de régression |
|---|---|---|---|
| L1 | Inspecter le WIP fiscal du poste (commit 7466e76, non vérifié) : analyse, tests, soit finir soit reverter | **inachevé** | impression des pièces, ORTB, échéances, installation (détection par validation) |
| L2 | Fiscal poste : écrans `cfg-fiscalite`, `cfg-comptabilite`, `cfg-branding`, `cfg-entetes`, impression à la date, fileul en lecture seule, jeu régénéré, parité N1 100 % | **inachevé** | argent : relecture obligatoire |
| L3 | Fausses sauvegardes : 85 constats non « doute » (46 écriture partielle, 14 relecture absente, 11 journal seul, 11 aucune écriture, 3 mémoire seule). Maquette d'abord, sonde Vague 82, `AUDIT-FAUSSES-SAUVEGARDES.md`. 111 « doute » à trier ensuite | **interrompu** | tout écran de saisie ; argent et droits relus |
| L4 | MECeF boîtier : ADR (questions ouvertes à jour), port `Mecef`, encodeur de trames + BCC avec vecteurs, simulateur, reprise sans doublon, avoir | **non démarré** | caisse, facturation, avoirs, M8 et MECeF |
| L5 | Espace « Mes » de l'agent (17 rubriques), régime individuel, filtres avancés (planning, registre des vacations), CRUD planning/primes/sécurité | **non démarré** (PRD écrit, `f7b3d3b`) | M10, M11, droits des agents, mobile |
| L6 | Rejeux de clôture : `check` isolé 306 pages, audit RBAC isolé, suite poste, une suite maquette complète | **à rejouer** (anciens passages sur arbre partagé) | aucune (mesure) |
| L7 | Mise en page : cohérence grille, marges, modales (`Colors.white` en dur, 114 usages), vérification sur écran réel | **partiel** (relevé fusionné, correction non reprise) | tout le poste, visuel seulement |
| L8 | Mère Dart rejouée sur PostgreSQL en mode pair (P7 déjà vert, reprise après SIGKILL) ; mesure du cache pour grosse clinique | à vérifier | sync |
| L9 | Recette sur site (hors environnement) : Windows (build, installateur, certificats), Android, deux postes physiques, SMTP clinique avec mot de passe, boîtier réel | **non vérifiable ici** | |

## 4. Nouvelles fonctionnalités à créer

- MECeF boîtier Eltrade CC300 : adaptateur Dart derrière le port `Mecef`, trames `<01><LEN><SEQ><CMD><DATA><05><BCC><03>`, 115 200 8N1, VID `03EB` PID `6119`, commandes C1, C2, 2B, C0, 31, 35, 38. Montants en entiers FCFA.
- Espace « Mes » : fiche de poste, fiche de paie, contrat, planning et gardes, statistiques de garde et de permanence, taux de présence, présences et absences (validation DA), congés, ordres de mission, primes, événements, participations, assurance, notes de service, agenda, rendez-vous.
- Planning : régimes individuels, filtres avancés, CRUD de gardes par médecin, saisie depuis le mobile avec synchronisation.
- Configuration fiscale à la première configuration, versions datées ensuite (poste).

## 5. Bugs et défauts détectés

| Où | Défaut | État |
|---|---|---|
| Maquette et poste | Créance assureur 411 absente du journal | corrigé (E2260, E2261) |
| Maquette | Secteur des demandes semées | corrigé (E2262) |
| Banc | Deux passages partageaient un serveur PHP | corrigé (E2263) |
| Écrans de saisie | Fausses sauvegardes (écriture partielle, journal seul, mémoire seule) | **ouvert**, 196 constats |
| Poste | `Colors.white` en dur dans les panneaux de modale | **ouvert** |
| Maquette | `check` des 306 pages jamais abouti d'un seul tenant | **à rejouer par tranches** |
| Relais | Destination du coffre libre pour un appareil appairé | décision attendue |
| Pilote Eltrade (tiers) | float32, pas de reprise, pas de verrou, `GetCmd` rend `seq`, `clean()` inerte, boucle sans fin sur réponse tronquée, pas de test | **ne pas reprendre le code** |

## 6. Questions en attente de validation

1. **Coffre de récupération** : déjà décidé « une seule adresse, celle du superadmin ». À confirmer qu'on applique côté relais pour tout appareil appairé.
2. **Courriel du poste** : déjà décidé « envoi direct, file avec reprise seulement en cas d'échec ». À confirmer que c'est figé.
3. **Installateur** : Q2 nom `SIGH_Poste_Setup_<version>.exe`, Q4 avertissement renforcé pour la mère, Q5 signature de code différée, Q6 sauvegardes `Documents\SIGH-CNT-Sauvegarde-<date>` jamais supprimées, Q7 `build_runner` conditionnel. Recommandations déjà données, validation attendue.
4. **MECeF** : commence-t-on par l'ADR (questions ouvertes à jour) ou par le port Dart ? Qui fournit la fiche technique et `MECeF_MCF_SFE_Protocole_v2.pdf` ? Nombre de boîtiers prévus ? Le boîtier est-il branché à la caisse (hypothèse retenue) ?
5. **Mot de passe SMTP** : saisi dans le panneau, jamais dans le dépôt. Test en ligne par la Direction.
6. **Planning individuel (PRD f7b3d3b)** : décisions Q1 à Q8 du PRD restent à valider avant le lot L5.
7. **Fausses sauvegardes** : corriger tout de suite les 85 constats non « doute », et trier les 111 « doute » après ?
8. **Mise en page** : traiter seulement les anomalies importantes, ou toute la grille ?
9. **Fond des modales** : où voyez-vous encore un fond incorrect (quelle modale, quelle plateforme) ?

## 7. Proposition de séquence

L1 (inspection, sans agent) puis L3 (un agent Sonnet par groupe de 20 constats, argent et droits relus), puis L2, puis L6 en une seule fois. L4 peut démarrer en parallèle dès que la question 4 est tranchée. L5 après les décisions du PRD. L9 hors environnement.

## 8. Décisions de la Direction (06/11/2026, reçues)

| Sujet | Décision |
|---|---|
| Coffre de récupération | Adresse unique : le courriel de la DA ou du superadmin, rien d'autre, pour tout appareil appairé |
| Installateur | Les cinq recommandations validées (nom `SIGH_Poste_Setup_<version>.exe`, avertissement renforcé pour la mère, signature de code différée, sauvegardes `Documents\SIGH-CNT-Sauvegarde-<date>` jamais supprimées, `build_runner` conditionnel) |
| MECeF | Boîtier branché à la caisse ; 1 boîtier |
| SMTP | Mot de passe saisi dans le panneau lors du test en ligne ET en production, jamais dans le dépôt |
| Fausses sauvegardes | Corriger d'abord les 85 constats non « doute », trier les 111 « doute » ensuite |
| Mise en page | Toute la grille (pas seulement les anomalies importantes) |
| Fond des modales | Pas encore testé (branche non clonée) ; à reprendre au retour de test |
| Courriel du poste | Envoi direct, file avec reprise seulement en cas d'échec : figé |
| Planning individuel Q1 à Q8 | En attente de validation (voir PRD) |
