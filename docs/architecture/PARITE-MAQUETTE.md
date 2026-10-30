# Manifeste de parité — maquette → cible

> **ENGENDRÉ** par `prototype_html/build/parite.js` — ne pas éditer. Seuls les statuts se saisissent, dans `docs/architecture/parite-statuts.json`.
> Sources : `packages/referentiels/data/manifeste.json`, `packages/rbac/data/rbac.json`, `prototype_html/build/test-fonctionnel.js`.

| Mesure | Valeur |
|---|---|
| Écrans du manifeste (hors hubs de module) | **321** |
| Hubs de module (un par module, engendrés) | 22 |
| Écrans nommés par au moins un scénario de la maquette | 201 (63 %) |
| Écrans **sans** scénario (recette à écrire) | 120 |
| Écrans portés | 4 |
| Écrans recettés | 0 |
| Scénarios de la maquette analysés | 74 |

> « Nommé par un scénario » est une **estimation par analyse du texte** du banc (un identifiant d'écran cité dans le scénario) : elle dit où une recette existe déjà à reprendre, pas qu'elle couvre tout l'écran.

## Par tranche

| Tranche | Écrans | Avec scénario | Portés | Recettés |
|---|---|---|---|---|
| 1 · caisse + MECeF + impression | 17 | 8 | 4 | 0 |
| 2 · pharmacie, stocks, achats | 27 | 21 | 0 | 0 |
| 3 · laboratoire (imagerie : rangée M2) | 24 | 21 | 0 | 0 |
| 4 · parcours clinique (M1–M4) | 67 | 50 | 0 | 0 |
| 5 · assurances et comptabilité | 31 | 19 | 0 | 0 |
| 6 · RH, paie, administration, pilotage, configuration | 155 | 82 | 0 | 0 |

## Par écran

Colonnes : **Rôles** = nombre de rôles qui voient l'écran (matrice effective) · **Scénarios** = numéros d'ordre dans `test-fonctionnel.js`.

### Tranche 1 · caisse + MECeF + impression

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m8-caisse` | État de caisse journalier | M8 | 8 | 15, 29, 34, 38, 39, 42, 70 | non commencé |
| `m8-dashboard` | Tableau de bord facturation | M8 | 8 | — | non commencé |
| `m8-facturation` | Nouvelle facture | M8 | 7 | 10, 12, 16, 18, 31, 33 | non commencé |
| `m8-facture-avoir` | Factures d’avoir | M8 | 8 | 47 | non commencé |
| `m8-factures` | Factures | M8 | 8 | 11, 29, 47 | porté |
| `m8-operations` | Opérations de caisse | M8 | 8 | 19 | non commencé |
| `m8-paiements` | Paiements | M8 | 7 | — | porté |
| `m8-proforma` | Factures pro-forma | M8 | 8 | — | porté |
| `m8-recettes` | Recettes par période | M8 | 8 | 19 | non commencé |
| `m8-reliquats` | Reliquats | M8 | 8 | 19 | porté |
| `m8-remboursements` | Remboursements & annulations | M8 | 8 | — | non commencé |
| `mecef-avoirs` | Avoirs & annulations | MECEF | 6 | — | non commencé |
| `mecef-config` | Configuration fiscale | MECEF | 5 | — | non commencé |
| `mecef-dashboard` | Tableau de bord fiscal | MECEF | 6 | — | non commencé |
| `mecef-factures` | Factures normalisées | MECEF | 6 | 74 | non commencé |
| `mecef-journal` | Journal des transactions | MECEF | 6 | — | non commencé |
| `mecef-transmission` | Transmission & réponses | MECEF | 6 | — | non commencé |

### Tranche 2 · pharmacie, stocks, achats

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m6-alertes` | Alertes & seuils | M6 | 7 | — | non commencé |
| `m6-dashboard` | Tableau de bord stock | M6 | 6 | — | non commencé |
| `m6-dispensation` | Dispensation | M6 | 7 | 15, 24 | non commencé |
| `m6-etiquetage` | Étiquetage & emplacements | M6 | 7 | 32 | non commencé |
| `m6-inventaire` | Inventaires | M6 | 6 | 65 | non commencé |
| `m6-inventaire-feuille` | Feuille d’inventaire — comptage | M6 | 6 | — | non commencé |
| `m6-lots` | Lots & péremptions (FEFO) | M6 | 6 | 11, 42 | non commencé |
| `m6-mouvements` | Mouvements de stock | M6 | 6 | 31, 42 | non commencé |
| `m6-pertes` | Pertes, casses & rebuts | M6 | 7 | 32 | non commencé |
| `m6-pharmacie-externe` | Pharmacie externe — voie orale | M6 | 7 | — | non commencé |
| `m6-pharmacie-interne` | Pharmacie interne — urgences | M6 | 7 | — | non commencé |
| `m6-point-stock` | Point du stock valorisé | M6 | 7 | 38 | non commencé |
| `m6-point-ventes` | Suivi des ventes | M6 | 7 | 38, 57, 69, 70 | non commencé |
| `m6-produits` | Référentiel produits | M6 | 7 | 3, 11, 54 | non commencé |
| `m6-reprise` | Reprise SAGE 100 | M6 | 5 | 37 | non commencé |
| `m6-stock-detail` | Stock détail (pharmacie) | M6 | 6 | 40 | non commencé |
| `m6-stock-gros` | Stock gros (magasin) | M6 | 5 | 40, 54 | non commencé |
| `m6-transferts` | Transferts gros → détail | M6 | 5 | 4, 40, 42 | non commencé |
| `m7-besoins` | Bons d’expression de besoins | M7 | 20 (universel) | 31, 52, 67 | non commencé |
| `m7-commandes` | Bons de commande | M7 | 7 | 31 | non commencé |
| `m7-ecarts` | Écarts de livraison | M7 | 7 | 31 | non commencé |
| `m7-factures-fournisseurs` | Factures fournisseurs | M7 | 6 | 31 | non commencé |
| `m7-fournisseurs` | Fournisseurs | M7 | 6 | 31 | non commencé |
| `m7-livraisons` | Bons de livraison | M7 | 6 | 31 | non commencé |
| `m7-pv-reception-consommables` | PV de réception — consommables | M7 | 6 | — | non commencé |
| `m7-pv-reception-reactifs` | PV de réception — réactifs | M7 | 7 | 47 | non commencé |
| `m7-receptions` | Réceptions & contrôles | M7 | 7 | 31 | non commencé |

### Tranche 3 · laboratoire (imagerie : rangée M2)

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m2-dashboard-imagerie` | Poste d’imagerie médicale | M2 | 8 | — | non commencé |
| `m2-echographie-galerie` | Galerie des clichés | M2 | 8 | 50 | non commencé |
| `m2-imagerie` | Tableau Échographie | M2 | 7 | 33, 38, 42, 57, 64 | non commencé |
| `m2-imagerie-cr` | Compte rendu d’imagerie — saisie | M2 | 7 | — | non commencé |
| `m2-imagerie-demandes` | Demandes d’imagerie médicale | M2 | 8 | 50, 57, 62, 66 | non commencé |
| `m2-imagerie-irm` | Tableau IRM | M2 | 7 | 62 | non commencé |
| `m2-imagerie-mammographie` | Tableau Mammographie | M2 | 7 | 62 | non commencé |
| `m2-imagerie-radiographie` | Tableau Radiographie | M2 | 7 | 62, 66 | non commencé |
| `m2-imagerie-scanner` | Tableau Scanner | M2 | 7 | 62, 66 | non commencé |
| `m5-banque-sang` | Banque de sang | M5 | 0 | 27 | non commencé |
| `m5-catalogue` | Catalogue des analyses | M5 | 8 | 2 | non commencé |
| `m5-demandes` | Demandes d’analyses | M5 | 9 | 15, 31, 48, 67 | non commencé |
| `m5-demandes-hospitalisation` | Demandes — hospitalisation | M5 | 9 | 48 | non commencé |
| `m5-demandes-maternite` | Demandes — maternité | M5 | 9 | 48 | non commencé |
| `m5-donneurs` | Donneurs & transfusions | M5 | 0 | 27 | non commencé |
| `m5-impression-resultats` | Impression des résultats | M5 | 8 | 48 | non commencé |
| `m5-prelevement` | Salle de prélèvement | M5 | 8 | 27, 40 | non commencé |
| `m5-reactifs` | Réactifs & consommables | M5 | 6 | 27, 33 | non commencé |
| `m5-reactifs-stats` | Statistiques des réactifs | M5 | 8 | 48 | non commencé |
| `m5-resultats` | Saisie des résultats | M5 | 9 | 20, 27, 30, 39, 42, 57 | non commencé |
| `m5-resultats-comparatif` | Comparatif des résultats | M5 | 9 | 48 | non commencé |
| `m5-stats` | Statistiques du laboratoire | M5 | 8 | 27 | non commencé |
| `m5-unites` | Unités de mesure | M5 | 5 | — | non commencé |
| `m5-valeurs-reference` | Valeurs de référence | M5 | 8 | 27 | non commencé |

### Tranche 4 · parcours clinique (M1–M4)

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m1-antecedents` | Antécédents & allergies | M1 | 9 | 31, 39, 40 | non commencé |
| `m1-certificats-externes` | Certificats — patients externes | M1 | 13 | 51 | non commencé |
| `m1-constantes` | Constantes à l’accueil | M1 | 10 | 33, 40, 43 | non commencé |
| `m1-contre-reference` | Fiches de contre-référence | M1 | 9 | 40 | non commencé |
| `m1-documents` | Documents numérisés | M1 | 9 | 22, 31 | non commencé |
| `m1-dossier-etendu` | Dossier de consultation étendu | M1 | 8 | 20, 35, 40, 45 | non commencé |
| `m1-dossier-medical` | Dossier médical informatisé | M1 | 9 | 31, 33, 40, 45 | non commencé |
| `m1-externe` | Patient externe | M1 | 10 | 29, 31, 43, 59 | non commencé |
| `m1-numerisation` | Plan de numérisation | M1 | 8 | 31 | non commencé |
| `m1-patient-nouveau` | Ouvrir un dossier patient | M1 | 15 | 1 | non commencé |
| `m1-patient-profil` | Fiche patient | M1 | 14 | 13, 22, 31, 39, 63 | non commencé |
| `m1-patients` | Répertoire des patients | M1 | 15 | 1, 9, 14, 20, 22, 26, 31, 42, 45, 54, 63, 70, 73 | non commencé |
| `m1-pieces` | Certificats & attestations | M1 | 9 | 40, 51 | non commencé |
| `m1-reference` | Fiches de référence | M1 | 9 | 40 | non commencé |
| `m2-affichage` | Écran d’appel des patients | M2 | 8 | 43 | non commencé |
| `m2-agenda` | Agenda | M2 | 8 | 22, 44, 67 | non commencé |
| `m2-agenda-medecin` | Agenda du médecin | M2 | 7 | 51 | non commencé |
| `m2-consultation-fiche` | Fiche de consultation | M2 | 7 | 20, 28, 45, 63 | non commencé |
| `m2-consultations` | Consultations | M2 | 8 | 31, 42, 54 | non commencé |
| `m2-domicile` | Consultations & soins à domicile | M2 | 8 | — | non commencé |
| `m2-dossier-consultation-nouveau` | Dossier de consultation — saisie | M2 | 6 | — | non commencé |
| `m2-dossiers-consultation` | Dossiers de consultation | M2 | 6 | 45, 63 | non commencé |
| `m2-file-attente` | File d’attente | M2 | 8 | 43 | non commencé |
| `m2-file-cabinet` | File par cabinet | M2 | 8 | 51 | non commencé |
| `m2-ordonnance-nouvelle` | Nouvelle ordonnance — saisie | M2 | 6 | — | non commencé |
| `m2-ordonnances` | Ordonnances | M2 | 6 | 15, 28, 33, 38, 57 | non commencé |
| `m2-pathologies` | Pathologies & morbidité | M2 | 6 | 28 | non commencé |
| `m2-prescriptions` | Prescriptions | M2 | 7 | 33 | non commencé |
| `m2-registre-appels` | Registre des appels | M2 | 8 | 43 | non commencé |
| `m2-rendezvous` | Rendez-vous & visites | M2 | 8 | 22, 43, 44, 57, 61 | non commencé |
| `m2-salle-soins` | Salle de soins | M2 | 6 | 33, 38 | non commencé |
| `m2-visites` | Registre des visites de suivi clinique | M2 | 8 | 22 | non commencé |
| `m3-administrations` | Administration des traitements | M3 | 8 | — | non commencé |
| `m3-admissions` | Admissions | M3 | 8 | — | non commencé |
| `m3-bloc-checklist` | Check-listes du bloc | M3 | 8 | 33, 42 | non commencé |
| `m3-bloc-cro` | Comptes rendus opératoires | M3 | 8 | 33, 42 | non commencé |
| `m3-bons-pansements` | Bons de pansement | M3 | 8 | 49 | non commencé |
| `m3-chambres` | Chambres & lits | M3 | 9 | — | non commencé |
| `m3-cpa` | Consultation pré-anesthésique | M3 | 8 | 49 | non commencé |
| `m3-cr-anesthesie` | Comptes rendus d’anesthésie | M3 | 8 | 49 | non commencé |
| `m3-demande-examen` | Demande d’examen | M3 | 8 | 49 | non commencé |
| `m3-feuille-temperature` | Feuille de température | M3 | 9 | 33 | non commencé |
| `m3-glasgow` | Score de Glasgow | M3 | 8 | 42 | non commencé |
| `m3-observation` | Mise en observation | M3 | 8 | 21, 67 | non commencé |
| `m3-plan-lits` | Plan des lits | M3 | 9 | 33 | non commencé |
| `m3-rapport` | Rapport médical | M3 | 8 | — | non commencé |
| `m3-soins` | Feuille de soins | M3 | 8 | 20 | non commencé |
| `m3-sortie-avis-medical` | Sortie contre avis médical | M3 | 8 | — | non commencé |
| `m3-sorties` | Sorties d’hospitalisation | M3 | 8 | 5 | non commencé |
| `m3-surveillance` | Fiche de surveillance | M3 | 8 | — | non commencé |
| `m3-transfusion` | Surveillance transfusionnelle | M3 | 8 | — | non commencé |
| `m3-visites-patients` | Visites aux hospitalisés | M3 | 8 | — | non commencé |
| `m4-accouchements` | Accouchements | M4 | 5 | 42 | non commencé |
| `m4-comptes-rendus` | Comptes rendus de maternité | M4 | 5 | 33, 46 | non commencé |
| `m4-cpn` | CPN & carte maternelle | M4 | 5 | 46 | non commencé |
| `m4-cpon` | Consultations post-natales (CPoN) | M4 | 5 | 46 | non commencé |
| `m4-deces` | Registre des décès | M4 | 5 | — | non commencé |
| `m4-dossier-bebe` | Dossier bébé & soins du nouveau-né | M4 | 5 | — | non commencé |
| `m4-dossier-obstetrical` | Dossier obstétrical | M4 | 5 | 60 | non commencé |
| `m4-dossier-obstetrical-nouveau` | Ouvrir un dossier obstétrical | M4 | 5 | — | non commencé |
| `m4-maternite` | Suivi maternité | M4 | 5 | 46 | non commencé |
| `m4-naissances` | Registre des naissances | M4 | 5 | — | non commencé |
| `m4-partogramme` | Partogramme | M4 | 5 | 46 | non commencé |
| `m4-planification` | Planification familiale | M4 | 5 | 46 | non commencé |
| `m4-ptme` | Registre PTME | M4 | 5 | — | non commencé |
| `m4-soins-curatifs` | Soins curatifs & urgences maternité | M4 | 5 | — | non commencé |
| `m4-sonu` | Registre SONUB / SONUC | M4 | 5 | 46 | non commencé |

### Tranche 5 · assurances et comptabilité

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `m9-assures` | Assurés & cartes | M9 | 6 | 17, 31, 61 | non commencé |
| `m9-compagnies` | Compagnies partenaires | M9 | 6 | 8, 61 | non commencé |
| `m9-conventions` | Conventions & garanties | M9 | 6 | 17, 19 | non commencé |
| `m9-creances` | Créances | M9 | 6 | 61, 74 | non commencé |
| `m9-dashboard` | Tableau de bord assurances | M9 | 6 | — | non commencé |
| `m9-facture-mere` | Facture mère assurance | M9 | 6 | 35 | non commencé |
| `m9-factures-assureur` | Factures mensuelles assureur | M9 | 6 | 19, 74 | non commencé |
| `m9-historique` | Historique par assureur | M9 | 6 | 19 | non commencé |
| `m9-prises-en-charge` | Prises en charge | M9 | 6 | — | non commencé |
| `m9-relances` | Relances | M9 | 6 | — | non commencé |
| `m12-analytique` | Comptabilité analytique | M12 | 5 | — | non commencé |
| `m12-balance` | Balance générale & âgée | M12 | 5 | — | non commencé |
| `m12-banques` | Banques & rapprochements | M12 | 5 | — | non commencé |
| `m12-baseline-2025` | Baseline 2025 | M12 | 5 | 37 | non commencé |
| `m12-bfr` | Besoin en fonds de roulement | M12 | 5 | 65 | non commencé |
| `m12-budgets` | Budgets | M12 | 5 | — | non commencé |
| `m12-cloture` | Exercices & clôtures | M12 | 4 | 42, 68, 70, 74 | non commencé |
| `m12-compte-resultat` | Compte de résultat | M12 | 5 | 39, 62 | non commencé |
| `m12-cout-activite` | Coût à l’activité | M12 | 5 | — | non commencé |
| `m12-dashboard` | Tableau de bord comptable | M12 | 5 | — | non commencé |
| `m12-depenses` | Dépenses journalières | M12 | 5 | 39, 47, 52, 67 | non commencé |
| `m12-echeances` | Échéances fiscales & paiements | M12 | 5 | 25, 67 | non commencé |
| `m12-ecritures` | Écritures comptables | M12 | 5 | 6, 12, 42, 52 | non commencé |
| `m12-etats-financiers` | États financiers | M12 | 5 | 58, 74 | non commencé |
| `m12-flux-tresorerie` | Tableau des flux de trésorerie | M12 | 5 | 62 | non commencé |
| `m12-grand-livre` | Grand livre | M12 | 5 | — | non commencé |
| `m12-immobilisations` | Immobilisations & amortissements | M12 | 5 | 58 | non commencé |
| `m12-journaux` | Journaux comptables | M12 | 5 | — | non commencé |
| `m12-ouverture` | Bilan d’ouverture & à-nouveaux | M12 | 5 | 58 | non commencé |
| `m12-plan-comptable` | Plan comptable OHADA | M12 | 5 | — | non commencé |
| `m12-seuil-rentabilite` | Seuil de rentabilité | M12 | 5 | 39 | non commencé |

### Tranche 6 · RH, paie, administration, pilotage, configuration

| Écran | Libellé | Module | Rôles | Scénarios | Statut |
|---|---|---|---|---|---|
| `auth-2fa` | Vérification en 2 étapes | AUTH | 20 | — | non commencé |
| `auth-forgot` | Mot de passe oublié | AUTH | 20 | — | non commencé |
| `auth-lock` | Écran verrouillé | AUTH | 20 | 26, 70 | non commencé |
| `auth-reset` | Réinitialisation du mot de passe | AUTH | 20 | — | non commencé |
| `error-403` | Accès refusé | AUTH | 20 | 9 | non commencé |
| `error-404` | Page introuvable | AUTH | 20 | — | non commencé |
| `index` | Connexion | AUTH | 20 | — | non commencé |
| `plan-du-site` | Plan du site | AUTH | 20 | — | non commencé |
| `cfg-branding` | Identité & papier à en-tête | CFG | 3 | — | non commencé |
| `cfg-catalogue` | Catalogue tarifaire (deux prix) | CFG | 4 | 33 | non commencé |
| `cfg-centres-couts` | Centres de coûts | CFG | 3 | 16, 57 | non commencé |
| `cfg-certificats` | Certificats médicaux | CFG | 4 | 23 | non commencé |
| `cfg-comptabilite` | Paramètres comptables & obligations | CFG | 3 | 25 | non commencé |
| `cfg-compte` | Mon compte | CFG | 3 | — | non commencé |
| `cfg-entetes` | Papier à en-tête officiel | CFG | 3 | 33 | non commencé |
| `cfg-fiscalite` | Paramètres fiscaux (IFU / RCCM) | CFG | 3 | 23 | non commencé |
| `cfg-imagerie-catalogue` | Catalogue de l’imagerie | CFG | 3 | 50 | non commencé |
| `cfg-modules` | Activité des modules | CFG | 3 | 27, 54 | non commencé |
| `cfg-natures-facture` | Natures de facture | CFG | 3 | 16 | non commencé |
| `cfg-notifications` | Notifications | CFG | 3 | — | non commencé |
| `cfg-organisation` | Organisation & organigramme | CFG | 3 | 16 | non commencé |
| `cfg-poste` | Ce poste (mode fileul / mère) | CFG | 2 | — | non commencé |
| `cfg-rappels` | Rappels & messages | CFG | 3 | — | non commencé |
| `cfg-regles` | Règles métier versionnées | CFG | 3 | 24 | non commencé |
| `cfg-systeme` | Paramètres système | CFG | 3 | 16, 23, 67 | non commencé |
| `cfg-tarifs` | Référentiel tarifaire | CFG | 4 | 9, 43 | non commencé |
| `cfg-types-piece` | Types de pièces certifiantes | CFG | 3 | 33 | non commencé |
| `dash-admin-agent` | Agent administratif | DASH | 2 | 36, 41 | non commencé |
| `dash-aide-comptable` | Assistant Comptable | DASH | 4 | 42 | non commencé |
| `dash-aide-soignant` | Aide-soignante | DASH | 3 | 36, 37 | non commencé |
| `dash-ambulancier` | Ambulance | DASH | 2 | 36, 37 | non commencé |
| `dash-anesthesiste` | Anesthésiste | DASH | 4 | 42 | non commencé |
| `dash-assistant-comptable` | Assistant de Direction | DASH | 3 | 36, 37 | non commencé |
| `dash-caissier` | Caisse | DASH | 2 | 9, 36, 37, 40 | non commencé |
| `dash-chirurgien` | Chirurgien | DASH | 4 | 42 | non commencé |
| `dash-comptable` | Comptabilité | DASH | 3 | 36, 37 | non commencé |
| `dash-echographiste` | Échographie | DASH | 3 | 36, 37, 38 | non commencé |
| `dash-infirmier` | Infirmier / Sage-femme | DASH | 3 | 36, 37, 46 | non commencé |
| `dash-laborantin` | Biologiste médical | DASH | 2 | 36, 37, 40 | non commencé |
| `dash-maternite` | Maternité | DASH | 5 | 60 | non commencé |
| `dash-medecin` | Médecin | DASH | 3 | 36, 37 | non commencé |
| `dash-patient` | Espace patient | DASH | 3 | — | non commencé |
| `dash-pharmacien` | Pharmacie | DASH | 5 | 36, 40 | non commencé |
| `dash-receptionniste` | Accueil | DASH | 2 | 36, 37, 43 | non commencé |
| `dash-rh` | Ressources humaines | DASH | 2 | — | non commencé |
| `dash-stock` | Gestionnaire de stock | DASH | 3 | 36, 37, 40 | non commencé |
| `dash-surveillant` | Surveillant | DASH | 4 | 36, 37 | non commencé |
| `ged-archives` | Archivage & conservation | GED | 6 | — | non commencé |
| `ged-bibliotheque` | Bibliothèque documentaire | GED | 6 | 52 | non commencé |
| `ged-workflow` | Workflow de validation | GED | 6 | — | non commencé |
| `m10-assurance-personnel` | Assurance du personnel | M10 | 3 | 26 | non commencé |
| `m10-badges` | Badges du personnel | M10 | 5 | 55, 67 | non commencé |
| `m10-badges-impression` | Planche d’impression des badges | M10 | 3 | 55 | non commencé |
| `m10-badges-modeles` | Modèles de badge | M10 | 3 | 55 | non commencé |
| `m10-badges-verification` | Vérifier un badge | M10 | 5 | 55 | non commencé |
| `m10-conges` | Congés | M10 | 3 | — | non commencé |
| `m10-contrats` | Contrats | M10 | 3 | 33, 67 | non commencé |
| `m10-dashboard` | Tableau de bord RH | M10 | 3 | — | non commencé |
| `m10-employe-profil` | Fiche employé | M10 | 3 | — | non commencé |
| `m10-evaluations` | Évaluations (NS 131) | M10 | 3 | 13, 32, 67 | non commencé |
| `m10-evenements` | Événements du personnel | M10 | 3 | 26, 32 | non commencé |
| `m10-fiches-poste` | Fiches de poste | M10 | 3 | — | non commencé |
| `m10-missions` | Ordres de mission | M10 | 3 | 23, 67 | non commencé |
| `m10-participations` | Frais de participation | M10 | 3 | 26 | non commencé |
| `m10-personnel` | Personnel | M10 | 3 | 23, 39, 54 | non commencé |
| `m10-planning` | Planning & gardes | M10 | 4 | 26, 33 | non commencé |
| `m10-presences` | Présences & absences | M10 | 4 | 33 | non commencé |
| `m10-prestataires` | Prestataires externes | M10 | 3 | — | non commencé |
| `m10-primes` | Primes (NS 132) | M10 | 3 | 7, 26 | non commencé |
| `m10-sanctions` | Sanctions | M10 | 3 | — | non commencé |
| `m10-securite-entretien` | Sécurité & entretien | M10 | 3 | — | non commencé |
| `m10-stats-gardes` | Statistiques de garde | M10 | 4 | 26 | non commencé |
| `m10-stats-permanences` | Statistiques des permanences | M10 | 4 | 39 | non commencé |
| `m10-stats-presence` | Taux de présence par service | M10 | 4 | 39 | non commencé |
| `m11-avances` | Avances sur salaire | M11 | 4 | — | non commencé |
| `m11-bulletins` | Bulletins de paie | M11 | 4 | 9, 23, 54 | non commencé |
| `m11-calcul` | Calcul de la paie | M11 | 4 | 23, 26, 32 | non commencé |
| `m11-cotisations` | Cotisations CNSS / ITS / VPS | M11 | 4 | 23 | non commencé |
| `m11-dashboard` | Tableau de bord paie | M11 | 4 | — | non commencé |
| `m11-heures-sup` | Heures supplémentaires | M11 | 4 | — | non commencé |
| `m11-ortb` | Redevance ORTB | M11 | 4 | 23 | non commencé |
| `m11-prets-etudes` | Prêts-études et avances | M11 | 4 | — | non commencé |
| `m11-validation` | Validation Direction | M11 | 4 | — | non commencé |
| `adm-enquetes` | Enquêtes & questionnaires | M13 | 5 | 52, 56 | non commencé |
| `adm-satisfaction` | Satisfaction des patients | M13 | 5 | 52, 53 | non commencé |
| `adm-validations` | Validations en attente | M13 | 7 | 53 | non commencé |
| `enquete-publique` | Fiche d’enquête (lien partagé) | M13 | 11 | — | non commencé |
| `m13-ambulance` | Interventions ambulance | M13 | 6 | — | non commencé |
| `m13-courriers` | Courriers (départ / arrivée) | M13 | 6 | 43, 52 | non commencé |
| `m13-evenements` | Événements & notifications | M13 | 5 | 13, 22 | non commencé |
| `m13-maintenance` | Parc technique & maintenance | M13 | 4 | 37, 40 | non commencé |
| `m13-notes-service` | Notes de service | M13 | 5 | — | non commencé |
| `m13-plan-annuel` | Plan annuel de travail | M13 | 5 | — | non commencé |
| `m13-repertoire-ambulances` | Répertoire des ambulances | M13 | 8 | 35, 43 | non commencé |
| `m13-reunions` | Réunions | M13 | 5 | — | non commencé |
| `m14-audit` | Journal d’audit | M14 | 3 | — | non commencé |
| `m14-roles` | Rôles & permissions (RBAC) | M14 | 3 | 20, 31, 33 | non commencé |
| `m14-sauvegardes` | Sauvegardes & restauration | M14 | 3 | 23 | non commencé |
| `m14-sessions` | Sessions actives | M14 | 3 | — | non commencé |
| `m14-soignants` | Prescripteurs & exécutants de soins | M14 | 3 | 33 | non commencé |
| `m14-taches` | Tâches planifiées | M14 | 3 | 71, 72 | non commencé |
| `m14-utilisateurs` | Utilisateurs | M14 | 3 | — | non commencé |
| `mere-a-traiter` | « À traiter » consolidé | MERE | 2 | — | non commencé |
| `mere-appareils` | Appareils et appairage | MERE | 2 | — | non commencé |
| `mere-base` | Base de données locale | MERE | 2 | — | non commencé |
| `mere-cle-clinique` | Clé de clinique | MERE | 2 | — | non commencé |
| `mere-conflits` | Conflits et doublons | MERE | 2 | — | non commencé |
| `mere-import` | Import de migration | MERE | 2 | — | non commencé |
| `mere-indicateurs` | Indicateurs publiés | MERE | 2 | — | non commencé |
| `mere-integrite` | Intégrité et altérations | MERE | 2 | — | non commencé |
| `mere-journal-operations` | Journal des opérations | MERE | 2 | — | non commencé |
| `mere-journal-technique` | Journal technique | MERE | 2 | — | non commencé |
| `mere-lots-tournee` | Lots de tournée (mobiles) | MERE | 2 | — | non commencé |
| `mere-mise-en-service` | Assistant de première mise en service | MERE | 2 | — | non commencé |
| `mere-mises-a-jour` | Mises à jour et compatibilité | MERE | 2 | — | non commencé |
| `mere-notifications` | Notifications serveur | MERE | 2 | — | non commencé |
| `mere-plages-baux` | Plages de numéros et baux de stock | MERE | 2 | — | non commencé |
| `mere-planificateur` | Planificateur | MERE | 2 | — | non commencé |
| `mere-reinit` | Réinitialisation de production | MERE | 2 | — | non commencé |
| `mere-relais` | Relais en ligne | MERE | 2 | — | non commencé |
| `mere-reseau` | Réseau local | MERE | 2 | — | non commencé |
| `mere-sauvegardes` | Sauvegardes et restauration | MERE | 2 | — | non commencé |
| `mere-service` | Service et démarrage | MERE | 2 | — | non commencé |
| `mere-supervision` | Supervision | MERE | 2 | — | non commencé |
| `dash-admin` | Administrateur | PIL | 1 | 31, 36, 42 | non commencé |
| `dash-croise` | Tableau de bord dynamique croisé | PIL | 5 | 36, 39, 57 | non commencé |
| `dash-da` | Statistiques de la Direction | PIL | 5 | 36, 61 | non commencé |
| `dash-direction` | Direction | PIL | 4 | 9, 11, 14, 36 | non commencé |
| `m10-cout-agent` | Coût global de l’agent | PIL | 4 | 51 | non commencé |
| `m12-rentabilite-groupes` | Recettes & charges par groupe | PIL | 5 | 51, 57 | non commencé |
| `m12-tableau-decisionnel` | Tableau de bord décisionnel | PIL | 4 | 65 | non commencé |
| `m2-stats-consultations` | Statistiques des consultations | PIL | 5 | 51 | non commencé |
| `m2-stats-echographie` | Statistiques de l’imagerie médicale | PIL | 6 | 50, 57 | non commencé |
| `m3-stats-bloc` | Statistiques du bloc & anesthésie | PIL | 7 | 51 | non commencé |
| `m3-stats-hospitalisations` | Statistiques des hospitalisations | PIL | 8 | — | non commencé |
| `m4-stats-maternite` | Statistiques maternité & naissances | PIL | 7 | 46 | non commencé |
| `m5-stats-examens` | Statistiques des examens | PIL | 6 | 51 | non commencé |
| `rapports-bibliotheque` | Bibliothèque des états | RAP | 20 | — | non commencé |
| `rapports-direction` | États de la Direction | RAP | 8 | 24 | non commencé |
| `rapports-generateur` | Générateur de rapports | RAP | 9 | — | non commencé |
| `rapports-historique` | Historique des éditions | RAP | 9 | — | non commencé |
| `rls-alertes` | Alertes et notifications | RLS | 1 | — | non commencé |
| `rls-appareils` | Appareils | RLS | 1 | — | non commencé |
| `rls-boites` | Boîtes aux lettres | RLS | 1 | — | non commencé |
| `rls-codes` | Codes d’appairage | RLS | 1 | — | non commencé |
| `rls-hebergement` | Hébergement (cPanel) | RLS | 1 | — | non commencé |
| `rls-indicateurs` | Indicateurs reçus | RLS | 1 | — | non commencé |
| `rls-journal` | Journal d’audit du relais | RLS | 1 | — | non commencé |
| `rls-opacite` | Preuve d’opacité | RLS | 1 | — | non commencé |
| `rls-parametres` | Paramètres du relais | RLS | 1 | — | non commencé |
| `rls-sauvegarde` | Sauvegarde du relais | RLS | 1 | — | non commencé |
| `rls-superadmin` | Comptes superadmin | RLS | 1 | — | non commencé |
| `rls-tableau` | Tableau de bord du relais | RLS | 1 | — | non commencé |
| `aide-apropos` | Aide & À propos | SUP | 20 | 14 | non commencé |
| `contact-editeur` | Contactez l’éditeur | SUP | 20 | 14 | non commencé |

