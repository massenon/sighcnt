# Manifeste de parité — maquette → cible

> **ENGENDRÉ** par `prototype_html/build/parite.js` — ne pas éditer. Seuls les statuts se saisissent, dans `docs/architecture/parite-statuts.json`.
> Sources : `packages/referentiels/data/manifeste.json`, `packages/rbac/data/rbac.json`, `prototype_html/build/test-fonctionnel.js`.

| Mesure | Valeur |
|---|---|
| Écrans du manifeste (hors hubs de module) | **336** |
| Hubs de module (un par module, engendrés) | 23 |
| Écrans nommés par au moins un scénario de la maquette | 229 (68 %) |
| Écrans **sans** scénario (recette à écrire) | 107 |
| Écrans portés | 336 |
| Écrans recettés | 0 |
| Scénarios de la maquette analysés | 111 |

> « Nommé par un scénario » est une **estimation par analyse du texte** du banc (un identifiant d'écran cité dans le scénario) : elle dit où une recette existe déjà à reprendre, pas qu'elle couvre tout l'écran.

## Par tranche

| Tranche | Écrans | Avec scénario | Portés | Recettés |
|---|---|---|---|---|
| 1 · caisse + MECeF + impression | 17 | 12 | 17 | 0 |
| 2 · pharmacie, stocks, achats | 27 | 23 | 27 | 0 |
| 3 · laboratoire (imagerie : rangée M2) | 24 | 22 | 24 | 0 |
| 4 · parcours clinique (M1–M4) | 67 | 50 | 67 | 0 |
| 5 · assurances et comptabilité | 31 | 21 | 31 | 0 |
| 6 · RH, paie, administration, pilotage, configuration | 170 | 101 | 170 | 0 |

## Par écran

Colonnes : **Rôles** = nombre de rôles qui voient l'écran (matrice effective) · **Scénarios** = numéros d'ordre dans `test-fonctionnel.js`.

### Tranche 1 · caisse + MECeF + impression

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m8-caisse` | État de caisse journalier | M8 | 8 | 16, 30, 35, 39, 40, 43, 71, 82, 102 | porté |
| `m8-dashboard` | Tableau de bord facturation | M8 | 8 | — | porté |
| `m8-facturation` | Nouvelle facture | M8 | 7 | 11, 13, 17, 19, 32, 34, 88, 90 | porté |
| `m8-facture-avoir` | Factures d’avoir | M8 | 8 | 48 | porté |
| `m8-factures` | Factures | M8 | 8 | 12, 30, 48, 82 | porté |
| `m8-operations` | Opérations de caisse | M8 | 8 | 20 | porté |
| `m8-paiements` | Paiements | M8 | 7 | 88, 99, 100 | porté |
| `m8-proforma` | Factures pro-forma | M8 | 8 | — | porté |
| `m8-recettes` | Recettes par période | M8 | 8 | 20 | porté |
| `m8-reliquats` | Reliquats | M8 | 8 | 20 | porté |
| `m8-remboursements` | Remboursements & annulations | M8 | 8 | — | porté |
| `mecef-avoirs` | Avoirs & annulations | MECEF | 6 | 108 | porté |
| `mecef-config` | Configuration fiscale | MECEF | 5 | 90, 108 | porté |
| `mecef-dashboard` | Tableau de bord fiscal | MECEF | 6 | — | porté |
| `mecef-factures` | Factures normalisées | MECEF | 6 | 76, 82, 99 | porté |
| `mecef-journal` | Journal des transactions | MECEF | 6 | — | porté |
| `mecef-transmission` | Transmission & réponses | MECEF | 6 | 108 | porté |

### Tranche 2 · pharmacie, stocks, achats

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m6-alertes` | Alertes & seuils | M6 | 7 | — | porté |
| `m6-dashboard` | Tableau de bord stock | M6 | 6 | 82 | porté |
| `m6-dispensation` | Dispensation | M6 | 7 | 16, 25 | porté |
| `m6-etiquetage` | Étiquetage & emplacements | M6 | 7 | 33 | porté |
| `m6-import-grand-stock` | Importation Grand Stock | M6 | 5 | 38, 77, 90 | porté |
| `m6-inventaire` | Inventaires | M6 | 6 | 66 | porté |
| `m6-inventaire-feuille` | Feuille d’inventaire — comptage | M6 | 6 | — | porté |
| `m6-lots` | Lots & péremptions (FEFO) | M6 | 6 | 12, 43 | porté |
| `m6-mouvements` | Mouvements de stock | M6 | 6 | 32, 43 | porté |
| `m6-pertes` | Pertes, casses & rebuts | M6 | 7 | 33, 90 | porté |
| `m6-pharmacie-externe` | Pharmacie externe — voie orale | M6 | 7 | 90 | porté |
| `m6-pharmacie-interne` | Pharmacie interne — urgences | M6 | 7 | — | porté |
| `m6-point-stock` | Point du stock valorisé | M6 | 7 | 39 | porté |
| `m6-point-ventes` | Suivi des ventes | M6 | 7 | 39, 58, 70, 71, 82 | porté |
| `m6-produits` | Référentiel produits | M6 | 7 | 4, 12, 55, 95, 103, 105 | porté |
| `m6-stock-detail` | Stock détail (pharmacie) | M6 | 6 | 41 | porté |
| `m6-stock-gros` | Stock gros (magasin) | M6 | 5 | 41, 55 | porté |
| `m6-transferts` | Transferts gros → détail | M6 | 5 | 5, 41, 43 | porté |
| `m7-besoins` | Bons d’expression de besoins | M7 | 20 (universel) | 32, 53, 68 | porté |
| `m7-commandes` | Bons de commande | M7 | 7 | 32, 82 | porté |
| `m7-ecarts` | Écarts de livraison | M7 | 7 | 32 | porté |
| `m7-factures-fournisseurs` | Factures fournisseurs | M7 | 6 | 32 | porté |
| `m7-fournisseurs` | Fournisseurs | M7 | 6 | 32 | porté |
| `m7-livraisons` | Bons de livraison | M7 | 6 | 32 | porté |
| `m7-pv-reception-consommables` | PV de réception — consommables | M7 | 6 | — | porté |
| `m7-pv-reception-reactifs` | PV de réception — réactifs | M7 | 7 | 48 | porté |
| `m7-receptions` | Réceptions & contrôles | M7 | 7 | 32 | porté |

### Tranche 3 · laboratoire (imagerie : rangée M2)

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m2-dashboard-imagerie` | Poste d’imagerie médicale | M2 | 8 | — | porté |
| `m2-echographie-galerie` | Galerie des clichés | M2 | 8 | 51 | porté |
| `m2-imagerie` | Tableau Échographie | M2 | 7 | 34, 39, 43, 58, 65 | porté |
| `m2-imagerie-cr` | Compte rendu d’imagerie — saisie | M2 | 7 | — | porté |
| `m2-imagerie-demandes` | Demandes d’imagerie médicale | M2 | 8 | 51, 58, 63, 67 | porté |
| `m2-imagerie-irm` | Tableau IRM | M2 | 7 | 63 | porté |
| `m2-imagerie-mammographie` | Tableau Mammographie | M2 | 7 | 63 | porté |
| `m2-imagerie-radiographie` | Tableau Radiographie | M2 | 7 | 63, 67 | porté |
| `m2-imagerie-scanner` | Tableau Scanner | M2 | 7 | 63, 67 | porté |
| `m5-banque-sang` | Banque de sang | M5 | 0 | 28 | porté |
| `m5-catalogue` | Catalogue des analyses | M5 | 8 | 3 | porté |
| `m5-demandes` | Demandes d’analyses | M5 | 9 | 16, 32, 49, 68 | porté |
| `m5-demandes-hospitalisation` | Demandes — hospitalisation | M5 | 9 | 49 | porté |
| `m5-demandes-maternite` | Demandes — maternité | M5 | 9 | 49 | porté |
| `m5-donneurs` | Donneurs & transfusions | M5 | 0 | 28 | porté |
| `m5-impression-resultats` | Impression des résultats | M5 | 8 | 49 | porté |
| `m5-prelevement` | Salle de prélèvement | M5 | 8 | 28, 41 | porté |
| `m5-reactifs` | Réactifs & consommables | M5 | 6 | 28, 34 | porté |
| `m5-reactifs-stats` | Statistiques des réactifs | M5 | 8 | 49 | porté |
| `m5-resultats` | Saisie des résultats | M5 | 9 | 21, 28, 31, 40, 43, 58 | porté |
| `m5-resultats-comparatif` | Comparatif des résultats | M5 | 9 | 49 | porté |
| `m5-stats` | Statistiques du laboratoire | M5 | 8 | 28 | porté |
| `m5-unites` | Unités de mesure | M5 | 5 | 1, 95, 105 | porté |
| `m5-valeurs-reference` | Valeurs de référence | M5 | 8 | 1, 28, 95, 105 | porté |

### Tranche 4 · parcours clinique (M1–M4)

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m1-antecedents` | Antécédents & allergies | M1 | 9 | 32, 40, 41 | porté |
| `m1-certificats-externes` | Certificats — patients externes | M1 | 13 | 52 | porté |
| `m1-constantes` | Constantes à l’accueil | M1 | 10 | 34, 41, 44 | porté |
| `m1-contre-reference` | Fiches de contre-référence | M1 | 9 | 41 | porté |
| `m1-documents` | Documents numérisés | M1 | 9 | 23, 32, 90 | porté |
| `m1-dossier-etendu` | Dossier de consultation étendu | M1 | 8 | 21, 36, 41, 46 | porté |
| `m1-dossier-medical` | Dossier médical informatisé | M1 | 9 | 32, 34, 41, 46 | porté |
| `m1-externe` | Patient externe | M1 | 10 | 30, 32, 44, 60, 102 | porté |
| `m1-numerisation` | Plan de numérisation | M1 | 8 | 32 | porté |
| `m1-patient-nouveau` | Ouvrir un dossier patient | M1 | 15 | 2, 97 | porté |
| `m1-patient-profil` | Fiche patient | M1 | 14 | 14, 23, 32, 40, 64 | porté |
| `m1-patients` | Répertoire des patients | M1 | 15 | 2, 10, 15, 21, 23, 27, 32, 43, 46, 55, 64, 71, 75, 79, 80, 81, 82, 83, 84, 85, 86, 87, 92, 96, 97, 98 | porté |
| `m1-pieces` | Certificats & attestations | M1 | 9 | 41, 52 | porté |
| `m1-reference` | Fiches de référence | M1 | 9 | 41 | porté |
| `m2-affichage` | Écran d’appel des patients | M2 | 8 | 44 | porté |
| `m2-agenda` | Agenda | M2 | 8 | 23, 45, 68, 82 | porté |
| `m2-agenda-medecin` | Agenda du médecin | M2 | 7 | 52 | porté |
| `m2-consultation-fiche` | Fiche de consultation | M2 | 7 | 21, 29, 46, 64 | porté |
| `m2-consultations` | Consultations | M2 | 8 | 32, 43, 55 | porté |
| `m2-domicile` | Consultations & soins à domicile | M2 | 8 | — | porté |
| `m2-dossier-consultation-nouveau` | Dossier de consultation — saisie | M2 | 6 | — | porté |
| `m2-dossiers-consultation` | Dossiers de consultation | M2 | 6 | 46, 64 | porté |
| `m2-file-attente` | File d’attente | M2 | 8 | 44 | porté |
| `m2-file-cabinet` | File par cabinet | M2 | 8 | 52 | porté |
| `m2-ordonnance-nouvelle` | Nouvelle ordonnance — saisie | M2 | 6 | — | porté |
| `m2-ordonnances` | Ordonnances | M2 | 6 | 16, 29, 34, 39, 58 | porté |
| `m2-pathologies` | Pathologies & morbidité | M2 | 6 | 1, 29, 95, 105 | porté |
| `m2-prescriptions` | Prescriptions | M2 | 7 | 34 | porté |
| `m2-registre-appels` | Registre des appels | M2 | 8 | 44 | porté |
| `m2-rendezvous` | Rendez-vous & visites | M2 | 8 | 23, 44, 45, 58, 62 | porté |
| `m2-salle-soins` | Salle de soins | M2 | 6 | 34, 39 | porté |
| `m2-visites` | Registre des visites de suivi clinique | M2 | 8 | 23 | porté |
| `m3-administrations` | Administration des traitements | M3 | 8 | — | porté |
| `m3-admissions` | Admissions | M3 | 8 | — | porté |
| `m3-bloc-checklist` | Check-listes du bloc | M3 | 8 | 34, 43, 95, 105 | porté |
| `m3-bloc-cro` | Comptes rendus opératoires | M3 | 8 | 34, 43 | porté |
| `m3-bons-pansements` | Bons de pansement | M3 | 8 | 50 | porté |
| `m3-chambres` | Chambres & lits | M3 | 9 | — | porté |
| `m3-cpa` | Consultation pré-anesthésique | M3 | 8 | 50 | porté |
| `m3-cr-anesthesie` | Comptes rendus d’anesthésie | M3 | 8 | 50 | porté |
| `m3-demande-examen` | Demande d’examen | M3 | 8 | 50 | porté |
| `m3-feuille-temperature` | Feuille de température | M3 | 9 | 34 | porté |
| `m3-glasgow` | Score de Glasgow | M3 | 8 | 43 | porté |
| `m3-observation` | Mise en observation | M3 | 8 | 22, 68 | porté |
| `m3-plan-lits` | Plan des lits | M3 | 9 | 34 | porté |
| `m3-rapport` | Rapport médical | M3 | 8 | — | porté |
| `m3-soins` | Feuille de soins | M3 | 8 | 21 | porté |
| `m3-sortie-avis-medical` | Sortie contre avis médical | M3 | 8 | — | porté |
| `m3-sorties` | Sorties d’hospitalisation | M3 | 8 | 6 | porté |
| `m3-surveillance` | Fiche de surveillance | M3 | 8 | — | porté |
| `m3-transfusion` | Surveillance transfusionnelle | M3 | 8 | — | porté |
| `m3-visites-patients` | Visites aux hospitalisés | M3 | 8 | — | porté |
| `m4-accouchements` | Accouchements | M4 | 5 | 43 | porté |
| `m4-comptes-rendus` | Comptes rendus de maternité | M4 | 5 | 34, 47 | porté |
| `m4-cpn` | CPN & carte maternelle | M4 | 5 | 47 | porté |
| `m4-cpon` | Consultations post-natales (CPoN) | M4 | 5 | 47 | porté |
| `m4-deces` | Registre des décès | M4 | 5 | — | porté |
| `m4-dossier-bebe` | Dossier bébé & soins du nouveau-né | M4 | 5 | — | porté |
| `m4-dossier-obstetrical` | Dossier obstétrical | M4 | 5 | 61 | porté |
| `m4-dossier-obstetrical-nouveau` | Ouvrir un dossier obstétrical | M4 | 5 | — | porté |
| `m4-maternite` | Suivi maternité | M4 | 5 | 47 | porté |
| `m4-naissances` | Registre des naissances | M4 | 5 | — | porté |
| `m4-partogramme` | Partogramme | M4 | 5 | 47 | porté |
| `m4-planification` | Planification familiale | M4 | 5 | 47 | porté |
| `m4-ptme` | Registre PTME | M4 | 5 | — | porté |
| `m4-soins-curatifs` | Soins curatifs & urgences maternité | M4 | 5 | — | porté |
| `m4-sonu` | Registre SONUB / SONUC | M4 | 5 | 47 | porté |

### Tranche 5 · assurances et comptabilité

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m9-assures` | Assurés & cartes | M9 | 6 | 18, 32, 62 | porté |
| `m9-compagnies` | Compagnies partenaires | M9 | 6 | 9, 62 | porté |
| `m9-conventions` | Conventions & garanties | M9 | 6 | 18, 20, 90 | porté |
| `m9-creances` | Créances | M9 | 6 | 62, 76 | porté |
| `m9-dashboard` | Tableau de bord assurances | M9 | 6 | — | porté |
| `m9-facture-mere` | Facture mère assurance | M9 | 6 | 36 | porté |
| `m9-factures-assureur` | Factures mensuelles assureur | M9 | 6 | 20, 76 | porté |
| `m9-historique` | Historique par assureur | M9 | 6 | 20, 82 | porté |
| `m9-prises-en-charge` | Prises en charge | M9 | 6 | — | porté |
| `m9-relances` | Relances | M9 | 6 | — | porté |
| `m12-analytique` | Comptabilité analytique | M12 | 5 | — | porté |
| `m12-balance` | Balance générale & âgée | M12 | 5 | 82 | porté |
| `m12-banques` | Banques & rapprochements | M12 | 5 | — | porté |
| `m12-baseline-2025` | Baseline 2025 | M12 | 5 | 38 | porté |
| `m12-bfr` | Besoin en fonds de roulement | M12 | 5 | 66 | porté |
| `m12-budgets` | Budgets | M12 | 5 | — | porté |
| `m12-cloture` | Exercices & clôtures | M12 | 4 | 43, 69, 71, 76, 80, 83, 87, 102 | porté |
| `m12-compte-resultat` | Compte de résultat | M12 | 5 | 40, 63 | porté |
| `m12-cout-activite` | Coût à l’activité | M12 | 5 | — | porté |
| `m12-dashboard` | Tableau de bord comptable | M12 | 5 | 82 | porté |
| `m12-depenses` | Dépenses journalières | M12 | 5 | 40, 48, 53, 68, 90 | porté |
| `m12-echeances` | Échéances fiscales & paiements | M12 | 5 | 26, 68, 101 | porté |
| `m12-ecritures` | Écritures comptables | M12 | 5 | 7, 13, 43, 53, 82 | porté |
| `m12-etats-financiers` | États financiers | M12 | 5 | 59, 76 | porté |
| `m12-flux-tresorerie` | Tableau des flux de trésorerie | M12 | 5 | 63 | porté |
| `m12-grand-livre` | Grand livre | M12 | 5 | — | porté |
| `m12-immobilisations` | Immobilisations & amortissements | M12 | 5 | 59 | porté |
| `m12-journaux` | Journaux comptables | M12 | 5 | — | porté |
| `m12-ouverture` | Bilan d’ouverture & à-nouveaux | M12 | 5 | 59 | porté |
| `m12-plan-comptable` | Plan comptable OHADA | M12 | 5 | — | porté |
| `m12-seuil-rentabilite` | Seuil de rentabilité | M12 | 5 | 40, 95, 105 | porté |

### Tranche 6 · RH, paie, administration, pilotage, configuration

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `auth-2fa` | Vérification en 2 étapes | AUTH | 20 | — | porté |
| `auth-forgot` | Mot de passe oublié | AUTH | 20 | — | porté |
| `auth-lock` | Écran verrouillé | AUTH | 20 | 27, 71 | porté |
| `auth-reset` | Réinitialisation du mot de passe | AUTH | 20 | 90 | porté |
| `error-403` | Accès refusé | AUTH | 20 | 10 | porté |
| `error-404` | Page introuvable | AUTH | 20 | — | porté |
| `index` | Connexion | AUTH | 20 | — | porté |
| `plan-du-site` | Plan du site | AUTH | 20 | — | porté |
| `cfg-branding` | Identité & papier à en-tête | CFG | 3 | 89 | porté |
| `cfg-catalogue` | Catalogue tarifaire (deux prix) | CFG | 4 | 34 | porté |
| `cfg-centres-couts` | Centres de coûts | CFG | 3 | 17, 58 | porté |
| `cfg-certificats` | Certificats médicaux | CFG | 4 | 24 | porté |
| `cfg-comptabilite` | Paramètres comptables & obligations | CFG | 3 | 26, 89, 95, 101, 105 | porté |
| `cfg-compte` | Mon compte | CFG | 3 | — | porté |
| `cfg-entetes` | Papier à en-tête officiel | CFG | 3 | 34, 89 | porté |
| `cfg-fiscalite` | Paramètres fiscaux (IFU / RCCM) | CFG | 3 | 24, 89, 101 | porté |
| `cfg-imagerie-catalogue` | Catalogue de l’imagerie | CFG | 5 | 1, 51, 95, 105 | porté |
| `cfg-modules` | Activité des modules | CFG | 3 | 28, 55 | porté |
| `cfg-natures-facture` | Natures de facture | CFG | 3 | 17 | porté |
| `cfg-notifications` | Notifications | CFG | 3 | — | porté |
| `cfg-organisation` | Organisation & organigramme | CFG | 3 | 17, 107 | porté |
| `cfg-pair` | Échanges entre postes (mode pair) | CFG | 2 | 85 | porté |
| `cfg-poste` | Ce poste (mode fileul / mère) | CFG | 2 | — | porté |
| `cfg-rappels` | Rappels & messages | CFG | 3 | 1, 95, 105 | porté |
| `cfg-regles` | Règles métier versionnées | CFG | 3 | 25 | porté |
| `cfg-smtp` | Messagerie (SMTP) | CFG | 2 | 86 | porté |
| `cfg-systeme` | Paramètres système | CFG | 3 | 17, 24, 68, 77, 84 | porté |
| `cfg-tarifs` | Référentiel tarifaire | CFG | 4 | 1, 10, 44, 95, 105 | porté |
| `cfg-types-piece` | Types de pièces certifiantes | CFG | 3 | 34 | porté |
| `dash-admin-agent` | Agent administratif | DASH | 2 | 37, 42 | porté |
| `dash-aide-comptable` | Assistant Comptable | DASH | 4 | 43 | porté |
| `dash-aide-soignant` | Aide-soignante | DASH | 3 | 37, 38 | porté |
| `dash-ambulancier` | Ambulance | DASH | 2 | 37, 38 | porté |
| `dash-anesthesiste` | Anesthésiste | DASH | 4 | 43 | porté |
| `dash-assistant-comptable` | Assistant de Direction | DASH | 3 | 37, 38 | porté |
| `dash-caissier` | Caisse | DASH | 2 | 10, 37, 38, 41 | porté |
| `dash-chirurgien` | Chirurgien | DASH | 4 | 43 | porté |
| `dash-comptable` | Comptabilité | DASH | 3 | 37, 38, 82 | porté |
| `dash-echographiste` | Échographie | DASH | 3 | 37, 38, 39 | porté |
| `dash-infirmier` | Infirmier / Sage-femme | DASH | 3 | 37, 38, 47 | porté |
| `dash-laborantin` | Biologiste médical | DASH | 2 | 37, 38, 41 | porté |
| `dash-maternite` | Maternité | DASH | 5 | 61 | porté |
| `dash-medecin` | Médecin | DASH | 3 | 37, 38 | porté |
| `dash-patient` | Espace patient | DASH | 3 | — | porté |
| `dash-pharmacien` | Pharmacie | DASH | 5 | 37, 41 | porté |
| `dash-receptionniste` | Accueil | DASH | 2 | 37, 38, 44 | porté |
| `dash-rh` | Ressources humaines | DASH | 2 | — | porté |
| `dash-stock` | Gestionnaire de stock | DASH | 3 | 37, 38, 41 | porté |
| `dash-surveillant` | Surveillant | DASH | 4 | 37, 38 | porté |
| `ged-archives` | Archivage & conservation | GED | 6 | — | porté |
| `ged-bibliotheque` | Bibliothèque documentaire | GED | 6 | 53 | porté |
| `ged-workflow` | Workflow de validation | GED | 6 | 95 | porté |
| `imp-accueil` | Jeux d’import et historique des lots | IMP | 8 | — | porté |
| `imp-actes` | Importation du catalogue des actes | IMP | 3 | — | porté |
| `imp-analyses` | Importation du catalogue des analyses | IMP | 3 | 94, 95, 105 | porté |
| `imp-assureurs` | Importation des compagnies d’assurance | IMP | 3 | — | porté |
| `imp-fournisseurs` | Importation des fournisseurs | IMP | 4 | — | porté |
| `imp-patients` | Importation du répertoire patients | IMP | 4 | — | porté |
| `imp-personnel` | Importation du personnel | IMP | 2 | — | porté |
| `imp-plan-comptable` | Importation du plan comptable | IMP | 3 | — | porté |
| `imp-soldes-ouverture` | Importation des soldes d’ouverture | IMP | 3 | — | porté |
| `imp-souscripteurs` | Importation des souscripteurs | IMP | 3 | — | porté |
| `m10-assurance-personnel` | Assurance du personnel | M10 | 3 | 27 | porté |
| `m10-badges` | Badges du personnel | M10 | 5 | 56, 68 | porté |
| `m10-badges-impression` | Planche d’impression des badges | M10 | 3 | 56 | porté |
| `m10-badges-modeles` | Modèles de badge | M10 | 3 | 1, 56, 95, 105 | porté |
| `m10-badges-verification` | Vérifier un badge | M10 | 5 | 56 | porté |
| `m10-conges` | Congés | M10 | 4 | 110 | porté |
| `m10-contrats` | Contrats | M10 | 3 | 34, 68 | porté |
| `m10-dashboard` | Tableau de bord RH | M10 | 3 | 77 | porté |
| `m10-employe-profil` | Fiche employé | M10 | 3 | — | porté |
| `m10-evaluations` | Évaluations (NS 131) | M10 | 3 | 14, 33, 68, 102 | porté |
| `m10-evenements` | Événements du personnel | M10 | 3 | 27, 33 | porté |
| `m10-fiches-poste` | Fiches de poste | M10 | 3 | 77 | porté |
| `m10-missions` | Ordres de mission | M10 | 4 | 24, 68, 110 | porté |
| `m10-participations` | Frais de participation | M10 | 3 | 27 | porté |
| `m10-personnel` | Personnel | M10 | 3 | 24, 40, 55, 77 | porté |
| `m10-planning` | Planning & gardes | M10 | 4 | 27, 34, 109 | porté |
| `m10-presences` | Présences & absences | M10 | 4 | 34, 110 | porté |
| `m10-prestataires` | Prestataires externes | M10 | 3 | — | porté |
| `m10-primes` | Primes (NS 132) | M10 | 3 | 8, 27 | porté |
| `m10-propositions-planning` | Propositions de planning | M10 | 20 (universel) | 111 | porté |
| `m10-sanctions` | Sanctions | M10 | 3 | — | porté |
| `m10-securite-entretien` | Sécurité & entretien | M10 | 3 | — | porté |
| `m10-stats-gardes` | Statistiques de garde | M10 | 4 | 27, 110 | porté |
| `m10-stats-permanences` | Statistiques des permanences | M10 | 4 | 40 | porté |
| `m10-stats-presence` | Taux de présence par service | M10 | 4 | 40 | porté |
| `m11-avances` | Avances sur salaire | M11 | 4 | — | porté |
| `m11-bulletins` | Bulletins de paie | M11 | 4 | 10, 24, 55, 77, 82 | porté |
| `m11-calcul` | Calcul de la paie | M11 | 4 | 24, 27, 33, 77 | porté |
| `m11-cotisations` | Cotisations CNSS / ITS / VPS | M11 | 4 | 24, 77 | porté |
| `m11-dashboard` | Tableau de bord paie | M11 | 4 | 77 | porté |
| `m11-heures-sup` | Heures supplémentaires | M11 | 4 | 77 | porté |
| `m11-ortb` | Redevance ORTB | M11 | 4 | 24, 77, 89 | porté |
| `m11-prets-etudes` | Prêts et avances | M11 | 4 | 77 | porté |
| `m11-validation` | Validation Direction | M11 | 4 | 79 | porté |
| `adm-enquetes` | Enquêtes & questionnaires | M13 | 5 | 1, 53, 57, 95, 105 | porté |
| `adm-satisfaction` | Satisfaction des patients | M13 | 5 | 53, 54 | porté |
| `adm-validations` | Validations en attente | M13 | 11 | 54, 89, 94, 105 | porté |
| `enquete-publique` | Fiche d’enquête (lien partagé) | M13 | 11 | — | porté |
| `m13-ambulance` | Interventions ambulance | M13 | 6 | — | porté |
| `m13-courriers` | Courriers (départ / arrivée) | M13 | 6 | 44, 53 | porté |
| `m13-evenements` | Événements & notifications | M13 | 5 | 14, 23 | porté |
| `m13-maintenance` | Parc technique & maintenance | M13 | 4 | 38, 41 | porté |
| `m13-notes-service` | Notes de service | M13 | 5 | — | porté |
| `m13-plan-annuel` | Plan annuel de travail | M13 | 5 | — | porté |
| `m13-repertoire-ambulances` | Répertoire des ambulances | M13 | 8 | 36, 44 | porté |
| `m13-reunions` | Réunions | M13 | 5 | — | porté |
| `m14-audit` | Journal d’audit | M14 | 3 | — | porté |
| `m14-roles` | Rôles & permissions (RBAC) | M14 | 3 | 21, 32, 34 | porté |
| `m14-sauvegardes` | Sauvegardes & restauration | M14 | 3 | 24, 90 | porté |
| `m14-securite-utilisateurs` | Sécurité des utilisateurs | M14 | 1 | 78 | porté |
| `m14-sessions` | Sessions actives | M14 | 3 | 78 | porté |
| `m14-soignants` | Prescripteurs & exécutants de soins | M14 | 3 | 34 | porté |
| `m14-taches` | Tâches planifiées | M14 | 3 | 72, 73, 74 | porté |
| `m14-utilisateurs` | Utilisateurs | M14 | 3 | 91 | porté |
| `mere-a-traiter` | « À traiter » consolidé | MERE | 2 | — | porté |
| `mere-appareils` | Appareils et appairage | MERE | 2 | — | porté |
| `mere-base` | Base de données locale | MERE | 2 | — | porté |
| `mere-cle-clinique` | Clé de clinique | MERE | 2 | — | porté |
| `mere-conflits` | Conflits et doublons | MERE | 2 | — | porté |
| `mere-import` | Import de migration | MERE | 2 | — | porté |
| `mere-indicateurs` | Indicateurs publiés | MERE | 2 | — | porté |
| `mere-integrite` | Intégrité et altérations | MERE | 2 | — | porté |
| `mere-journal-operations` | Journal des opérations | MERE | 2 | — | porté |
| `mere-journal-technique` | Journal technique | MERE | 2 | — | porté |
| `mere-lots-tournee` | Lots de tournée (mobiles) | MERE | 2 | — | porté |
| `mere-mise-en-service` | Assistant de première mise en service | MERE | 2 | — | porté |
| `mere-mises-a-jour` | Mises à jour et compatibilité | MERE | 2 | — | porté |
| `mere-notifications` | Notifications serveur | MERE | 2 | — | porté |
| `mere-plages-baux` | Plages de numéros et baux de stock | MERE | 2 | — | porté |
| `mere-planificateur` | Planificateur | MERE | 2 | — | porté |
| `mere-reinit` | Réinitialisation de production | MERE | 2 | — | porté |
| `mere-relais` | Relais en ligne | MERE | 2 | — | porté |
| `mere-reseau` | Réseau local | MERE | 2 | — | porté |
| `mere-sauvegardes` | Sauvegardes et restauration | MERE | 2 | — | porté |
| `mere-service` | Service et démarrage | MERE | 2 | — | porté |
| `mere-supervision` | Supervision | MERE | 2 | — | porté |
| `dash-admin` | Administrateur | PIL | 1 | 32, 37, 43 | porté |
| `dash-croise` | Tableau de bord dynamique croisé | PIL | 5 | 37, 40, 58, 92, 93 | porté |
| `dash-da` | Statistiques de la Direction | PIL | 5 | 37, 62 | porté |
| `dash-direction` | Direction | PIL | 4 | 10, 12, 15, 37 | porté |
| `m10-cout-agent` | Coût global de l’agent | PIL | 4 | 52, 77 | porté |
| `m12-rentabilite-groupes` | Recettes & charges par groupe | PIL | 5 | 52, 58 | porté |
| `m12-tableau-decisionnel` | Tableau de bord décisionnel | PIL | 4 | 1, 66, 95, 105 | porté |
| `m2-stats-consultations` | Statistiques des consultations | PIL | 5 | 52, 92, 93 | porté |
| `m2-stats-echographie` | Statistiques de l’imagerie médicale | PIL | 6 | 51, 58 | porté |
| `m3-stats-bloc` | Statistiques du bloc & anesthésie | PIL | 7 | 52 | porté |
| `m3-stats-hospitalisations` | Statistiques des hospitalisations | PIL | 8 | — | porté |
| `m4-stats-maternite` | Statistiques maternité & naissances | PIL | 7 | 47 | porté |
| `m5-stats-examens` | Statistiques des examens | PIL | 6 | 52 | porté |
| `rapports-bibliotheque` | Bibliothèque des états | RAP | 20 | — | porté |
| `rapports-direction` | États de la Direction | RAP | 8 | 25 | porté |
| `rapports-generateur` | Générateur de rapports | RAP | 9 | — | porté |
| `rapports-historique` | Historique des éditions | RAP | 9 | — | porté |
| `rls-alertes` | Alertes et notifications | RLS | 1 | — | porté |
| `rls-appareils` | Appareils | RLS | 1 | — | porté |
| `rls-boites` | Boîtes aux lettres | RLS | 1 | — | porté |
| `rls-codes` | Codes d’appairage | RLS | 1 | — | porté |
| `rls-hebergement` | Hébergement | RLS | 1 | — | porté |
| `rls-indicateurs` | Indicateurs reçus | RLS | 1 | — | porté |
| `rls-journal` | Journal d’audit du relais | RLS | 1 | — | porté |
| `rls-opacite` | Preuve d’opacité | RLS | 1 | — | porté |
| `rls-parametres` | Paramètres du relais | RLS | 1 | — | porté |
| `rls-sauvegarde` | Sauvegarde du relais | RLS | 1 | — | porté |
| `rls-superadmin` | Comptes superadmin | RLS | 1 | — | porté |
| `rls-tableau` | Tableau de bord du relais | RLS | 1 | — | porté |
| `aide-apropos` | Aide & À propos | SUP | 20 | 15 | porté |
| `contact-editeur` | Contactez l’éditeur | SUP | 20 | 15, 86 | porté |
| `parametres-hub` | Paramètres système | SUP | 20 | 84, 85, 86, 96 | porté |

