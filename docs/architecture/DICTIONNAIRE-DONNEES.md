# Dictionnaire des données — tables PostgreSQL par module

Engendré par `prototype_html/build/gen-schema-pg.js` à partir du magasin du prototype. **Ne pas éditer à la main.**

| Schéma (module) | Tables | Tables filles | Colonnes typées | Fiches observées |
|---|---:|---:|---:|---:|
| `cfg` — Configuration | 12 | 2 | 90 | 568 |
| `ged` — GED | 1 | 0 | 24 | 221 |
| `m1` — M1 Patients & DMI | 6 | 0 | 147 | 430 |
| `m10` — M10 Ressources humaines | 16 | 0 | 97 | 2957 |
| `m11` — M11 Paie & primes | 1 | 0 | 16 | 12 |
| `m12` — M12 Comptabilité SYSCOHADA | 8 | 0 | 85 | 593 |
| `m13` — M13 Administration & ambulance | 9 | 0 | 42 | 90 |
| `m14` — M14 Sécurité & audit | 8 | 0 | 67 | 649 |
| `m2` — M2 RDV, visites, consultations, imagerie | 10 | 3 | 238 | 1219 |
| `m3` — M3 Hospitalisation & bloc | 10 | 2 | 147 | 618 |
| `m4` — M4 Maternité, naissances, décès | 13 | 4 | 283 | 331 |
| `m5` — M5 Laboratoire | 8 | 0 | 129 | 686 |
| `m6` — M6 Pharmacie & stocks | 8 | 1 | 82 | 1286 |
| `m7` — M7 Achats & fournisseurs | 6 | 2 | 55 | 39 |
| `m8` — M8 Facturation & caisse | 2 | 1 | 39 | 409 |
| `m9` — M9 Assurances & créances | 5 | 1 | 48 | 35 |
| `socle` — Socle commun (référentiels lus par plusieurs modules) | 1 | 0 | 28 | 451 |
| `sup` — Support | 1 | 0 | 0 | 0 |

## Détail par table

### `cfg.actes` (collection « actes », 73 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `prix` | prix | integer |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `secteur` | secteur | text |  |
| `assurable` | assurable | boolean |  |
| `code_tarif` | codeTarif | text |  |
| `non_couvert` | nonCouvert | boolean |  |
| `prix_assure` | prixAssure | integer |  |
| `prix_non_assure` | prixNonAssure | integer |  |
| `rapprochement` | rapprochement | text |  |
| `tarif_provisoire` | tarifProvisoire | boolean |  |
| `tarif_arrete_le` | tarifArreteLe | date |  |
| `motif_prix` | motifPrix | text |  |

Table fille `cfg.actes_variantes_grille` — 16 lignes : code text, source text, statut text, famille text, libelle text, a_arbitrer text, arbitrage text, assurable boolean, motif_prix text, non_couvert boolean, prix_assure integer, prix_a_valider boolean, prix_non_assure integer, grille_colonne1 integer, grille_colonne2 integer, inverse_depuis_grille boolean

### `cfg.catalogue_tarifs` (collection « catalogueTarifs », 147 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `famille` | famille | text |  |
| `libelle` | libelle | text |  |
| `a_arbitrer` | aArbitrer | text |  |
| `arbitrage` | arbitrage | text |  |
| `assurable` | assurable | jsonb |  |
| `motif_prix` | motifPrix | text |  |
| `non_couvert` | nonCouvert | boolean |  |
| `prix_assure` | prixAssure | integer |  |
| `prix_a_valider` | prixAValider | boolean |  |
| `prix_non_assure` | prixNonAssure | integer |  |
| `grille_colonne1` | grilleColonne1 | integer |  |
| `grille_colonne2` | grilleColonne2 | jsonb |  |
| `inverse_depuis_grille` | inverseDepuisGrille | boolean |  |
| `tarif_provisoire` | tarifProvisoire | boolean |  |

### `cfg.certificats` (collection « certificats », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `cfg.examens_imagerie` (collection « examensImagerie », 24 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `voie` | voie | text |  |
| `icone` | icone | text |  |
| `label` | label | text |  |
| `statut` | statut | text |  |
| `modalite` | modalite | text |  |
| `tarif_code` | tarifCode | text |  |
| `a_valider` | aValider | text |  |

### `cfg.modeles_message` (collection « modelesMessage », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `cfg.modules_actifs` (collection « modulesActifs », 2 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `actif` | actif | boolean |  |
| `motif` | motif | text |  |
| `ecrans` | ecrans | jsonb |  |
| `module` | module | text |  |
| `ferme_le` | fermeLe | date |  |
| `libelle` | libelle | text |  |
| `ferme_par` | fermePar | text |  |

### `cfg.natures_facture` (collection « naturesFacture », 14 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `ordre` | ordre | integer |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `secteur` | secteur | text |  |

### `cfg.postes` (collection « postes », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `cfg.rappels` (collection « rappels », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `cfg.secteurs` (collection « secteurs », 14 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `role` | role | text |  |
| `ordre` | ordre | integer |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `adjoint` | adjoint | text |  |
| `libelle` | libelle | text |  |
| `responsable` | responsable | text |  |
| `qualification` | qualification | text |  |

### `cfg.types_piece` (collection « typesPiece », 14 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `sigle` | sigle | text |  |
| `statut` | statut | text |  |
| `examens` | examens | jsonb |  |
| `libelle` | libelle | text |  |
| `collision` | collision | text |  |
| `direction` | direction | text |  |
| `tarif_code` | tarifCode | text |  |

### `cfg.variables_imagerie` (collection « variablesImagerie », 280 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `type` | type | text |  |
| `actif` | actif | boolean |  |
| `ordre` | ordre | integer |  |
| `unite` | unite | text |  |
| `examen` | examen | text |  |
| `normal` | normal | text |  |
| `repete` | repete | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `options` | options | jsonb |  |
| `rubrique` | rubrique | text |  |

Table fille `cfg.variables_imagerie_conditionnels` — 97 lignes : code text, quand jsonb, libelle text

### `ged.documents` (collection « documents », 221 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `signe` | signe | boolean |  |
| `format` | format | text |  |
| `statut` | statut | text |  |
| `taille` | taille | integer |  |
| `cree_le` | _creeLe | timestamptz |  |
| `archive` | archive | boolean |  |
| `contenu` | contenu | text |  |
| `libelle` | libelle | text |  |
| `version` | version | integer |  |
| `cree_par` | _creePar | text |  |
| `resultat` | resultat | text |  |
| `categorie` | categorie | text |  |
| `depose_par` | deposePar | text |  |
| `empreinte` | empreinte | text |  |
| `rattache_a` | rattacheA | text |  |
| `reference` | reference | text |  |
| `conservation` | conservation | integer |  |
| `rattachement` | rattachement | text |  |
| `consultations` | consultations | integer |  |
| `etat_validation` | etatValidation | text |  |
| `code_rattachement` | codeRattachement | text |  |
| `empreinte_balance` | empreinteBalance | text |  |

### `m10.assurances_personnel` (collection « assurancesPersonnel », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.badges` (collection « badges », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.bareme_ns131` (collection « baremeNS131 », 4 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `num` | num | text |  |
| `label` | label | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `version` | version | integer |  |
| `criteres` | criteres | jsonb |  |
| `critere_id` | critereId | text |  |
| `date_effet` | dateEffet | date |  |
| `sanctions` | sanctions | jsonb |  |

### `m10.evaluations` (collection « evaluations », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.evenements` (collection « evenements », 9 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `nature` | nature | text |  |
| `portee` | portee | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `libelle` | libelle | text |  |
| `cree_par` | _creePar | text |  |
| `reference` | reference | text |  |
| `beneficiaire` | beneficiaire | text |  |
| `mode_par_defaut` | modeParDefaut | text |  |
| `beneficiaire_id` | beneficiaireId | text |  |
| `montant_par_agent` | montantParAgent | integer |  |
| `periode_paiement` | periodePaiement | text |  |

### `m10.fiches_poste` (collection « fichesPoste », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.grille_primes` (collection « grillePrimes », 11 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `mode` | mode | text |  |
| `label` | label | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `prime_id` | primeId | text |  |
| `version` | version | integer |  |
| `montants` | montants | jsonb |  |
| `date_effet` | dateEffet | date |  |

### `m10.historique_bareme` (collection « historiqueBareme », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.historique_primes` (collection « historiquePrimes », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.missions` (collection « missions », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.modeles_badge` (collection « modelesBadge », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m10.participations` (collection « participations », 387 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `mode` | mode | text |  |
| `agent` | agent | text |  |
| `regle` | regle | boolean |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `agent_id` | agentId | text |  |
| `montant` | montant | integer |  |
| `cree_par` | _creePar | text |  |
| `matricule` | matricule | text |  |
| `reference` | reference | text |  |
| `evenement_id` | evenementId | text | → evenements (FK) |
| `date_reglement` | dateReglement | date |  |
| `periode_retenue` | periodeRetenue | text |  |
| `evenement_libelle` | evenementLibelle | text |  |

