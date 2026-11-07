# Plan en sprints — programme complet (30/10/2026)

> Remplace l'ordonnancement informel de `PLAN-implementation-v2.md`. Périmètre : **une** application Flutter desktop (305 écrans fidèles à la maquette + modules complémentaires de la mère), l'application mobile, le relais `apps/web`, le domaine partagé, et la qualité sur tous les niveaux.
>
> **Hypothèses à confirmer** (elles commandent les durées) : sprints de **2 semaines** ; équipe de **3 développeurs Flutter + 1 Laravel/PHP + 1 testeur** ; la vélocité réelle sera **mesurée aux sprints S1 et S2**, puis le calendrier est recalibré. Sans équipe nommée, les durées ci-dessous sont des ordres de grandeur, pas des engagements.

## 0. Règles de tous les sprints

| Règle | Détail |
|---|---|
| **Pousser à chaque tâche terminée** | `git push` sur la branche de travail après **chaque** tâche close, pour que la branche se clone et que les tests se lancent en local (web et poste). |
| **Définition de « fini »** (DoD) | code + tests qui **peuvent échouer** (au moins une mutation détectée) · `dart analyze` / `flutter analyze` / `php artisan test` propres · documentation à jour · poussé. |
| **Une règle sans vecteur n'est pas portée** | tout moteur à état est porté avec des vecteurs **engendrés par la maquette** (jamais écrits à la main). |
| **Fidélité de l'écran** | N1 contenu 100 % · N2 structure 100 % · N3 visuel ≤ 2 % revu · N4 scénarios rejoués (voir `PLAN-conversion-305-ecrans.md`). |
| **Direction de conception** | on garde de la maquette : barre supérieure, ruban horizontal à méga-menus, CRUD, tableaux, modales, tiroirs, structure et ordre des pages, espacements, hiérarchie typographique, emplacement des boutons, animations, comportement responsive, logo, icônes, génération PDF. Une refonte n'est permise que sur décision explicite. |
| **Un écart de la maquette se signale** | `docs/architecture/ECARTS-MAQUETTE.md` ; correction **dans la maquette d'abord**, vecteurs régénérés, puis portage. |
| **Revue de sprint** | démonstration, tableau de parité, liste de ce qui n'est **pas** fait, mise à jour du plan. |

## 1. Quatre pistes en parallèle

| Piste | Contenu | Responsable type |
|---|---|---|
| **A — Poste (305 écrans)** | kit, parité, tranches 1 à 6, moteurs à état | Flutter ×2 |
| **B — Modules de la mère (22)** | service, console, supervision, sauvegarde, relais | Flutter ×1 + Dart serveur |
| **C — Mobile** | écrans Flutter des 21 pages du simulateur, câblage natif | Flutter (renfort ponctuel) |
| **D — Relais web** | 12 modules du panneau, exploitation cPanel | Laravel ×1 |
| **Q — Qualité** | outillage de parité, recette, audit RBAC, sécurité | testeur |

## 2. Les sprints

### Phase 0 — Fondations (FAIT)
- **S0** (réalisé) : protocole de synchronisation (3 implémentations, 128 vérifications), relais Laravel + panneau, console de la mère, coque unique fileul/mère, moteur de droits, mobile (logique), prise en charge RG-09 et encaissement RG-10 portés, **prototypes** des 22 modules de la mère, des 12 modules du relais et du simulateur mobile, correction des écarts E1/E3.

### Phase 1 — Le socle de l'application (≈ 4 sprints)

| Sprint | Objectif | Tâches | Sortie |
|---|---|---|---|
| **S1** | Le mode mère s'active à l'exécution ; la coque a le visage de la maquette | **T9** activation à l'exécution + garde « une seule mère » · **T10a** kit : thème (jetons), barre supérieure, ruban à méga-menus filtré par droits, fil d'Ariane, gabarit de page standard, KPI · **B** M-15 *Service et démarrage* (écran réel) | l'application ouvre une page vide **qui a l'aspect de la maquette** ; la mère s'active par réglage |
| **S2** | Les composants de données | **T10b** tableau (tri, filtres, pagination, colonnes, plage de dates, recherche) · formulaire à **6 colonnes** · `combo`/`multiselect` · modale · tiroir · onglets avec ancre · toasts avec annulation · **Q** début de **T11** (extracteur de contenu/structure côté maquette) | page de démonstration de chaque composant ; **vélocité mesurée** |
| **S3** | Impression et graphiques | **T10c** impression A4 / rouleau 80 mm / badge CR80, en-tête légal unique, pied normalisé, totaux **calculés** · graphiques · **T11** extracteur côté Flutter, rapport N1/N2 par écran | rapport de parité engendré ; une pièce imprimée identique à la maquette |
| **S4** | Persistance locale et synchronisation réelle | base locale (drift) + file d'envoi · branchement de `sigh_sync` dans le **magasin** de l'application (lecture synchrone des fiches) · **B** M-04 *À traiter consolidé* · M-05 *Journal des opérations* | un poste crée une fiche hors ligne, la retrouve après coupure ; scénarios R1/R2 rejoués sur l'application |

### Phase 2 — Les tranches d'écrans (≈ 16 sprints)

Cadence cible : **≈ 15 écrans par sprint** (à recalibrer après S2). Chaque tranche se ferme à **N1 = N2 = N4 = 100 %** et N3 revu.