### `m10.personnel` (collection « personnel », 44 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `nom` | nom | text |  |
| `cnss` | cnss | text |  |
| `sexe` | sexe | text |  |
| `poste` | poste | text |  |
| `prenom` | prenom | text |  |
| `statut` | statut | text |  |
| `service` | service | text |  |
| `fonction` | fonction | text |  |
| `categorie` | categorie | text |  |
| `matricule` | matricule | text |  |
| `situation` | situation | text |  |
| `telephone` | telephone | text |  |
| `nom_complet` | nomComplet | text |  |
| `salaire_base` | salaireBase | integer |  |
| `date_embauche` | dateEmbauche | date |  |

### `m10.planning` (collection « planning », 1394 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `type` | type | text |  |
| `regime` | regime | text |  |
| `statut` | statut | text |  |
| `employe` | employe | text |  |
| `service` | service | text |  |
| `fonction` | fonction | text |  |
| `employe_id` | employeId | text |  |

### `m10.presences` (collection « presences », 1100 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `etat` | etat | text |  |
| `motif` | motif | text |  |
| `statut` | statut | text |  |
| `employe` | employe | text |  |
| `service` | service | text |  |
| `employe_id` | employeId | text |  |
| `matricule` | matricule | text |  |
| `heure_depart` | heureDepart | text |  |
| `heure_arrivee` | heureArrivee | text |  |

### `m10.regimes_travail` (collection « regimesTravail », 8 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `cycle` | cycle | integer |  |
| `repos` | repos | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `mention` | mention | text |  |
| `fonctions` | fonctions | jsonb |  |
| `vacations` | vacations | jsonb |  |
| `jours_travailles_mois` | joursTravaillesMois | integer |  |
| `honoraire` | honoraire | integer |  |
| `honoraire_mode` | honoraireMode | text |  |
| `honoraire_periodicite` | honorairePeriodicite | text |  |

### `m11.prets_etudes` (collection « pretsEtudes », 12 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `agent` | agent | text |  |
| `objet` | objet | text |  |
| `nature` | nature | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `montant` | montant | integer |  |
| `cree_par` | _creePar | text |  |
| `retenues` | retenues | jsonb |  |
| `employe_id` | employeId | text |  |
| `matricule` | matricule | text |  |
| `reference` | reference | text |  |
| `date_accord` | dateAccord | date |  |
| `autorise_par` | autorisePar | text |  |
| `nb_echeances` | nbEcheances | integer |  |
| `premiere_echeance` | premiereEcheance | text |  |

### `m12.banques` (collection « banques », 4 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `banque` | banque | text |  |
| `devise` | devise | text |  |
| `nature` | nature | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `intitule` | intitule | text |  |
| `numero_compte` | numeroCompte | text |  |
| `statut_compte` | statutCompte | text |  |
| `compte_comptable` | compteComptable | text |  |

### `m12.centres_couts` (collection « centresCouts », 7 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `type` | type | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `responsable` | responsable | text |  |

### `m12.depenses` (collection « depenses », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m12.echeances_fiscales` (collection « echeancesFiscales », 63 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `note` | note | text |  |
| `part` | part | integer |  |
| `paye` | paye | boolean |  |
| `statut` | statut | text |  |
| `famille` | famille | text |  |
| `libelle` | libelle | text |  |
| `montant` | montant | text |  |
| `periode` | periode | text |  |
| `echeance` | echeance | date |  |
| `exercice` | exercice | integer |  |
| `reportee` | reportee | boolean |  |
| `reference` | reference | text |  |
| `validee_par` | valideePar | text |  |
| `declaration` | declaration | text |  |
| `periodicite` | periodicite | text |  |
| `date_paiement` | datePaiement | date |  |
| `paye_le` | payeLe | date |  |
| `paye_par` | payePar | text |  |
| `quittance` | quittance | text |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `modifie_par` | _modifiePar | text |  |

### `m12.ecritures` (collection « ecritures », 506 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `debit` | debit | integer |  |
| `compte` | compte | text |  |
| `credit` | credit | integer |  |
| `numero` | numero | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `journal` | journal | text |  |
| `libelle` | libelle | text |  |
| `origine` | origine | text |  |
| `cree_par` | _creePar | text |  |
| `archive_le` | _archiveLe | timestamptz |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `archive_par` | _archivePar | text |  |
| `modifie_par` | _modifiePar | text |  |
| `compte_libelle` | compteLibelle | text |  |
| `journal_libelle` | journalLibelle | text |  |
| `motif_archivage` | _motifArchivage | text |  |
| `piece_id` | pieceId | text | → pieces (242 orphelin(s) sur 242, pas de FK) |
| `piece_numero` | pieceNumero | text |  |
| `valide_le` | valideLe | date |  |
| `valide_par` | validePar | text |  |
| `centre_cout` | centreCout | text |  |

### `m12.exercices` (collection « exercices », 5 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `fin` | fin | date |  |
| `etat` | etat | text |  |
| `annee` | annee | integer |  |
| `debut` | debut | date |  |
| `motif` | motif | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `valide_le` | valideLe | date |  |
| `valide_par` | validePar | text |  |

### `m12.immobilisations` (collection « immobilisations », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m12.objectifs_pilotage` (collection « objectifsPilotage », 8 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `axe` | axe | text |  |
| `aide` | aide | text |  |
| `sens` | sens | text |  |
| `cible` | cible | integer |  |
| `label` | label | text |  |
| `unite` | unite | text |  |
| `alerte` | alerte | integer |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `a_valider` | aValider | boolean |  |

### `m13.ambulance` (collection « ambulance », 38 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `etat` | etat | text |  |
| `motif` | motif | text |  |
| `tarif` | tarif | integer |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `facture` | facture | boolean |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `chauffeur` | chauffeur | text |  |
| `date_heure` | dateHeure | timestamptz |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `destination` | destination | text |  |
| `kilometrage` | kilometrage | integer |  |
| `patient_code` | patientCode | text |  |
| `accompagnant` | accompagnant | text |  |

### `m13.ambulances` (collection « ambulances », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m13.courriers` (collection « courriers », 34 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `sens` | sens | text |  |
| `objet` | objet | text |  |
| `nature` | nature | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `cree_par` | _creePar | text |  |
| `affecte_a` | affecteA | text |  |
| `numerise` | numerise | boolean |  |
| `reference` | reference | text |  |
| `traitement` | traitement | text |  |
| `correspondant` | correspondant | text |  |
| `accuse_reception` | accuseReception | boolean |  |

### `m13.enquetes` (collection « enquetes », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m13.evenements_etablissement` (collection « evenementsEtablissement », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m13.jetons_enquete` (collection « jetonsEnquete », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m13.materiel` (collection « materiel », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m13.reponses_enquetes` (collection « reponsesEnquetes », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m13.reunions` (collection « reunions », 18 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `lieu` | lieu | text |  |
| `type` | type | text |  |
| `heure` | heure | text |  |
| `statut` | statut | text |  |
| `president` | president | text |  |
| `reference` | reference | text |  |
| `compte_rendu` | compteRendu | boolean |  |
| `ordre_du_jour` | ordreDuJour | text |  |
| `participants` | participants | integer |  |

### `m14.audit` (collection « audit », 400 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `role` | role | text |  |
| `apres` | apres | text |  |
| `avant` | avant | text |  |
| `action` | action | text |  |
| `entite` | entite | text |  |
| `statut` | statut | text |  |
| `reference` | reference | text |  |
| `horodatage` | horodatage | timestamptz |  |
| `utilisateur` | utilisateur | text |  |
| `poste` | poste | text |  |
| `module` | module | text |  |
| `succes` | succes | boolean |  |
| `date_heure` | dateHeure | timestamptz |  |
| `ancienne_valeur` | ancienneValeur | text |  |
| `nouvelle_valeur` | nouvelleValeur | text |  |

### `m14.comptes` (collection « comptes », 112 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `num` | num | text |  |
| `classe` | classe | integer |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `journal` | journal | text |  |
| `libelle` | libelle | text |  |

### `m14.fichiers_sauvegarde` (collection « fichiersSauvegarde », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m14.notifications` (collection « notifications », 100 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `lue` | lue | boolean |  |
| `type` | type | text |  |
| `poste` | poste | text |  |
| `cree_le` | creeLe | timestamptz |  |
| `detail` | detail | text |  |
| `statut` | statut | text |  |
| `cree_le_2` | _creeLe | timestamptz |  |
| `libelle` | libelle | text |  |
| `cree_par` | _creePar | text |  |
| `priorite` | priorite | text |  |
| `demande_id` | demandeId | text |  |
| `facture_id` | factureId | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `destinataire` | destinataire | text |  |
| `ordonnance_id` | ordonnanceId | text |  |

### `m14.rbac` (collection « rbac », 22 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `role` | role | text |  |
| `motif` | motif | text |  |
| `droits` | droits | jsonb |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `defini_le` | definiLe | date |  |
| `defini_par` | definiPar | text |  |
| `droits_ecrans` | droitsEcrans | jsonb |  |
| `libelle_court` | libelleCourt | text |  |
| `libelle_origine` | libelleOrigine | text |  |
| `transfere_a` | transfereA | text |  |
| `accueil` | accueil | text |  |
| `couleur` | couleur | text |  |
| `nouveau` | nouveau | boolean |  |

### `m14.soignants` (collection « soignants », 15 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `poste` | poste | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `execute` | execute | boolean |  |
| `qualite` | qualite | text |  |
| `prescrit` | prescrit | boolean |  |
| `secteurs` | secteurs | jsonb |  |
| `supervise` | supervise | boolean |  |
| `nom_complet` | nomComplet | text |  |
| `personnel_id` | personnelId | text | → personnel (FK) |
| `realise_imagerie` | realiseImagerie | boolean |  |

### `m14.tentatives_connexion` (collection « tentativesConnexion », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m14.utilisateurs` (collection « utilisateurs », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m1.constantes` (collection « constantes », 91 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `fr` | fr | integer |  |
| `id` | id | text |  |
| `imc` | imc | numeric |  |
| `spo2` | spo2 | integer |  |
| `poids` | poids | numeric |  |
| `pouls` | pouls | integer |  |
| `moment` | moment | text |  |
| `statut` | statut | text |  |
| `taille` | taille | integer |  |
| `cree_le` | _creeLe | timestamptz |  |
| `origine` | origine | text |  |
| `patient` | patient | text |  |
| `tension` | tension | text |  |
| `cree_par` | _creePar | text |  |
| `date_heure` | dateHeure | timestamp |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `relevee_par` | releveePar | text |  |
| `tension_dia` | tensionDia | integer |  |
| `tension_sys` | tensionSys | integer |  |
| `patient_code` | patientCode | text |  |
| `temperature` | temperature | numeric |  |
| `dossier_id` | dossierId | text |  |

### `m1.contre_references` (collection « contreReferences », 6 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `service` | service | text |  |
| `cree_par` | _creePar | text |  |
| `evolution` | evolution | text |  |
| `justifiee` | justifiee | boolean |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `chef_service` | chefService | text |  |
| `concordance` | concordance | boolean |  |
| `date_arrivee` | dateArrivee | date |  |
| `hospitalise` | hospitalise | boolean |  |
| `patient_code` | patientCode | text |  |
| `heure_arrivee` | heureArrivee | text |  |
| `observations` | observations | text |  |
| `agent_referent` | agentReferent | text |  |
| `centre_accueil` | centreAccueil | text |  |
| `numero_dossier` | numeroDossier | text |  |
| `numero_reference` | numeroReference | text |  |
| `diagnostic_entree` | diagnosticEntree | text |  |
| `diagnostic_sortie` | diagnosticSortie | text |  |
| `motif_non_justifiee` | motifNonJustifiee | text |  |
| `structure_provenance` | structureProvenance | text |  |

### `m1.documents_patient` (collection « documentsPatient », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m1.fiches_reference` (collection « fichesReference », 30 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `age` | age | integer |  |
| `sens` | sens | text |  |
| `sexe` | sexe | text |  |
| `moyen` | moyen | text |  |
| `pouls` | pouls | integer |  |
| `motifs` | motifs | jsonb |  |
| `numero` | numero | text |  |
| `statut` | statut | text |  |
| `urgent` | urgent | boolean |  |
| `cree_le` | _creeLe | timestamptz |  |
| `adresse` | adresse | text |  |
| `patient` | patient | text |  |
| `tension` | tension | text |  |
| `cree_par` | _creePar | text |  |
| `depart_le` | departLe | text |  |
| `arrivee_le` | arriveeLe | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `symptomes` | symptomes | text |  |
| `contact_nom` | contactNom | text |  |
| `ambulancier` | ambulancier | text |  |
| `patient_code` | patientCode | text |  |
| `temperature` | temperature | numeric |  |
| `traitements` | traitements | text |  |
| `abord_veineux` | abordVeineux | boolean |  |
| `centre_alerte` | centreAlerte | boolean |  |
| `observations` | observations | text |  |
| `agent_referent` | agentReferent | text |  |
| `date_admission` | dateAdmission | date |  |
| `date_reference` | dateReference | date |  |
| `contact_adresse` | contactAdresse | text |  |
| `heure_admission` | heureAdmission | text |  |
| `heure_reference` | heureReference | text |  |
| `centre_destination` | centreDestination | text |  |
| `formation_sanitaire` | formationSanitaire | text |  |

### `m1.patients` (collection « patients », 213 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `nom` | nom | text |  |
| `sexe` | sexe | text |  |
| `prenom` | prenom | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `cree_par` | _creePar | text |  |
| `telephone` | telephone | text |  |
| `archive_le` | _archiveLe | timestamptz |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `archive_par` | _archivePar | text |  |
| `modifie_par` | _modifiePar | text |  |
| `observation` | observation | text |  |
| `motif_archivage` | _motifArchivage | text |  |
| `champ_inconnu_du_schema` | champInconnuDuSchema | text |  |
| `age` | age | integer |  |
| `code` | code | text |  |
| `assure` | assure | boolean |  |
| `adresse` | adresse | text |  |
| `externe` | externe | boolean |  |
| `assureur` | assureur | text |  |
| `quartier` | quartier | text |  |
| `date_creation` | dateCreation | date |  |
| `date_naissance` | dateNaissance | date |  |
| `age_reference_le` | ageReferenceLe | text |  |
| `origine_dossier` | origineDossier | text |  |
| `taux_prise_en_charge` | tauxPriseEnCharge | integer |  |
| `prescripteur_exterieur` | prescripteurExterieur | text |  |
| `allergies` | allergies | text |  |
| `antecedents` | antecedents | text |  |
| `assureur_nom` | assureurNom | text |  |
| `numero_police` | numeroPolice | text |  |
| `groupe_sanguin` | groupeSanguin | text |  |
| `souscripteur_id` | souscripteurId | text | → souscripteurs (FK) |
| `carte_expiration` | carteExpiration | date |  |
| `antecedents_autres` | antecedentsAutres | text |  |
| `personne_a_prevenir` | personneAPrevenir | text |  |
| `traitement_en_cours` | traitementEnCours | text |  |
| `categorie_assurance` | categorieAssurance | text |  |
| `souscripteur` | souscripteur | text |  |
| `matricule` | matricule | text |  |
| `personnel_id` | personnelId | text | → personnel (FK) |
| `fonction_agent` | fonctionAgent | text |  |
| `prise_en_charge_personnel` | priseEnChargePersonnel | boolean |  |

### `m1.pieces` (collection « pieces », 90 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `annee` | annee | integer |  |
| `sigle` | sigle | text |  |
| `numero` | numero | integer |  |
| `remis_a` | remisA | text |  |
| `statut` | statut | text |  |
| `type_id` | typeId | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `contenu` | contenu | text |  |
| `libelle` | libelle | text |  |
| `medecin` | medecin | text |  |
| `montant` | montant | integer |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `direction` | direction | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `couverture` | couverture | text |  |
| `patient_code` | patientCode | text |  |
| `date_delivrance` | dateDelivrance | date |  |

### `m2.cliches_imagerie` (collection « clichesImagerie », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m2.consultations` (collection « consultations », 282 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | timestamptz |  |
| `type` | type | text |  |
| `motif` | motif | text |  |
| `tarif` | tarif | integer |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `medecin` | medecin | text |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `medecin_id` | medecinId | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `diagnostic` | diagnostic | text |  |
| `patient_code` | patientCode | text |  |
| `frais_deplacement` | fraisDeplacement | integer |  |
| `adresse_intervention` | adresseIntervention | text |  |
| `fc` | fc | integer |  |
| `poids` | poids | integer |  |
| `tension` | tension | text |  |
| `conduite` | conduite | text |  |
| `orientation` | orientation | text |  |
| `pathologies` | pathologies | jsonb |  |
| `temperature` | temperature | numeric |  |
| `dossier_reference` | dossierReference | text |  |
| `orientation_label` | orientationLabel | text |  |
| `resume_syndromique` | resumeSyndromique | text |  |
| `pathologies_libelles` | pathologiesLibelles | jsonb |  |
| `pathologie_principale` | pathologiePrincipale | text |  |
| `dossier_consultation_id` | dossierConsultationId | text |  |