| Sprints | Tranche | Écrans | Contenu et moteurs |
|---|---|---|---|
| **S5–S6** | 1 — Caisse, MECeF, impression | 17 | écrans de caisse, tickets, factures **-A/-B**, avoir (**T18** `emettreAvoir`), état MECeF **simulé** · **blocage** : protocole du boîtier physique (informations attendues à la finalisation) |
| **S7–S8** | 2 — Pharmacie, stocks, achats | 27 | FEFO, CUMP, RG-03, bons de commande RG-04, PV de réception · vecteurs **valorisation** et **FEFO** |
| **S9–S10** | 3 — Laboratoire, imagerie | 24 | deux verrous de validation, plages par lot versionnées, cinq modalités d'imagerie |
| **S11–S14** | 4 — Parcours clinique | 67 | patients/DMI (zones 1 et 2), consultations (dossier → fiche → prescription), hospitalisation, maternité (cahier obstétrical, partogramme) |
| **S15–S16** | 5 — Assurances, comptabilité | 31 | facture mère, balance âgée, exercice et clôture (**T18**), états financiers (feuillets 7/51 et 8/51), BFR |
| **S17–S20** | 6 — RH, paie, administration, pilotage, configuration, tableaux de bord, rapports | 120 | paie (ITS, CNSS, ORTB), primes (grille datée), évaluations, badges, enquêtes, 20 tableaux de bord par poste |

Pistes parallèles pendant ces sprints :

| Sprints | Piste B (mère) | Piste C (mobile) | Piste D (relais) |
|---|---|---|---|
| S5–S6 | M-09 sauvegardes/restauration · M-10 clé de clinique | écrans Flutter : appairage, PIN, accueils | `rls-boites`, `rls-indicateurs` |
| S7–S8 | M-13 relais · M-14 indicateurs | soignant : tournée, dossier, constantes | `rls-alertes`, `rls-parametres` |
| S9–S10 | M-06 plages/baux · M-07 lots de tournée | médecin : consultation, prescription, analyses | `rls-superadmin`, `rls-hebergement` |
| S11–S12 | M-11 intégrité · M-12 réinitialisation (écran réel à compléter) | sage-femme : CPN, CPoN, surveillance | `rls-sauvegarde`, `rls-opacite` |
| S13–S14 | M-16 base · M-17 réseau | réception de secours (4 écrans) | revue de sécurité du relais |
| S15–S16 | M-18 planificateur (PHP → Dart) · M-19 notifications | synchronisation mobile ↔ relais réelle, lot expirant | exploitation : supervision, journaux |
| S17–S20 | M-20 assistant de mise en service · M-21 mises à jour · M-22 import de migration | coffre sécurisé, PIN, biométrie, notifications (**hors de l'environnement de rédaction**) | — |

### Phase 3 — Mise en service (≈ 3 sprints)

| Sprint | Objectif | Contenu |
|---|---|---|
| **S21** | Recette de bout en bout | les **74 scénarios** de la maquette rejoués sur l'application · audit RBAC 0 promesse · scénarios de coupure à plusieurs processus sur l'application complète |
| **S22** | Sécurité et performance | revue de sécurité (clé de clinique, enveloppes, jetons, RBAC côté serveur) · **tests de charge** (30 agents, 18 000 dossiers) · SQLCipher · journaux |
| **S23** | Packaging et déploiement | service Windows / systemd · installeur · compilation native Windows, Linux, Android, iOS · procédure de sauvegarde et de retour arrière · formation · migration des données réelles |

## 3. Dépendances externes (à fournir au moment de la finalisation)

| Besoin | Bloque | Statut |
|---|---|---|
| **Protocole du boîtier MECeF physique** (modèle, interface, dix questions au fournisseur et à la DGI) | S5–S6 (intégration), S23 | **annoncé par la Direction** — « informations fournies au moment de la finalisation » |
| Équipement de build : Windows, Android, iOS (compilation native, signature) | S23 | hors de l'environnement de rédaction |
| Détenteur de la copie papier de la clé de clinique | S6 (M-10), S22 | à désigner par la Direction |
| Arbitrage des écarts E2 (pièce sans lignes) et E4 (date jour / instant) | S5 | ouverts |
| Accès à un cPanel réel pour la procédure de déploiement | S23, piste D | à fournir |
| Jeu de données réel (migration SAGE, classeurs) | S23, M-22 | à fournir |

## 4. Risques et parades

| Risque | Parade |
|---|---|
| **Ampleur** (≈ 61 700 lignes d'écrans) sous-estimée | vélocité mesurée à S2 ; recalibrage du calendrier à la revue de S2 ; tranche 6 découpée en lots par module |
| Dérive entre maquette et application | extracteurs N1/N2 **engendrés** ; aucune parité déclarée « à l'œil » |
| Règles métier portées divergentes | vecteurs engendrés + mutations ; écarts consignés |
| Le magasin synchrone de la maquette n'a pas d'équivalent direct en Flutter | décision d'architecture en **S4** (cache mémoire hydraté + journal), ADR à rédiger avant tout écran de tranche |
| Blocage MECeF | écrans et simulation d'abord ; intégration physique isolée derrière une interface |

## 5. État d'avancement

Tenu dans `PLAN-implementation-v2.md` (§ État d'avancement) et dans le tableau de parité `docs/architecture/PARITE-MAQUETTE.md`.