### `m2.demandes_imagerie` (collection « demandesImagerie », 35 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `prix` | prix | integer |  |
| `examen` | examen | text |  |
| `statut` | statut | text |  |
| `urgent` | urgent | boolean |  |
| `cree_le` | _creeLe | timestamptz |  |
| `origine` | origine | text |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `modalite` | modalite | text |  |
| `date_heure` | dateHeure | timestamptz |  |
| `facture_id` | factureId | text | → factures (FK) |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `examen_code` | examenCode | text |  |
| `indication` | indication | text |  |
| `motif_tarif` | motifTarif | text |  |
| `modifie_par` | _modifiePar | text |  |
| `patient_code` | patientCode | text |  |
| `ordonnance_id` | ordonnanceId | text |  |
| `prescripteur` | prescripteur | text |  |
| `facture_numero` | factureNumero | text |  |
| `ordonnance_numero` | ordonnanceNumero | text |  |
| `secteur_demandeur` | secteurDemandeur | text |  |
| `bloque_par_paiement` | bloqueParPaiement | boolean |  |
| `dossier_consultation_id` | dossierConsultationId | text |  |
| `regle_le` | regleLe | timestamptz |  |
| `valide_le` | valideLe | timestamptz |  |
| `execute_le` | executeLe | timestamptz |  |

### `m2.dossiers_consultation` (collection « dossiersConsultation », 28 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `age` | age | integer |  |
| `imc` | imc | numeric |  |
| `etat` | etat | text |  |
| `sexe` | sexe | text |  |
| `spo2` | spo2 | integer |  |
| `poids` | poids | integer |  |
| `pouls` | pouls | integer |  |
| `statut` | statut | text |  |
| `taille` | taille | integer |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `recu_par` | recuPar | text |  |
| `tension` | tension | text |  |
| `cree_par` | _creePar | text |  |
| `assureur` | assureur | text |  |
| `histoire` | histoire | text |  |
| `ouvert_le` | ouvertLe | timestamptz |  |
| `soignant` | soignant | text |  |
| `allergies` | allergies | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `type_venue` | typeVenue | text |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `motif_venue` | motifVenue | text |  |
| `modifie_par` | _modifiePar | text |  |
| `date_arrivee` | dateArrivee | date |  |
| `etat_general` | etatGeneral | text |  |
| `patient_code` | patientCode | text |  |
| `temperature` | temperature | numeric |  |
| `ant_medicaux` | ant_medicaux | text |  |
| `heure_arrivee` | heureArrivee | text |  |
| `groupe_sanguin` | groupeSanguin | text |  |
| `dossier_saisi_le` | dossierSaisiLe | timestamptz |  |
| `statut_vaccinal` | statutVaccinal | text |  |
| `ant_chirurgicaux` | ant_chirurgicaux | text |  |
| `electrophorese_hb` | electrophoreseHb | text |  |
| `examens_physiques` | examensPhysiques | jsonb |  |
| `constantes_accueil` | constantesAccueil | jsonb |  |
| `traitement_en_cours` | traitementEnCours | text |  |
| `etat_general_precision` | etatGeneralPrecision | text |  |
| `ant_gyneco_obstetricaux` | ant_gyneco_obstetricaux | text |  |
| `allergies_medicamenteuses` | allergiesMedicamenteuses | text |  |
| `clotur_le` | cloturLe | timestamptz |  |
| `fiches_ids` | fichesIds | jsonb |  |
| `orientation` | orientation | text |  |
| `derniere_fiche_id` | derniereFicheId | text |  |
| `diagnostic_retenu` | diagnosticRetenu | text |  |
| `pathologies_retenues` | pathologiesRetenues | jsonb |  |
| `antecedents_obstetricaux` | antecedentsObstetricaux | jsonb |  |
| `examen_obstetrical` | examenObstetrical | jsonb |  |

### `m2.file_attente` (collection « fileAttente », 19 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `etat` | etat | text |  |
| `motif` | motif | text |  |
| `poste` | poste | text |  |
| `numero` | numero | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `servi_le` | serviLe | timestamptz |  |
| `cree_par` | _creePar | text |  |
| `priorite` | priorite | text |  |
| `appele_par` | appelePar | text |  |
| `arrivee_le` | arriveeLe | timestamptz |  |
| `patient_id` | patientId | text | → patients (FK) |
| `praticien` | praticien | text |  |
| `poste_label` | posteLabel | text |  |
| `patient_code` | patientCode | text |  |

### `m2.ordonnances` (collection « ordonnances », 132 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | timestamptz |  |
| `actes` | actes | jsonb |  |
| `numero` | numero | text |  |
| `statut` | statut | text |  |
| `urgent` | urgent | boolean |  |
| `cree_le` | _creeLe | timestamptz |  |
| `medecin` | medecin | text |  |
| `montant` | montant | integer |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `imagerie` | imagerie | jsonb |  |
| `facture_id` | factureId | text | → factures (FK) |
| `patient_id` | patientId | text | → patients (FK) |
| `modifie_le` | _modifieLe | timestamptz |  |
| `diagnostic` | diagnostic | text |  |
| `modifie_par` | _modifiePar | text |  |
| `patient_code` | patientCode | text |  |
| `statut_actes` | statutActes | text |  |
| `montant_actes` | montantActes | integer |  |
| `facture_numero` | factureNumero | text |  |
| `consultation_id` | consultationId | text |  |
| `statut_analyses` | statutAnalyses | text |  |
| `statut_imagerie` | statutImagerie | text |  |
| `statut_paiement` | statutPaiement | text |  |
| `montant_analyses` | montantAnalyses | integer |  |
| `montant_imagerie` | montantImagerie | integer |  |
| `montant_medicaments` | montantMedicaments | integer |  |
| `statut_dispensation` | statutDispensation | text |  |
| `dossier_consultation_id` | dossierConsultationId | text |  |

Table fille `m2.ordonnances_analyses` — 330 lignes : code text, prix integer, delai text, categorie text, designation text, echantillon text

Table fille `m2.ordonnances_medicaments` — 181 lignes : prix integer, duree text, total integer, unite text, produit text, quantite integer, posologie text, produit_id text

### `m2.pathologies` (collection « pathologies », 55 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `a_valider` | aValider | boolean |  |
| `chapitre` | chapitre | text |  |
| `valide_le` | valideLe | date |  |
| `valide_par` | validePar | text |  |
| `notifiable` | notifiable | boolean |  |

### `m2.prescriptions` (collection « prescriptions », 158 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | timestamptz |  |
| `type` | type | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `montant` | montant | integer |  |
| `origine` | origine | text |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `modalite` | modalite | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `patient_code` | patientCode | text |  |
| `ordonnance_id` | ordonnanceId | text | → ordonnances (FK) |
| `prescripteur` | prescripteur | text |  |
| `prescripteur_id` | prescripteurId | text |  |
| `statut_paiement` | statutPaiement | text |  |
| `secteur_destinataire` | secteurDestinataire | text |  |
| `premier_administrateur` | premierAdministrateur | text |  |
| `assure` | assure | boolean |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `indication` | indication | text |  |
| `modifie_par` | _modifiePar | text |  |
| `admission_id` | admissionId | text |  |

Table fille `m2.prescriptions_lignes` — 305 lignes : prix integer, duree text, libelle text, quantite integer, posologie text, produit_id text, nb_administrations integer, tarif text, famille text, acte_code text, frequence text, motif_tarif text, prix_a_valider boolean

### `m2.resultats_imagerie` (collection « resultatsImagerie », 156 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `age` | age | integer |  |
| `ddr` | ddr | text |  |
| `date` | date | timestamptz |  |
| `examen` | examen | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `annexes` | annexes | text |  |
| `patient` | patient | text |  |
| `rendu_le` | renduLe | timestamptz |  |
| `valeurs` | valeurs | jsonb |  |
| `cree_par` | _creePar | text |  |
| `condition` | condition | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `conclusion` | conclusion | text |  |
| `examen_code` | examenCode | text |  |
| `indication` | indication | text |  |
| `patient_code` | patientCode | text |  |
| `realisateur` | realisateur | text |  |
| `prescripteur` | prescripteur | text |  |
| `realisateur_id` | realisateurId | text |  |
| `demande_reference` | demandeReference | text |  |
| `demande_imagerie_id` | demandeImagerieId | text |  |
| `resultats` | resultats | text |  |
| `prescripteur_id` | prescripteurId | text |  |
| `recommandation` | recommandation | text |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `modifie_par` | _modifiePar | text |  |

### `m2.soins` (collection « soins », 354 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `lit` | lit | text |  |
| `acte` | acte | text |  |
| `date` | date | date |  |
| `etat` | etat | text |  |
| `heure` | heure | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `produit` | produit | text |  |
| `cree_par` | _creePar | text |  |
| `quantite` | quantite | integer |  |
| `soignant` | soignant | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `admission_id` | admissionId | text | → admissions (FK) |
| `patient_code` | patientCode | text |  |
| `observations` | observations | text |  |

### `m3.administrations` (collection « administrations », 125 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `rang` | rang | integer |  |
| `total` | total | integer |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `libelle` | libelle | text |  |
| `patient` | patient | text |  |
| `secteur` | secteur | text |  |
| `cree_par` | _creePar | text |  |
| `modalite` | modalite | text |  |
| `date_heure` | dateHeure | date |  |
| `executant` | executant | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `ligne_index` | ligneIndex | integer |  |
| `executant_id` | executantId | text |  |
| `observation` | observation | text |  |
| `patient_code` | patientCode | text |  |
| `motif_secteur` | motifSecteur | text |  |
| `prescription_id` | prescriptionId | text | → prescriptions (FK) |
| `prescription_ref` | prescriptionRef | text |  |

### `m3.admissions` (collection « admissions », 91 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `lit` | lit | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `chambre` | chambre | text |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `infirmier` | infirmier | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `symptomes` | symptomes | text |  |
| `date_entree` | dateEntree | date |  |
| `date_sortie` | dateSortie | date |  |
| `infirmier_id` | infirmierId | text |  |
| `patient_code` | patientCode | text |  |
| `type_chambre` | typeChambre | text |  |
| `prise_en_charge` | priseEnCharge | text |  |
| `diagnostic_entree` | diagnosticEntree | text |  |

### `m3.checklists_bloc` (collection « checklistsBloc », 52 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `total` | total | integer |  |
| `coches` | coches | integer |  |
| `moment` | moment | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `date_heure` | dateHeure | timestamptz |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `responsable` | responsable | text |  |
| `responsable_id` | responsableId | text |  |

Table fille `m3.checklists_bloc_items` — 546 lignes : coche boolean, label text

### `m3.cpa` (collection « cpa », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m3.cr_operatoires` (collection « crOperatoires », 26 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `cro` | cro | text |  |
| `nip` | nip | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `operateur` | operateur | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `anesthesie` | anesthesie | text |  |
| `operateur_id` | operateurId | text |  |
| `patient_code` | patientCode | text |  |
| `anesthesiste` | anesthesiste | text |  |
| `intervention` | intervention | text |  |
| `aide_operateur` | aideOperateur | text |  |
| `date_operation` | dateOperation | date |  |
| `anesthesiste_id` | anesthesisteId | text |  |
| `aide_operateur_id` | aideOperateurId | text |  |
| `diagnostic_peroperatoire` | diagnosticPeroperatoire | text |  |

### `m3.observations` (collection « observations », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m3.rapports_medicaux` (collection « rapportsMedicaux », 22 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `age` | age | integer |  |
| `sexe` | sexe | text |  |
| `motif` | motif | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `adresse` | adresse | text |  |
| `medecin` | medecin | text |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `anamnese` | anamnese | text |  |
| `evolution` | evolution | text |  |
| `medecin_id` | medecinId | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `telephone` | telephone | text |  |
| `date_entree` | dateEntree | date |  |
| `date_sortie` | dateSortie | date |  |
| `hypotheses` | hypotheses | text |  |
| `patient_code` | patientCode | text |  |
| `examen_physique` | examenPhysique | text |  |
| `diagnostic_retenu` | diagnosticRetenu | text |  |
| `diagnostic_sortie` | diagnosticSortie | text |  |
| `traitement_entree` | traitementEntree | text |  |
| `traitement_sortie` | traitementSortie | text |  |
| `traitement_reajuste` | traitementReajuste | text |  |
| `examens_paracliniques` | examensParacliniques | text |  |

### `m3.releves` (collection « releves », 270 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `fc` | fc | integer |  |
| `fr` | fr | integer |  |
| `id` | id | text |  |
| `date` | date | date |  |
| `spo2` | spo2 | integer |  |
| `heure` | heure | text |  |
| `poids` | poids | integer |  |
| `statut` | statut | text |  |
| `taille` | taille | integer |  |
| `diurese` | diurese | integer |  |
| `tension` | tension | text |  |
| `saisi_par` | saisiPar | text |  |
| `traitement` | traitement | text |  |
| `admission_id` | admissionId | text | → admissions (FK) |
| `temperature` | temperature | numeric |  |

### `m3.scores_glasgow` (collection « scoresGlasgow », 18 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `nip` | nip | text |  |
| `score` | score | integer |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `date_heure` | dateHeure | timestamp |  |
| `evalue_par` | evaluePar | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `evaluateur` | evaluateur | text |  |
| `observation` | observation | text |  |

Table fille `m3.scores_glasgow_axes` — 54 lignes : axe text, points integer, libelle text

### `m3.surveillances_transfusion` (collection « surveillancesTransfusion », 14 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `debut` | debut | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `releves` | releves | integer |  |
| `service` | service | text |  |
| `valeurs` | valeurs | jsonb |  |
| `cree_par` | _creePar | text |  |
| `attendus` | attendus | integer |  |
| `incident` | incident | boolean |  |
| `poche_psl` | pochePSL | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `conclusion` | conclusion | text |  |
| `patient_code` | patientCode | text |  |
| `responsable` | responsable | text |  |
| `responsable_id` | responsableId | text |  |
| `nature_incident` | natureIncident | text |  |

### `m4.accouchements` (collection « accouchements », 48 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `type` | type | text |  |
| `voie` | voie | text |  |
| `actes` | actes | jsonb |  |
| `duree` | duree | text |  |
| `issue` | issue | text |  |
| `statut` | statut | text |  |
| `patient` | patient | text |  |
| `nn_decede` | nnDecede | boolean |  |
| `placenta` | placenta | jsonb |  |
| `date_heure` | dateHeure | timestamptz |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `sage_femme` | sageFemme | text |  |
| `hemorragie` | hemorragie | boolean |  |
| `degre_mort_ne` | degreMortNe | text |  |
| `nn_reference` | nnReference | boolean |  |
| `patient_code` | patientCode | text |  |
| `femme_decedee` | femmeDecedee | boolean |  |
| `femme_referee` | femmeReferee | boolean |  |
| `quantite_sang` | quantiteSang | integer |  |
| `surveillance` | surveillance | jsonb |  |
| `complications` | complications | text |  |
| `mode_delivrance` | modeDelivrance | text |  |
| `gestes_delivrance` | gestesDelivrance | jsonb |  |

### `m4.cpon` (collection « cpon », 20 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `hpp` | hpp | boolean |  |
| `date` | date | date |  |
| `type` | type | text |  |
| `examen` | examen | text |  |
| `statut` | statut | text |  |
| `patient` | patient | text |  |
| `conseil_pf` | conseilPF | boolean |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `sage_femme` | sageFemme | text |  |
| `patient_code` | patientCode | text |  |
| `etat_nouveau_ne` | etatNouveauNe | text |  |
| `etiologie_ante` | etiologieAnte | text |  |
| `accouchement_ref` | accouchementRef | text |  |
| `supplementation` | supplementation | text |  |
| `hemorragie_ante_partum` | hemorragieAntePartum | boolean |  |

### `m4.cr_maternite` (collection « crMaternite », 65 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `cree_le` | creeLe | timestamptz |  |
| `statut` | statut | text |  |
| `suites` | suites | text |  |
| `type_cr` | typeCr | text |  |
| `cree_le_2` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `terme_sa` | termeSA | integer |  |
| `cree_par` | _creePar | text |  |
| `date_heure` | dateHeure | timestamp |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `sage_femme` | sageFemme | text |  |
| `type_label` | typeLabel | text |  |
| `anesthesie` | anesthesie | text |  |
| `indication` | indication | text |  |
| `deroulement` | deroulement | text |  |
| `operateur_id` | operateurId | text |  |
| `patient_code` | patientCode | text |  |
| `sage_femme_id` | sageFemmeId | text |  |
| `complications` | complications | text |  |
| `produit_aspire` | produitAspire | text |  |
| `geste` | geste | text |  |
| `methode` | methode | text |  |
| `date_acte` | dateActe | date |  |
| `counseling` | counseling | boolean |  |
| `prochain_rdv` | prochainRdv | date |  |
| `observations` | observations | text |  |
| `effets_secondaires` | effetsSecondaires | boolean |  |
| `voie` | voie | text |  |
| `apgar1` | apgar1 | integer |  |
| `apgar5` | apgar5 | integer |  |
| `etat_mere` | etatMere | text |  |
| `dechirure` | dechirure | text |  |
| `delivrance` | delivrance | text |  |
| `sexe_enfant` | sexeEnfant | text |  |
| `episiotomie` | episiotomie | boolean |  |
| `poids_enfant` | poidsEnfant | integer |  |
| `presentation` | presentation | text |  |
| `travail_duree` | travailDuree | integer |  |
| `pertes_sanguines` | pertesSanguines | integer |  |

### `m4.deces` (collection « deces », 14 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `lieu` | lieu | text |  |
| `cause` | cause | text |  |
| `statut` | statut | text |  |
| `declare` | declare | boolean |  |
| `medecin` | medecin | text |  |
| `patient` | patient | text |  |
| `date_heure` | dateHeure | timestamptz |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `patient_code` | patientCode | text |  |

### `m4.dossiers_obstetricaux` (collection « dossiersObstetricaux », 24 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `age` | age | integer |  |
| `ddr` | ddr | date |  |
| `dpa` | dpa | date |  |
| `vat` | vat | jsonb |  |
| `plan` | plan | jsonb |  |
| `droits` | droits | jsonb |  |
| `info_pf` | infoPF | text |  |
| `parite` | parite | integer |  |
| `statut` | statut | text |  |
| `taille` | taille | numeric |  |
| `examens` | examens | jsonb |  |
| `gestite` | gestite | integer |  |
| `patient` | patient | text |  |
| `referee` | referee | boolean |  |
| `facteurs` | facteurs | jsonb |  |
| `maladies` | maladies | text |  |
| `quartier` | quartier | text |  |
| `allergies` | allergies | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `sage_femme` | sageFemme | text |  |
| `telephone` | telephone | text |  |
| `date_entree` | dateEntree | date |  |
| `profession` | profession | text |  |
| `referee_par` | refereePar | text |  |
| `avortements` | avortements | integer |  |
| `nationalite` | nationalite | text |  |
| `patient_code` | patientCode | text |  |
| `traitements` | traitements | text |  |
| `classes_meres` | classesMeres | jsonb |  |
| `reference_cpn` | referenceCPN | text |  |
| `transfusions` | transfusions | integer |  |
| `numero_dossier` | numeroDossier | text |  |
| `procreateur_gs` | procreateurGs | text |  |
| `statut_dossier` | statutDossier | text |  |
| `enfants_decedes` | enfantsDecedes | integer |  |
| `enfants_vivants` | enfantsVivants | integer |  |
| `procreateur_nom` | procreateurNom | text |  |
| `personne_contact` | personneContact | text |  |
| `telephone_contact` | telephoneContact | text |  |
| `procreateur_serologie` | procreateurSerologie | text |  |
| `procreateur_profession` | procreateurProfession | text |  |
| `reference_accouchement` | referenceAccouchement | text |  |

### `m4.grossesses` (collection « grossesses », 18 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `sp` | sp | jsonb |  |
| `ddr` | ddr | date |  |
| `dpa` | dpa | date |  |
| `fer` | fer | boolean |  |
| `gar` | gar | boolean |  |
| `vat` | vat | text |  |
| `milda` | milda | boolean |  |
| `statut` | statut | text |  |
| `folates` | folates | boolean |  |
| `patient` | patient | text |  |
| `terme_sa` | termeSA | integer |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `sage_femme` | sageFemme | text |  |
| `mebendazole` | mebendazole | boolean |  |
| `patient_code` | patientCode | text |  |
| `groupe_sanguin` | groupeSanguin | text |  |

Table fille `m4.grossesses_visites` — 49 lignes : n integer, hu integer, pb text, sp text, ta text, fer boolean, imc numeric, omi text, bdcf integer, date date, milda boolean, poids integer, pouls integer, seins text, sucre text, terme text, vulve text, bassin text, rdv_cpn date, urines text, arrivee text, foldine boolean, albumine text, conduite text, plaintes text, speculum text, heure_cpnr text, methode_pf text, muqueuses text, rdv_classe text, conscience text, diagnostic text, inspection text, echographie text, prestataire text, temperature text, counseling_pf boolean, deparasitage boolean, presentation text, signes_danger boolean, toucher_vaginal text, points_ureteraux text, recherche_active text, conseils_nutrition boolean

### `m4.naissances` (collection « naissances », 48 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `pc` | pc | numeric |  |
| `pt` | pt | numeric |  |
| `bcg` | bcg | boolean |  |
| `mere` | mere | text |  |
| `sexe` | sexe | text |  |
| `vpo0` | vpo0 | boolean |  |
| `hep_b0` | hepB0 | boolean |  |
| `poids` | poids | text |  |
| `vit_k1` | vitK1 | boolean |  |
| `apgar1` | apgar1 | integer |  |
| `apgar5` | apgar5 | integer |  |
| `mere_id` | mereId | text |  |
| `statut` | statut | text |  |
| `taille` | taille | integer |  |
| `vivant` | vivant | boolean |  |
| `apgar10` | apgar10 | integer |  |
| `collyre` | collyre | boolean |  |
| `declare` | declare | boolean |  |
| `mere_code` | mereCode | text |  |
| `date_heure` | dateHeure | timestamptz |  |
| `reference` | reference | text |  |
| `soins_fiche` | soinsFiche | jsonb |  |
| `apgar_detail` | apgarDetail | jsonb |  |
| `reanimation` | reanimation | boolean |  |
| `accouchement_id` | accouchementId | text | → accouchements (FK) |

Table fille `m4.naissances_elements24h` — 72 lignes : sein text, heure text, neuro text, cordon text, ictere text, urines text, meconium text, coloration text, respiration integer, temperature text

### `m4.partogrammes` (collection « partogrammes », 6 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `clos` | clos | boolean |  |
| `debut` | debut | timestamptz |  |
| `issue` | issue | text |  |
| `parite` | parite | integer |  |
| `resume` | resume | text |  |
| `statut` | statut | text |  |
| `gestite` | gestite | integer |  |
| `patient` | patient | text |  |
| `rupture` | rupture | timestamptz |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `accoucheur` | accoucheur | text |  |
| `patient_code` | patientCode | text |  |
| `dilatation_finale` | dilatationFinale | integer |  |

Table fille `m4.partogrammes_mesures` — 31 lignes : ta text, bdf integer, heure integer, pouls integer, urines text, liquide text, descente integer, ocytocine text, dilatation integer, temperature text, contractions integer, chevauchement integer, descente_cotee text, duree_contractions text

### `m4.planification_familiale` (collection « planificationFamiliale », 24 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `ddr` | ddr | date |  |
| `rdv` | rdv | date |  |
| `date` | date | date |  |
| `statut` | statut | text |  |
| `methode` | methode | text |  |
| `patient` | patient | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `sage_femme` | sageFemme | text |  |
| `acceptante` | acceptante | text |  |
| `constantes` | constantes | text |  |
| `patient_code` | patientCode | text |  |
| `methode_label` | methodeLabel | text |  |
| `methode_anterieure` | methodeAnterieure | text |  |

### `m4.ptme` (collection « ptme », 6 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `ctm` | ctm | boolean |  |
| `pcr1` | pcr1 | text |  |
| `pcr2` | pcr2 | text |  |
| `ag_hbs` | agHbs | text |  |
| `hep_bj0` | hepBJ0 | boolean |  |
| `statut` | statut | text |  |
| `patient` | patient | text |  |
| `vih_type` | vihType | text |  |
| `duree_arv` | dureeARV | text |  |
| `syphilis` | syphilis | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `allaitement` | allaitement | text |  |
| `patient_code` | patientCode | text |  |
| `charge_virale` | chargeVirale | text |  |
| `pcr_naissance` | pcrNaissance | text |  |
| `protocole_arv` | protocoleARV | text |  |
| `serologie18m` | serologie18m | text |  |
| `vih_trimestre` | vihTrimestre | integer |  |
| `prophylaxie_nn` | prophylaxieNN | integer |  |

Table fille `m4.ptme_dispensations` — 19 lignes : mois text, servie boolean

### `m4.registre_sonu` (collection « registreSONU », 10 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `agent` | agent | text |  |
| `parite` | parite | integer |  |
| `statut` | statut | text |  |
| `gestite` | gestite | integer |  |
| `patient` | patient | text |  |
| `date_heure` | dateHeure | timestamptz |  |
| `evolution` | evolution | text |  |
| `fonctions` | fonctions | jsonb |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `autre_geste` | autreGeste | text |  |
| `evacuation` | evacuation | boolean |  |
| `provenance` | provenance | text |  |
| `patient_code` | patientCode | text |  |
| `heure_fin_gestes` | heureFinGestes | text |  |
| `heure_abord_veineux` | heureAbordVeineux | text |  |
| `diagnostic_evacuation` | diagnosticEvacuation | text |  |

### `m4.soins_curatifs_maternite` (collection « soinsCuratifsMaternite », 16 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `agent` | agent | text |  |
| `statut` | statut | text |  |
| `patient` | patient | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `reference` | reference | text |  |
| `symptomes` | symptomes | text |  |
| `diagnostic` | diagnostic | text |  |
| `traitement` | traitement | text |  |
| `tranche_age` | trancheAge | text |  |
| `patient_code` | patientCode | text |  |
| `femme_observee` | femmeObservee | boolean |  |
| `milda_delivree` | mildaDelivree | boolean |  |
| `urgence_maternite` | urgenceMaternite | text |  |
| `femme_hospitalisee` | femmeHospitalisee | boolean |  |
| `jours_hospitalisation` | joursHospitalisation | integer |  |

### `m4.suivi_maternite` (collection « suiviMaternite », 32 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `cpn` | cpn | integer |  |
| `dpa` | dpa | date |  |
| `date` | date | date |  |
| `poids` | poids | integer |  |
| `risque` | risque | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `terme_sa` | termeSA | integer |  |
| `cree_par` | _creePar | text |  |
| `patient_id` | patientId | text | → patients (FK) |
| `sage_femme` | sageFemme | text |  |
| `patient_code` | patientCode | text |  |
| `observations` | observations | text |  |
| `groupe_sanguin` | groupeSanguin | text |  |

### `m5.analyses` (collection « analyses », 48 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `n` | n | integer |  |
| `id` | id | text |  |
| `code` | code | text |  |
| `prix` | prix | integer |  |
| `delai` | delai | text |  |
| `statut` | statut | text |  |
| `categorie` | categorie | text |  |
| `designation` | designation | text |  |
| `echantillon` | echantillon | text |  |
| `tarif_provisoire` | tarifProvisoire | boolean |  |

### `m5.demandes_analyses` (collection « demandesAnalyses », 358 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `prix` | prix | integer |  |
| `delai` | delai | text |  |
| `statut` | statut | text |  |
| `urgent` | urgent | boolean |  |
| `cree_le` | _creeLe | timestamptz |  |
| `analyse_` | analyse | text |  |
| `origine` | origine | text |  |
| `patient` | patient | text |  |
| `recu_par` | recuPar | text |  |
| `regle_le` | regleLe | timestamptz |  |
| `saisi_le` | saisiLe | timestamptz |  |
| `valeurs` | valeurs | jsonb |  |
| `version` | version | integer |  |
| `cree_par` | _creePar | text |  |
| `resultat` | resultat | text |  |
| `saisi_par` | saisiPar | text |  |
| `valide_le` | valideLe | timestamptz |  |
| `anormales` | anormales | integer |  |
| `categorie` | categorie | text |  |
| `date_heure` | dateHeure | timestamptz |  |
| `patient_id` | patientId | text | → patients (FK) |
| `preleve_le` | preleveLe | timestamptz |  |
| `reference` | reference | text |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `conclusion` | conclusion | text |  |
| `laborantin` | laborantin | text |  |
| `preleve_par` | prelevePar | text |  |
| `recu_labo_le` | recuLaboLe | timestamptz |  |
| `modifie_par` | _modifiePar | text |  |
| `analyse_code` | analyseCode | text |  |
| `code_analyse` | codeAnalyse | text |  |
| `echantillon` | echantillon | text |  |
| `etat_analyse` | etatAnalyse | text |  |
| `patient_code` | patientCode | text |  |
| `ordonnance_id` | ordonnanceId | text | → ordonnances (FK) |
| `preleve_par_id` | preleveParId | text |  |
| `prescripteur` | prescripteur | text |  |
| `statut_paiement` | statutPaiement | text |  |
| `ordonnance_numero` | ordonnanceNumero | text |  |
| `secteur_demandeur` | secteurDemandeur | text |  |
| `bloque_par_paiement` | bloqueParPaiement | boolean |  |
| `qualite_validateur` | qualiteValidateur | text |  |
| `resultat_structure` | resultatStructure | boolean |  |
| `valide_technique_le` | valideTechniqueLe | timestamptz |  |
| `valide_technique_par` | valideTechniquePar | text |  |
| `valide_biologique_par` | valideBiologiquePar | text |  |
| `dossier_consultation_id` | dossierConsultationId | text |  |
| `facture_id` | factureId | text | → factures (FK) |
| `indication` | indication | text |  |
| `hospitalise` | hospitalise | boolean |  |
| `facture_numero` | factureNumero | text |  |
| `origine_demande` | origineDemande | text |  |
| `service_demandeur` | serviceDemandeur | text |  |
| `valide_bio_le` | valideBioLe | date |  |
| `valide_bio_par` | valideBioPar | text |  |

### `m5.donneurs` (collection « donneurs », 9 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `statut` | statut | text |  |
| `reference` | reference | text |  |
| `nom` | nom | text |  |
| `telephone` | telephone | text |  |
| `groupe` | groupe | text |  |
| `dernier_don` | dernierDon | date |  |
| `nb_dons` | nbDons | integer |  |
| `eligible` | eligible | boolean |  |
| `type` | type | text |  |

### `m5.examens_labo` (collection « examensLabo », 70 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `note` | note | text |  |
| `delai` | delai | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `section` | section | text |  |
| `documente` | documente | boolean |  |
| `designation` | designation | text |  |
| `echantillon` | echantillon | text |  |
| `section_bulletin` | sectionBulletin | text |  |
| `section_resultat` | sectionResultat | text |  |

### `m5.plages_reactif` (collection « plagesReactif », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m5.poches` (collection « poches », 15 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `statut` | statut | text |  |
| `reference` | reference | text |  |
| `groupe` | groupe | text |  |
| `volume` | volume | integer |  |
| `date_prelevement` | datePrelevement | date |  |
| `date_peremption` | datePeremption | date |  |
| `donneur` | donneur | text |  |
| `etat` | etat | text |  |
| `reserve` | reserve | boolean |  |

### `m5.unites_labo` (collection « unitesLabo », 23 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `domaine` | domaine | text |  |
| `libelle` | libelle | text |  |
| `symbole` | symbole | text |  |
| `a_valider` | aValider | boolean |  |

### `m5.variables_labo` (collection « variablesLabo », 163 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `max` | max | numeric |  |
| `min` | min | numeric |  |
| `code` | code | text |  |
| `type` | type | text |  |
| `actif` | actif | boolean |  |
| `ordre` | ordre | integer |  |
| `regle` | regle | text |  |
| `unite` | unite | text |  |
| `examen` | examen | text |  |
| `normal` | normal | text |  |
| `parent` | parent | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `section` | section | text |  |
| `valeurs` | valeurs | jsonb |  |
| `a_valider` | aValider | boolean |  |
| `decimales` | decimales | integer |  |
| `retractable` | retractable | boolean |  |
| `examen_libelle` | examenLibelle | text |  |
| `accompagnement` | accompagnement | boolean |  |
| `valide_le` | valideLe | date |  |
| `valide_par` | validePar | text |  |

### `m6.dispensations` (collection « dispensations », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m6.emplacements` (collection « emplacements », 24 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `zone` | zone | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `libelle` | libelle | text |  |
| `capacite` | capacite | text |  |
| `temperature` | temperature | text |  |

### `m6.inventaires` (collection « inventaires », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m6.lots` (collection « lots », 346 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `statut` | statut | text |  |
| `produit` | produit | text |  |
| `numero_lot` | numeroLot | text |  |
| `produit_id` | produitId | text | → produits (FK) |
| `emplacement` | emplacement | text |  |
| `date_peremption` | datePeremption | date |  |
| `quantite_restante` | quantiteRestante | integer |  |

### `m6.mouvements` (collection « mouvements », 678 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `type` | type | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `produit` | produit | text |  |
| `cree_par` | _creePar | text |  |
| `quantite` | quantite | integer |  |
| `produit_id` | produitId | text | → produits (FK) |
| `reference` | reference | text |  |
| `stock_type` | stockType | text |  |
| `type_label` | typeLabel | text |  |
| `utilisateur` | utilisateur | text |  |
| `justificatif` | justificatif | text |  |

### `m6.produits` (collection « produits », 184 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `cump` | cump | numeric |  |
| `stock` | stock | integer |  |
| `unite` | unite | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `categorie` | categorie | text |  |
| `lot_import` | lotImport | text |  |
| `prix_achat` | prixAchat | integer |  |
| `prix_vente` | prixVente | integer |  |
| `stock_gros` | stockGros | integer |  |
| `date_import` | dateImport | date |  |
| `designation` | designation | text |  |
| `emplacement` | emplacement | text |  |
| `fournisseur` | fournisseur | text |  |
| `seuil_alerte` | seuilAlerte | integer |  |
| `stock_detail` | stockDetail | integer |  |
| `valorise_sage` | valoriseSage | boolean |  |
| `seuil_a_valider` | seuilAValider | boolean |  |
| `seuil_confirme_le` | seuilConfirmeLe | date |  |
| `quantite_importee` | quantiteImportee | integer |  |
| `source_valorisation` | sourceValorisation | text |  |
| `valorisation_provisoire` | valorisationProvisoire | boolean |  |

### `m6.transferts` (collection « transferts », 20 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `etat` | etat | text |  |
| `motif` | motif | text |  |
| `unite` | unite | text |  |
| `statut` | statut | text |  |
| `valeur` | valeur | numeric |  |
| `cree_le` | _creeLe | timestamptz |  |
| `produit` | produit | text |  |
| `cree_par` | _creePar | text |  |
| `nb_lignes` | nbLignes | integer |  |
| `quantite` | quantite | integer |  |
| `demandeur` | demandeur | text |  |
| `operateur` | operateur | text |  |
| `reference` | reference | text |  |
| `date_reception` | dateReception | date |  |
| `quantite_totale` | quantiteTotale | integer |  |
| `receptionnaire` | receptionnaire | text |  |

Table fille `m6.transferts_lignes` — 139 lignes : lot text, code text, cump numeric, unite text, produit text, quantite integer, categorie text, produit_id text, peremption date

### `m6.valorisations_sage` (collection « valorisationsSage », 34 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `code` | code | text |  |
| `date` | date | date |  |
| `auteur` | auteur | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `a_valider` | aValider | boolean |  |
| `designation` | designation | text |  |
| `observation` | observation | text |  |
| `prix_revient` | prixRevient | integer |  |

### `m7.besoins` (collection « besoins », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m7.commandes` (collection « commandes », 15 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `statut` | statut | text |  |
| `montant` | montant | integer |  |
| `reference` | reference | text |  |
| `validee_par` | valideePar | text |  |
| `fournisseur` | fournisseur | text |  |
| `date_validation` | dateValidation | date |  |
| `delai_livraison` | delaiLivraison | integer |  |
| `fournisseur_nom` | fournisseurNom | text |  |
| `statut_commande` | statutCommande | text |  |

Table fille `m7.commandes_lignes` — 46 lignes : unite text, montant integer, produit text, quantite integer, produit_id text, prix_unitaire integer

### `m7.factures_fournisseurs` (collection « facturesFournisseurs », 9 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `bl_ref` | blRef | text |  |
| `ecart` | ecart | integer |  |
| `statut` | statut | text |  |
| `echeance` | echeance | date |  |
| `reference` | reference | text |  |
| `commande_ref` | commandeRef | text |  |
| `fournisseur` | fournisseur | text |  |
| `statut_rappro` | statutRappro | text |  |
| `fournisseur_nom` | fournisseurNom | text |  |
| `montant_facture` | montantFacture | integer |  |
| `statut_paiement` | statutPaiement | text |  |
| `montant_livraison` | montantLivraison | integer |  |
| `numero_fournisseur` | numeroFournisseur | text |  |

### `m7.fournisseurs` (collection « fournisseurs », 6 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `ifu` | ifu | text |  |
| `nom` | nom | text |  |
| `tel` | tel | text |  |
| `code` | code | text |  |
| `type` | type | text |  |
| `delai` | delai | integer |  |
| `ville` | ville | text |  |
| `banque` | banque | text |  |
| `cle_rib` | cleRib | text |  |
| `compte` | compte | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `adresse` | adresse | text |  |
| `guichet` | guichet | text |  |
| `habilite` | habilite | boolean |  |
| `code_banque` | codeBanque | text |  |
| `code_client` | codeClient | text |  |
| `certification` | certification | text |  |

### `m7.livraisons` (collection « livraisons », 9 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `statut` | statut | text |  |
| `montant` | montant | integer |  |
| `reference` | reference | text |  |
| `commande_ref` | commandeRef | text |  |
| `controle_par` | controlePar | jsonb |  |
| `fournisseur` | fournisseur | text |  |
| `fournisseur_nom` | fournisseurNom | text |  |
| `statut_reception` | statutReception | text |  |

Table fille `m7.livraisons_lignes` — 24 lignes : ecart integer, unite text, montant integer, produit text, quantite integer, produit_id text, prix_unitaire integer, quantite_livree integer

### `m7.pv_receptions` (collection « pvReceptions », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m8.avoirs` (collection « avoirs », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m8.factures` (collection « factures », 409 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | date |  |
| `type` | type | text |  |
| `numero` | numero | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `assureur` | assureur | text |  |
| `reliquat` | reliquat | integer |  |
| `base_mecef` | baseMecef | integer |  |
| `montant_ht` | montantHT | integer |  |
| `patient_id` | patientId | text | → patients (FK) |
| `modifie_le` | _modifieLe | timestamptz |  |
| `montant_ttc` | montantTTC | integer |  |
| `modifie_par` | _modifiePar | text |  |
| `montant_brut` | montantBrut | integer |  |
| `montant_paye` | montantPaye | integer |  |
| `numero_mecef` | numeroMecef | text |  |
| `part_patient` | partPatient | integer |  |
| `patient_code` | patientCode | text |  |
| `personnel_id` | personnelId | text | → personnel (FK) |
| `statut_mecef` | statutMecef | text |  |
| `total_remise` | totalRemise | integer |  |
| `mode_paiement` | modePaiement | text |  |
| `ordonnance_id` | ordonnanceId | text | → ordonnances (FK) |
| `part_assurance` | partAssurance | integer |  |
| `part_personnel` | partPersonnel | integer |  |
| `statut_paiement` | statutPaiement | text |  |
| `dernier_reglement` | dernierReglement | jsonb |  |
| `ordonnance_numero` | ordonnanceNumero | text |  |
| `taux_prise_en_charge` | tauxPriseEnCharge | integer |  |
| `dossier_consultation_id` | dossierConsultationId | text |  |
| `prise_en_charge_personnel` | priseEnChargePersonnel | boolean |  |
| `origine_demande` | origineDemande | text |  |
| `prescripteur_exterieur` | prescripteurExterieur | text |  |
| `taux_remise` | tauxRemise | integer |  |
| `motif_remise` | motifRemise | text |  |
| `souscripteur` | souscripteur | text |  |

Table fille `m8.factures_lignes` — 1037 lignes : id text, paye_le timestamptz, remise integer, montant integer, paye_par text, acte_code text, quantite integer, categorie text, demande_id text, produit_id text, designation text, montant_brut integer, motif_remise text, part_patient integer, montant_regle integer, part_assureur integer, prix_unitaire integer, part_personnel integer, statut_paiement text, prix_unitaire_net integer, demande_imagerie_id text, taux_remise integer

### `m9.assureurs` (collection « assureurs », 13 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `n` | n | integer |  |
| `id` | id | text |  |
| `nom` | nom | text |  |
| `tel` | tel | jsonb |  |
| `code` | code | text |  |
| `email` | email | text |  |
| `statut` | statut | text |  |
| `assures` | assures | integer |  |
| `convention` | convention | text |  |

### `m9.couvertures_assurance` (collection « couverturesAssurance », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m9.factures_mere` (collection « facturesMere », 13 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `fin` | fin | date |  |
| `etat` | etat | text |  |
| `debut` | debut | date |  |
| `numero` | numero | text |  |
| `statut` | statut | text |  |
| `cree_le` | _creeLe | timestamptz |  |
| `periode` | periode | text |  |
| `cree_par` | _creePar | text |  |
| `controle` | controle | jsonb |  |
| `emise_par` | emisePar | text |  |
| `reliquat` | reliquat | integer |  |
| `compagnie` | compagnie | text |  |
| `nb_factures` | nbFactures | integer |  |
| `date_emission` | dateEmission | date |  |
| `montant_regle` | montantRegle | integer |  |
| `periode_label` | periodeLabel | text |  |
| `pieces_filles` | piecesFilles | jsonb |  |
| `compagnie_code` | compagnieCode | text |  |
| `date_reglement` | dateReglement | date |  |
| `montant_reclame` | montantReclame | integer |  |
| `nb_souscripteurs` | nbSouscripteurs | integer |  |
| `reference_reglement` | referenceReglement | text |  |

Table fille `m9.factures_mere_souscripteurs` — 31 lignes : montant integer, patient integer, assureur integer, nb_factures integer, souscripteur text

### `m9.garanties` (collection « garanties », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|

### `m9.souscripteurs` (collection « souscripteurs », 9 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `nom` | nom | text |  |
| `police` | police | text |  |
| `source` | source | text |  |
| `statut` | statut | text |  |
| `contact` | contact | text |  |
| `date_fin` | dateFin | text |  |
| `assureur` | assureur | text |  |
| `effectif` | effectif | integer |  |
| `categorie` | categorie | text |  |
| `date_debut` | dateDebut | date |  |
| `actes_exclus` | actesExclus | jsonb |  |
| `assureur_nom` | assureurNom | text |  |
| `grille_saisie` | grilleSaisie | boolean |  |
| `produits_exclus` | produitsExclus | jsonb |  |
| `accord_prealable` | accordPrealable | jsonb |  |

### `socle.taches` (collection « taches », 451 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
| `id` | id | text |  |
| `date` | date | timestamptz |  |
| `icon` | icon | text |  |
| `role` | role | text |  |
| `type` | type | text |  |
| `ecran` | ecran | text |  |
| `titre` | titre | text |  |
| `detail` | detail | text |  |
| `fait_le` | faitLe | timestamptz |  |
| `module` | module | text |  |
| `statut` | statut | text |  |
| `urgent` | urgent | boolean |  |
| `cree_le` | _creeLe | timestamptz |  |
| `fait_par` | faitPar | text |  |
| `montant` | montant | integer |  |
| `patient` | patient | text |  |
| `cree_par` | _creePar | text |  |
| `facture_id` | factureId | text | → factures (FK) |
| `reference` | reference | text |  |
| `modifie_le` | _modifieLe | timestamptz |  |
| `modifie_par` | _modifiePar | text |  |
| `patient_code` | patientCode | text |  |
| `ordonnance_id` | ordonnanceId | text | → ordonnances (FK) |
| `facture_numero` | factureNumero | text |  |
| `poste` | poste | text |  |
| `cree_le_2` | creeLe | timestamptz |  |
| `libelle` | libelle | text |  |
| `patient_id` | patientId | text | → patients (FK) |

### `sup.support` (collection « support », 0 fiches)

| Colonne | Champ | Type | Référence |
|---|---|---|---|
