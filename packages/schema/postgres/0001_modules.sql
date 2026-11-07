-- =============================================================================
-- SIGH-CNT — tables relationnelles de TOUS les modules (PostgreSQL)
-- ENGENDRÉ par prototype_html/build/gen-schema-pg.js — ne pas éditer à la main.
-- Une table par collection du magasin, un schéma par module, des tables filles pour
-- les tableaux d'objets, une colonne `extra` pour tout champ non prévu, des clés
-- étrangères là où le jeu courant n'a aucun orphelin. RG-14 : aucune suppression
-- physique côté application — `statut = 'archive'` reste une valeur, pas un DELETE.
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS "cfg";
COMMENT ON SCHEMA "cfg" IS 'Configuration';
CREATE SCHEMA IF NOT EXISTS "ged";
COMMENT ON SCHEMA "ged" IS 'GED';
CREATE SCHEMA IF NOT EXISTS "imp";
COMMENT ON SCHEMA "imp" IS 'Importation de données (IMP)';
CREATE SCHEMA IF NOT EXISTS "m1";
COMMENT ON SCHEMA "m1" IS 'M1 Patients & DMI';
CREATE SCHEMA IF NOT EXISTS "m10";
COMMENT ON SCHEMA "m10" IS 'M10 Ressources humaines';
CREATE SCHEMA IF NOT EXISTS "m11";
COMMENT ON SCHEMA "m11" IS 'M11 Paie & primes';
CREATE SCHEMA IF NOT EXISTS "m12";
COMMENT ON SCHEMA "m12" IS 'M12 Comptabilité SYSCOHADA';
CREATE SCHEMA IF NOT EXISTS "m13";
COMMENT ON SCHEMA "m13" IS 'M13 Administration & ambulance';
CREATE SCHEMA IF NOT EXISTS "m14";
COMMENT ON SCHEMA "m14" IS 'M14 Sécurité & audit';
CREATE SCHEMA IF NOT EXISTS "m2";
COMMENT ON SCHEMA "m2" IS 'M2 RDV, visites, consultations, imagerie';
CREATE SCHEMA IF NOT EXISTS "m3";
COMMENT ON SCHEMA "m3" IS 'M3 Hospitalisation & bloc';
CREATE SCHEMA IF NOT EXISTS "m4";
COMMENT ON SCHEMA "m4" IS 'M4 Maternité, naissances, décès';
CREATE SCHEMA IF NOT EXISTS "m5";
COMMENT ON SCHEMA "m5" IS 'M5 Laboratoire';
CREATE SCHEMA IF NOT EXISTS "m6";
COMMENT ON SCHEMA "m6" IS 'M6 Pharmacie & stocks';
CREATE SCHEMA IF NOT EXISTS "m7";
COMMENT ON SCHEMA "m7" IS 'M7 Achats & fournisseurs';
CREATE SCHEMA IF NOT EXISTS "m8";
COMMENT ON SCHEMA "m8" IS 'M8 Facturation & caisse';
CREATE SCHEMA IF NOT EXISTS "m9";
COMMENT ON SCHEMA "m9" IS 'M9 Assurances & créances';
CREATE SCHEMA IF NOT EXISTS "socle";
COMMENT ON SCHEMA "socle" IS 'Socle commun (référentiels lus par plusieurs modules)';
CREATE SCHEMA IF NOT EXISTS "sup";
COMMENT ON SCHEMA "sup" IS 'Support';

CREATE TABLE IF NOT EXISTS "cfg"."actes" (
  "id" text PRIMARY KEY,
  "code" text,
  "prix" integer,
  "source" text,
  "statut" text,
  "libelle" text,
  "secteur" text,
  "assurable" boolean,
  "code_tarif" text,
  "non_couvert" boolean,
  "prix_assure" integer,
  "prix_non_assure" integer,
  "rapprochement" text,
  "tarif_provisoire" boolean,
  "tarif_arrete_le" date,
  "motif_prix" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."actes" IS 'Collection « actes » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_actes_code" ON "cfg"."actes" ("code");
CREATE INDEX IF NOT EXISTS "ix_actes_statut" ON "cfg"."actes" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."actes_variantes_grille" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "code" text,
  "source" text,
  "statut" text,
  "famille" text,
  "libelle" text,
  "a_arbitrer" text,
  "arbitrage" text,
  "assurable" boolean,
  "motif_prix" text,
  "non_couvert" boolean,
  "prix_assure" integer,
  "prix_a_valider" boolean,
  "prix_non_assure" integer,
  "grille_colonne1" integer,
  "grille_colonne2" integer,
  "inverse_depuis_grille" boolean,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "cfg"."actes" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "cfg"."actes_variantes_grille" IS 'Lignes « variantesGrille » de « actes »';
CREATE TABLE IF NOT EXISTS "cfg"."catalogue_tarifs" (
  "id" text PRIMARY KEY,
  "code" text,
  "source" text,
  "statut" text,
  "famille" text,
  "libelle" text,
  "a_arbitrer" text,
  "arbitrage" text,
  "assurable" jsonb,
  "motif_prix" text,
  "non_couvert" boolean,
  "prix_assure" integer,
  "prix_a_valider" boolean,
  "prix_non_assure" integer,
  "grille_colonne1" integer,
  "grille_colonne2" jsonb,
  "inverse_depuis_grille" boolean,
  "tarif_provisoire" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."catalogue_tarifs" IS 'Collection « catalogueTarifs » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_catalogue_tarifs_code" ON "cfg"."catalogue_tarifs" ("code");
CREATE INDEX IF NOT EXISTS "ix_catalogue_tarifs_statut" ON "cfg"."catalogue_tarifs" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."certificats" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."certificats" IS 'Collection « certificats » — Configuration';
CREATE TABLE IF NOT EXISTS "cfg"."examens_imagerie" (
  "id" text PRIMARY KEY,
  "code" text,
  "voie" text,
  "icone" text,
  "label" text,
  "statut" text,
  "modalite" text,
  "tarif_code" text,
  "a_valider" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."examens_imagerie" IS 'Collection « examensImagerie » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_examens_imagerie_code" ON "cfg"."examens_imagerie" ("code");
CREATE INDEX IF NOT EXISTS "ix_examens_imagerie_statut" ON "cfg"."examens_imagerie" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."historique_obligations" (
  "id" text PRIMARY KEY,
  "code" text,
  "type" text,
  "motif" text,
  "source" text,
  "statut" text,
  "cree_le" timestamptz,
  "date_fin" date,
  "famille" text,
  "libelle" text,
  "retiree" boolean,
  "cree_par" text,
  "valide_le" text,
  "date_effet" text,
  "modifie_le" text,
  "seuil_tele" integer,
  "valide_par" text,
  "archive_le" timestamptz,
  "modifie_le_2" timestamptz,
  "modifie_par" text,
  "archive_par" text,
  "modifie_par_2" text,
  "remplacee_le" timestamptz,
  "cumul_maximum" integer,
  "obligation_id" text,
  "remplacee_par" text,
  "motif_archivage" text,
  "motif_remplacement" text,
  "jour" integer,
  "mois" integer,
  "note" text,
  "part" integer,
  "declaration" text,
  "periodicite" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."historique_obligations" IS 'Collection « historiqueObligations » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_historique_obligations_code" ON "cfg"."historique_obligations" ("code");
CREATE INDEX IF NOT EXISTS "ix_historique_obligations_type" ON "cfg"."historique_obligations" ("type");
CREATE INDEX IF NOT EXISTS "ix_historique_obligations_statut" ON "cfg"."historique_obligations" ("statut");
CREATE INDEX IF NOT EXISTS "ix_historique_obligations_obligation_id" ON "cfg"."historique_obligations" ("obligation_id");
CREATE TABLE IF NOT EXISTS "cfg"."historique_obligations_redevances" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "id" text,
  "code" text,
  "mois" integer,
  "libelle" text,
  "montant" integer,
  "assiette" text,
  "seuil_max" text,
  "seuil_min" integer,
  "categorie" text,
  "mois_label" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "cfg"."historique_obligations" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "cfg"."historique_obligations_redevances" IS 'Lignes « redevances » de « historiqueObligations »';
CREATE TABLE IF NOT EXISTS "cfg"."identite_legale" (
  "bp" text,
  "id" text PRIMARY KEY,
  "fin" text,
  "ifu" text,
  "nom" text,
  "logo" text,
  "pays" text,
  "rccm" text,
  "debut" date,
  "email" text,
  "forme" text,
  "motif" text,
  "sigle" text,
  "cree_le" timestamptz,
  "devise" text,
  "slogan" text,
  "source" text,
  "statut" text,
  "cree_le_2" timestamptz,
  "adresse" text,
  "cree_par" text,
  "version" integer,
  "cree_par_2" text,
  "valide_le" text,
  "regime_tva" text,
  "valide_par" text,
  "archive_le" timestamptz,
  "modifie_le" timestamptz,
  "code_devise" text,
  "telephones" jsonb,
  "archive_par" text,
  "modifie_par" text,
  "autorisation" text,
  "telephone_rdv" text,
  "formule_arrete" text,
  "motif_archivage" text,
  "formule_politesse" text,
  "autorisation_exercice" text,
  "autorisation_exercice_motif" text,
  "modifie_le_2" text,
  "modifie_par_2" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."identite_legale" IS 'Collection « identiteLegale » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_identite_legale_statut" ON "cfg"."identite_legale" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."modeles_message" (
  "id" text PRIMARY KEY,
  "actif" boolean,
  "texte" text,
  "source" text,
  "statut" text,
  "cree_le" timestamptz,
  "libelle" text,
  "cree_par" text,
  "occasion" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."modeles_message" IS 'Collection « modelesMessage » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_modeles_message_statut" ON "cfg"."modeles_message" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."modules_actifs" (
  "id" text PRIMARY KEY,
  "code" text,
  "actif" boolean,
  "motif" text,
  "ecrans" jsonb,
  "module" text,
  "ferme_le" date,
  "libelle" text,
  "ferme_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."modules_actifs" IS 'Collection « modulesActifs » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_modules_actifs_code" ON "cfg"."modules_actifs" ("code");
CREATE TABLE IF NOT EXISTS "cfg"."natures_facture" (
  "id" text PRIMARY KEY,
  "code" text,
  "ordre" integer,
  "source" text,
  "statut" text,
  "libelle" text,
  "secteur" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."natures_facture" IS 'Collection « naturesFacture » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_natures_facture_code" ON "cfg"."natures_facture" ("code");
CREATE INDEX IF NOT EXISTS "ix_natures_facture_statut" ON "cfg"."natures_facture" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."obligations_fiscales" (
  "id" text PRIMARY KEY,
  "code" text,
  "jour" integer,
  "mois" integer,
  "note" text,
  "part" integer,
  "type" text,
  "motif" text,
  "source" text,
  "statut" text,
  "famille" text,
  "libelle" text,
  "valide_le" text,
  "date_effet" text,
  "modifie_le" text,
  "valide_par" text,
  "modifie_le_2" timestamptz,
  "modifie_par" text,
  "modifie_par_2" text,
  "declaration" text,
  "periodicite" text,
  "seuil_tele" integer,
  "cumul_maximum" integer,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."obligations_fiscales" IS 'Collection « obligationsFiscales » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_obligations_fiscales_code" ON "cfg"."obligations_fiscales" ("code");
CREATE INDEX IF NOT EXISTS "ix_obligations_fiscales_type" ON "cfg"."obligations_fiscales" ("type");
CREATE INDEX IF NOT EXISTS "ix_obligations_fiscales_statut" ON "cfg"."obligations_fiscales" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."obligations_fiscales_redevances" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "id" text,
  "code" text,
  "mois" integer,
  "libelle" text,
  "montant" integer,
  "assiette" text,
  "seuil_max" text,
  "seuil_min" integer,
  "categorie" text,
  "mois_label" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "cfg"."obligations_fiscales" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "cfg"."obligations_fiscales_redevances" IS 'Lignes « redevances » de « obligationsFiscales »';
CREATE TABLE IF NOT EXISTS "cfg"."postes" (
  "id" text PRIMARY KEY,
  "chef" boolean,
  "role" text,
  "poste" text,
  "source" text,
  "statut" text,
  "effectif" integer,
  "parent_id" text,
  "titulaire" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."postes" IS 'Collection « postes » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_postes_statut" ON "cfg"."postes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_postes_parent_id" ON "cfg"."postes" ("parent_id");
CREATE TABLE IF NOT EXISTS "cfg"."rappels" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."rappels" IS 'Collection « rappels » — Configuration';
CREATE TABLE IF NOT EXISTS "cfg"."ressources" (
  "id" text PRIMARY KEY,
  "statut" text,
  "libelle" text,
  "type" text,
  "usage" text,
  "donnees" text,
  "fichier" text,
  "taille" integer,
  "cree_le" timestamptz,
  "cree_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."ressources" IS 'Collection « ressources » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_ressources_statut" ON "cfg"."ressources" ("statut");
CREATE INDEX IF NOT EXISTS "ix_ressources_type" ON "cfg"."ressources" ("type");
CREATE TABLE IF NOT EXISTS "cfg"."secteurs" (
  "id" text PRIMARY KEY,
  "code" text,
  "role" text,
  "ordre" integer,
  "source" text,
  "statut" text,
  "adjoint" text,
  "libelle" text,
  "responsable" text,
  "qualification" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."secteurs" IS 'Collection « secteurs » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_secteurs_code" ON "cfg"."secteurs" ("code");
CREATE INDEX IF NOT EXISTS "ix_secteurs_statut" ON "cfg"."secteurs" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."types_piece" (
  "id" text PRIMARY KEY,
  "sigle" text,
  "statut" text,
  "examens" jsonb,
  "libelle" text,
  "collision" text,
  "direction" text,
  "tarif_code" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."types_piece" IS 'Collection « typesPiece » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_types_piece_statut" ON "cfg"."types_piece" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."validations_referentiels" (
  "id" text PRIMARY KEY,
  "cible" text,
  "statut" text,
  "famille" text,
  "libelle" text,
  "valide_le" date,
  "valide_par" text,
  "valide_role" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."validations_referentiels" IS 'Collection « validationsReferentiels » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_validations_referentiels_statut" ON "cfg"."validations_referentiels" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."variables_imagerie" (
  "id" text PRIMARY KEY,
  "code" text,
  "type" text,
  "actif" boolean,
  "ordre" integer,
  "unite" text,
  "examen" text,
  "normal" text,
  "repete" text,
  "statut" text,
  "libelle" text,
  "options" jsonb,
  "rubrique" text,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."variables_imagerie" IS 'Collection « variablesImagerie » — Configuration';
CREATE INDEX IF NOT EXISTS "ix_variables_imagerie_code" ON "cfg"."variables_imagerie" ("code");
CREATE INDEX IF NOT EXISTS "ix_variables_imagerie_type" ON "cfg"."variables_imagerie" ("type");
CREATE INDEX IF NOT EXISTS "ix_variables_imagerie_statut" ON "cfg"."variables_imagerie" ("statut");
CREATE TABLE IF NOT EXISTS "cfg"."variables_imagerie_conditionnels" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "code" text,
  "quand" jsonb,
  "libelle" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "cfg"."variables_imagerie" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "cfg"."variables_imagerie_conditionnels" IS 'Lignes « conditionnels » de « variablesImagerie »';
CREATE TABLE IF NOT EXISTS "ged"."documents" (
  "id" text PRIMARY KEY,
  "date" date,
  "signe" boolean,
  "format" text,
  "statut" text,
  "taille" integer,
  "cree_le" timestamptz,
  "archive" boolean,
  "contenu" text,
  "libelle" text,
  "version" integer,
  "cree_par" text,
  "resultat" integer,
  "categorie" text,
  "depose_par" text,
  "empreinte" text,
  "rattache_a" text,
  "reference" text,
  "conservation" integer,
  "rattachement" text,
  "consultations" integer,
  "etat_validation" text,
  "archive_exercice" text,
  "code_rattachement" text,
  "empreinte_balance" text,
  "manifeste_empreinte" text,
  "extra" jsonb
);
COMMENT ON TABLE "ged"."documents" IS 'Collection « documents » — GED';
CREATE INDEX IF NOT EXISTS "ix_documents_date" ON "ged"."documents" ("date");
CREATE INDEX IF NOT EXISTS "ix_documents_statut" ON "ged"."documents" ("statut");
CREATE INDEX IF NOT EXISTS "ix_documents_reference" ON "ged"."documents" ("reference");
CREATE TABLE IF NOT EXISTS "imp"."lots_importation" (
  "id" text PRIMARY KEY,
  "statut" text,
  "reference" text,
  "jeu" text,
  "jeu_libelle" text,
  "fichier" text,
  "empreinte" text,
  "date" date,
  "par" text,
  "valide_par" text,
  "etat" text,
  "nb_lignes" integer,
  "nb_avertissements" integer,
  "nb_refus" integer,
  "erreurs_total" integer,
  "cree_le" timestamptz,
  "cree_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "imp"."lots_importation" IS 'Collection « lotsImportation » — Importation de données (IMP)';
CREATE INDEX IF NOT EXISTS "ix_lots_importation_statut" ON "imp"."lots_importation" ("statut");
CREATE INDEX IF NOT EXISTS "ix_lots_importation_reference" ON "imp"."lots_importation" ("reference");
CREATE INDEX IF NOT EXISTS "ix_lots_importation_date" ON "imp"."lots_importation" ("date");
CREATE INDEX IF NOT EXISTS "ix_lots_importation_etat" ON "imp"."lots_importation" ("etat");
CREATE TABLE IF NOT EXISTS "imp"."lots_importation_ecrits" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "collection" text,
  "id" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "imp"."lots_importation" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "imp"."lots_importation_ecrits" IS 'Lignes « ecrits » de « lotsImportation »';
CREATE TABLE IF NOT EXISTS "imp"."lots_importation_erreurs" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "n" integer,
  "colonne" text,
  "valeur" text,
  "code" text,
  "niveau" text,
  "motif" text,
  "geste" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "imp"."lots_importation" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "imp"."lots_importation_erreurs" IS 'Lignes « erreurs » de « lotsImportation »';
CREATE TABLE IF NOT EXISTS "m10"."assurances_personnel" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."assurances_personnel" IS 'Collection « assurancesPersonnel » — M10 Ressources humaines';
CREATE TABLE IF NOT EXISTS "m10"."badges" (
  "id" text PRIMARY KEY,
  "etat" text,
  "agent" text,
  "photo" text,
  "poste" text,
  "emis_le" date,
  "numero" text,
  "statut" text,
  "emis_par" text,
  "remis_le" date,
  "service" text,
  "expire_le" date,
  "modele_id" text,
  "retire_le" text,
  "matricule" text,
  "personnel_id" text,
  "motif_retrait" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."badges" IS 'Collection « badges » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_badges_etat" ON "m10"."badges" ("etat");
CREATE INDEX IF NOT EXISTS "ix_badges_numero" ON "m10"."badges" ("numero");
CREATE INDEX IF NOT EXISTS "ix_badges_statut" ON "m10"."badges" ("statut");
CREATE INDEX IF NOT EXISTS "ix_badges_modele_id" ON "m10"."badges" ("modele_id");
CREATE INDEX IF NOT EXISTS "ix_badges_personnel_id" ON "m10"."badges" ("personnel_id");
CREATE TABLE IF NOT EXISTS "m10"."bareme_ns131" (
  "id" text PRIMARY KEY,
  "num" text,
  "label" text,
  "source" text,
  "statut" text,
  "version" integer,
  "criteres" jsonb,
  "critere_id" text,
  "date_effet" date,
  "sanctions" jsonb,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."bareme_ns131" IS 'Collection « baremeNS131 » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_bareme_ns131_statut" ON "m10"."bareme_ns131" ("statut");
CREATE INDEX IF NOT EXISTS "ix_bareme_ns131_critere_id" ON "m10"."bareme_ns131" ("critere_id");
CREATE TABLE IF NOT EXISTS "m10"."beneficiaires_primes" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."beneficiaires_primes" IS 'Collection « beneficiairesPrimes » — M10 Ressources humaines';
CREATE TABLE IF NOT EXISTS "m10"."conges" (
  "id" text PRIMARY KEY,
  "duree" integer,
  "nature" text,
  "statut" text,
  "date_fin" date,
  "employe" text,
  "service" text,
  "date_debut" date,
  "employe_id" text,
  "matricule" text,
  "reference" text,
  "remplacant" text,
  "statut_conge" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."conges" IS 'Collection « conges » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_conges_nature" ON "m10"."conges" ("nature");
CREATE INDEX IF NOT EXISTS "ix_conges_statut" ON "m10"."conges" ("statut");
CREATE INDEX IF NOT EXISTS "ix_conges_employe_id" ON "m10"."conges" ("employe_id");
CREATE INDEX IF NOT EXISTS "ix_conges_reference" ON "m10"."conges" ("reference");
CREATE TABLE IF NOT EXISTS "m10"."contrats" (
  "id" text PRIMARY KEY,
  "essai" text,
  "poste" text,
  "nature" text,
  "statut" text,
  "date_fin" date,
  "employe" text,
  "salaire" integer,
  "fonction" text,
  "date_debut" date,
  "employe_id" text,
  "matricule" text,
  "reference" text,
  "statut_contrat" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."contrats" IS 'Collection « contrats » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_contrats_nature" ON "m10"."contrats" ("nature");
CREATE INDEX IF NOT EXISTS "ix_contrats_statut" ON "m10"."contrats" ("statut");
CREATE INDEX IF NOT EXISTS "ix_contrats_employe_id" ON "m10"."contrats" ("employe_id");
CREATE INDEX IF NOT EXISTS "ix_contrats_reference" ON "m10"."contrats" ("reference");
CREATE TABLE IF NOT EXISTS "m10"."evaluations" (
  "id" text PRIMARY KEY,
  "statut" text,
  "employe" text,
  "periode" text,
  "service" text,
  "criteres" jsonb,
  "fonction" text,
  "categorie" text,
  "employe_id" text,
  "matricule" text,
  "reference" text,
  "date_bareme" date,
  "evaluateur" text,
  "salaire_brut" integer,
  "observations" text,
  "prelevement_pct" integer,
  "prelevement_montant" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."evaluations" IS 'Collection « evaluations » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_evaluations_statut" ON "m10"."evaluations" ("statut");
CREATE INDEX IF NOT EXISTS "ix_evaluations_periode" ON "m10"."evaluations" ("periode");
CREATE INDEX IF NOT EXISTS "ix_evaluations_employe_id" ON "m10"."evaluations" ("employe_id");
CREATE INDEX IF NOT EXISTS "ix_evaluations_reference" ON "m10"."evaluations" ("reference");
CREATE TABLE IF NOT EXISTS "m10"."evenements" (
  "id" text PRIMARY KEY,
  "date" date,
  "nature" text,
  "portee" text,
  "statut" text,
  "cree_le" timestamptz,
  "libelle" text,
  "cree_par" text,
  "reference" text,
  "beneficiaire" text,
  "mode_par_defaut" text,
  "beneficiaire_id" text,
  "montant_par_agent" integer,
  "periode_paiement" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."evenements" IS 'Collection « evenements » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_evenements_date" ON "m10"."evenements" ("date");
CREATE INDEX IF NOT EXISTS "ix_evenements_nature" ON "m10"."evenements" ("nature");
CREATE INDEX IF NOT EXISTS "ix_evenements_statut" ON "m10"."evenements" ("statut");
CREATE INDEX IF NOT EXISTS "ix_evenements_reference" ON "m10"."evenements" ("reference");
CREATE INDEX IF NOT EXISTS "ix_evenements_beneficiaire_id" ON "m10"."evenements" ("beneficiaire_id");
CREATE TABLE IF NOT EXISTS "m10"."fiches_poste" (
  "id" text PRIMARY KEY,
  "resume" text,
  "source" text,
  "statut" text,
  "cree_le" timestamptz,
  "redigee" boolean,
  "cree_par" text,
  "intitule" text,
  "rattachement" text,
  "textes" text,
  "niveau_n" text,
  "anomalie" text,
  "diplomes" text,
  "archivage" text,
  "niveau_inf" text,
  "niveau_sup" text,
  "savoir_etre" text,
  "elaboration" date,
  "savoir_faire" text,
  "environnement" text,
  "relations_externes" text,
  "relations_internes" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."fiches_poste" IS 'Collection « fichesPoste » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_fiches_poste_statut" ON "m10"."fiches_poste" ("statut");
CREATE TABLE IF NOT EXISTS "m10"."fiches_poste_missions" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "mission" text,
  "activites" jsonb,
  "indicateurs" jsonb,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m10"."fiches_poste" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m10"."fiches_poste_missions" IS 'Lignes « missions » de « fichesPoste »';
CREATE TABLE IF NOT EXISTS "m10"."grille_primes" (
  "id" text PRIMARY KEY,
  "mode" text,
  "label" text,
  "source" text,
  "statut" text,
  "prime_id" text,
  "version" integer,
  "montants" jsonb,
  "date_effet" date,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."grille_primes" IS 'Collection « grillePrimes » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_grille_primes_statut" ON "m10"."grille_primes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_grille_primes_prime_id" ON "m10"."grille_primes" ("prime_id");
CREATE TABLE IF NOT EXISTS "m10"."historique_bareme" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."historique_bareme" IS 'Collection « historiqueBareme » — M10 Ressources humaines';
CREATE TABLE IF NOT EXISTS "m10"."historique_primes" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."historique_primes" IS 'Collection « historiquePrimes » — M10 Ressources humaines';
CREATE TABLE IF NOT EXISTS "m10"."missions" (
  "id" text PRIMARY KEY,
  "agent" text,
  "moyen" text,
  "objet" text,
  "nature" text,
  "statut" text,
  "agent_id" text,
  "libelle" text,
  "fonction" text,
  "reference" text,
  "validee_le" date,
  "date_depart" date,
  "date_retour" date,
  "validee_par" text,
  "destination" text,
  "observation" text,
  "statut_mission" text,
  "structure_prise" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."missions" IS 'Collection « missions » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_missions_nature" ON "m10"."missions" ("nature");
CREATE INDEX IF NOT EXISTS "ix_missions_statut" ON "m10"."missions" ("statut");
CREATE INDEX IF NOT EXISTS "ix_missions_agent_id" ON "m10"."missions" ("agent_id");
CREATE INDEX IF NOT EXISTS "ix_missions_reference" ON "m10"."missions" ("reference");
CREATE TABLE IF NOT EXISTS "m10"."modeles_badge" (
  "id" text PRIMARY KEY,
  "zones" jsonb,
  "defaut" boolean,
  "format" text,
  "source" text,
  "statut" text,
  "libelle" text,
  "a_valider" boolean,
  "orientation" text,
  "mentions_verso" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."modeles_badge" IS 'Collection « modelesBadge » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_modeles_badge_statut" ON "m10"."modeles_badge" ("statut");
CREATE TABLE IF NOT EXISTS "m10"."participations" (
  "id" text PRIMARY KEY,
  "mode" text,
  "recu" text,
  "agent" text,
  "statut" text,
  "cree_le" timestamptz,
  "montant" integer,
  "cree_par" text,
  "employe_id" text,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "encaisse_par" text,
  "date_paiement" date,
  "periode_retenue" text,
  "statut_paiement" text,
  "evenement_libelle" text,
  "nature" text,
  "service" text,
  "fonction" text,
  "matricule" text,
  "reference" text,
  "evenement_id" text,
  "date_evenement" date,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."participations" IS 'Collection « participations » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_participations_statut" ON "m10"."participations" ("statut");
CREATE INDEX IF NOT EXISTS "ix_participations_employe_id" ON "m10"."participations" ("employe_id");
CREATE INDEX IF NOT EXISTS "ix_participations_nature" ON "m10"."participations" ("nature");
CREATE INDEX IF NOT EXISTS "ix_participations_reference" ON "m10"."participations" ("reference");
CREATE INDEX IF NOT EXISTS "ix_participations_evenement_id" ON "m10"."participations" ("evenement_id");
CREATE TABLE IF NOT EXISTS "m10"."personnel" (
  "id" text PRIMARY KEY,
  "nom" text,
  "cnss" text,
  "sexe" text,
  "poste" text,
  "prenom" text,
  "statut" text,
  "service" text,
  "fonction" text,
  "categorie" text,
  "matricule" text,
  "situation" text,
  "telephone" text,
  "nom_complet" text,
  "salaire_base" integer,
  "date_embauche" date,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."personnel" IS 'Collection « personnel » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_personnel_statut" ON "m10"."personnel" ("statut");
CREATE TABLE IF NOT EXISTS "m10"."planning" (
  "id" text PRIMARY KEY,
  "date" date,
  "type" text,
  "regime" text,
  "statut" text,
  "employe" text,
  "service" text,
  "fonction" text,
  "employe_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."planning" IS 'Collection « planning » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_planning_date" ON "m10"."planning" ("date");
CREATE INDEX IF NOT EXISTS "ix_planning_type" ON "m10"."planning" ("type");
CREATE INDEX IF NOT EXISTS "ix_planning_statut" ON "m10"."planning" ("statut");
CREATE INDEX IF NOT EXISTS "ix_planning_employe_id" ON "m10"."planning" ("employe_id");
CREATE TABLE IF NOT EXISTS "m10"."presences" (
  "id" text PRIMARY KEY,
  "date" date,
  "etat" text,
  "motif" text,
  "statut" text,
  "employe" text,
  "service" text,
  "employe_id" text,
  "matricule" text,
  "heure_depart" text,
  "heure_arrivee" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."presences" IS 'Collection « presences » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_presences_date" ON "m10"."presences" ("date");
CREATE INDEX IF NOT EXISTS "ix_presences_etat" ON "m10"."presences" ("etat");
CREATE INDEX IF NOT EXISTS "ix_presences_statut" ON "m10"."presences" ("statut");
CREATE INDEX IF NOT EXISTS "ix_presences_employe_id" ON "m10"."presences" ("employe_id");
CREATE TABLE IF NOT EXISTS "m10"."prestataires" (
  "id" text PRIMARY KEY,
  "ifu" text,
  "nom" text,
  "statut" text,
  "reference" text,
  "tarif_acte" integer,
  "telephone" text,
  "specialite" text,
  "actes_realises" integer,
  "facture_normalisee" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."prestataires" IS 'Collection « prestataires » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_prestataires_statut" ON "m10"."prestataires" ("statut");
CREATE INDEX IF NOT EXISTS "ix_prestataires_reference" ON "m10"."prestataires" ("reference");
CREATE TABLE IF NOT EXISTS "m10"."regimes_travail" (
  "id" text PRIMARY KEY,
  "cycle" integer,
  "repos" text,
  "source" text,
  "statut" text,
  "libelle" text,
  "mention" text,
  "fonctions" jsonb,
  "vacations" jsonb,
  "jours_travailles_mois" integer,
  "honoraire" integer,
  "honoraire_mode" text,
  "honoraire_periodicite" text,
  "extra" jsonb
);
COMMENT ON TABLE "m10"."regimes_travail" IS 'Collection « regimesTravail » — M10 Ressources humaines';
CREATE INDEX IF NOT EXISTS "ix_regimes_travail_statut" ON "m10"."regimes_travail" ("statut");
CREATE TABLE IF NOT EXISTS "m11"."avances" (
  "id" text PRIMARY KEY,
  "statut" text,
  "cree_le" timestamptz,
  "employe" text,
  "montant" integer,
  "cree_par" text,
  "employe_id" text,
  "reference" text,
  "rembourse" integer,
  "modifie_le" timestamptz,
  "mensualite" integer,
  "modifie_par" text,
  "statut_avance" text,
  "nb_mensualites" integer,
  "date" date,
  "motif" text,
  "service" text,
  "matricule" text,
  "extra" jsonb
);
COMMENT ON TABLE "m11"."avances" IS 'Collection « avances » — M11 Paie & primes';
CREATE INDEX IF NOT EXISTS "ix_avances_statut" ON "m11"."avances" ("statut");
CREATE INDEX IF NOT EXISTS "ix_avances_employe_id" ON "m11"."avances" ("employe_id");
CREATE INDEX IF NOT EXISTS "ix_avances_reference" ON "m11"."avances" ("reference");
CREATE INDEX IF NOT EXISTS "ix_avances_date" ON "m11"."avances" ("date");
CREATE TABLE IF NOT EXISTS "m11"."bulletins" (
  "id" text PRIMARY KEY,
  "mois" integer,
  "ortb" integer,
  "annee" integer,
  "sonde" text,
  "statut" text,
  "cree_le" timestamptz,
  "periode" text,
  "cree_par" text,
  "ortb_tele" integer,
  "employe_id" text,
  "ortb_radio" integer,
  "archive_le" timestamptz,
  "archive_par" text,
  "motif_archivage" text,
  "extra" jsonb
);
COMMENT ON TABLE "m11"."bulletins" IS 'Collection « bulletins » — M11 Paie & primes';
CREATE INDEX IF NOT EXISTS "ix_bulletins_annee" ON "m11"."bulletins" ("annee");
CREATE INDEX IF NOT EXISTS "ix_bulletins_statut" ON "m11"."bulletins" ("statut");
CREATE INDEX IF NOT EXISTS "ix_bulletins_periode" ON "m11"."bulletins" ("periode");
CREATE INDEX IF NOT EXISTS "ix_bulletins_employe_id" ON "m11"."bulletins" ("employe_id");
CREATE TABLE IF NOT EXISTS "m11"."heures_sup" (
  "id" text PRIMARY KEY,
  "motif" text,
  "heures" integer,
  "statut" text,
  "valide" boolean,
  "employe" text,
  "montant" integer,
  "periode" text,
  "service" text,
  "employe_id" text,
  "matricule" text,
  "reference" text,
  "majoration" integer,
  "taux_horaire" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m11"."heures_sup" IS 'Collection « heuresSup » — M11 Paie & primes';
CREATE INDEX IF NOT EXISTS "ix_heures_sup_statut" ON "m11"."heures_sup" ("statut");
CREATE INDEX IF NOT EXISTS "ix_heures_sup_periode" ON "m11"."heures_sup" ("periode");
CREATE INDEX IF NOT EXISTS "ix_heures_sup_employe_id" ON "m11"."heures_sup" ("employe_id");
CREATE INDEX IF NOT EXISTS "ix_heures_sup_reference" ON "m11"."heures_sup" ("reference");
CREATE TABLE IF NOT EXISTS "m11"."prets_etudes" (
  "id" text PRIMARY KEY,
  "objet" text,
  "nature" text,
  "statut" text,
  "cree_le" timestamptz,
  "employe" text,
  "montant" integer,
  "cree_par" text,
  "retenues" jsonb,
  "employe_id" text,
  "reference" text,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "nb_echeances" integer,
  "premiere_echeance" text,
  "agent" text,
  "matricule" text,
  "date_accord" date,
  "autorise_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m11"."prets_etudes" IS 'Collection « pretsEtudes » — M11 Paie & primes';
CREATE INDEX IF NOT EXISTS "ix_prets_etudes_nature" ON "m11"."prets_etudes" ("nature");
CREATE INDEX IF NOT EXISTS "ix_prets_etudes_statut" ON "m11"."prets_etudes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_prets_etudes_employe_id" ON "m11"."prets_etudes" ("employe_id");
CREATE INDEX IF NOT EXISTS "ix_prets_etudes_reference" ON "m11"."prets_etudes" ("reference");
CREATE TABLE IF NOT EXISTS "m12"."archives_exercice" (
  "id" text PRIMARY KEY,
  "par" text,
  "annee" integer,
  "cree_le" timestamptz,
  "statut" text,
  "cree_le_2" timestamptz,
  "version" integer,
  "cree_par" text,
  "an_numero" text,
  "cl_numero" text,
  "reference" text,
  "manifeste_empreinte" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."archives_exercice" IS 'Collection « archivesExercice » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_archives_exercice_annee" ON "m12"."archives_exercice" ("annee");
CREATE INDEX IF NOT EXISTS "ix_archives_exercice_statut" ON "m12"."archives_exercice" ("statut");
CREATE INDEX IF NOT EXISTS "ix_archives_exercice_reference" ON "m12"."archives_exercice" ("reference");
CREATE TABLE IF NOT EXISTS "m12"."archives_exercice_fichiers" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "nom" text,
  "type" text,
  "taille" integer,
  "contenu" text,
  "empreinte" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m12"."archives_exercice" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m12"."archives_exercice_fichiers" IS 'Lignes « fichiers » de « archivesExercice »';
CREATE TABLE IF NOT EXISTS "m12"."banques" (
  "id" text PRIMARY KEY,
  "banque" text,
  "devise" text,
  "nature" text,
  "source" text,
  "statut" text,
  "intitule" text,
  "numero_compte" text,
  "statut_compte" text,
  "compte_comptable" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."banques" IS 'Collection « banques » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_banques_nature" ON "m12"."banques" ("nature");
CREATE INDEX IF NOT EXISTS "ix_banques_statut" ON "m12"."banques" ("statut");
CREATE TABLE IF NOT EXISTS "m12"."budgets" (
  "id" text PRIMARY KEY,
  "prevu" integer,
  "centre" text,
  "nature" text,
  "statut" text,
  "exercice" integer,
  "reference" text,
  "centre_cout" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."budgets" IS 'Collection « budgets » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_budgets_nature" ON "m12"."budgets" ("nature");
CREATE INDEX IF NOT EXISTS "ix_budgets_statut" ON "m12"."budgets" ("statut");
CREATE INDEX IF NOT EXISTS "ix_budgets_reference" ON "m12"."budgets" ("reference");
CREATE TABLE IF NOT EXISTS "m12"."centres_couts" (
  "id" text PRIMARY KEY,
  "code" text,
  "type" text,
  "source" text,
  "statut" text,
  "libelle" text,
  "responsable" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."centres_couts" IS 'Collection « centresCouts » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_centres_couts_code" ON "m12"."centres_couts" ("code");
CREATE INDEX IF NOT EXISTS "ix_centres_couts_type" ON "m12"."centres_couts" ("type");
CREATE INDEX IF NOT EXISTS "ix_centres_couts_statut" ON "m12"."centres_couts" ("statut");
CREATE TABLE IF NOT EXISTS "m12"."clotures" (
  "id" text PRIMARY KEY,
  "le" timestamptz,
  "par" text,
  "type" text,
  "annee" integer,
  "motif" text,
  "statut" text,
  "cree_le" timestamptz,
  "cree_par" text,
  "an_numero" text,
  "cl_numero" text,
  "resultat" integer,
  "empreinte" text,
  "contre_passe" jsonb,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."clotures" IS 'Collection « clotures » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_clotures_type" ON "m12"."clotures" ("type");
CREATE INDEX IF NOT EXISTS "ix_clotures_annee" ON "m12"."clotures" ("annee");
CREATE INDEX IF NOT EXISTS "ix_clotures_statut" ON "m12"."clotures" ("statut");
CREATE TABLE IF NOT EXISTS "m12"."comptes_resultat" (
  "id" text PRIMARY KEY,
  "sens" text,
  "compte" text,
  "statut" text,
  "libelle" text,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."comptes_resultat" IS 'Collection « comptesResultat » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_comptes_resultat_statut" ON "m12"."comptes_resultat" ("statut");
CREATE TABLE IF NOT EXISTS "m12"."depenses" (
  "id" text PRIMARY KEY,
  "date" date,
  "statut" text,
  "libelle" text,
  "montant" integer,
  "saisi_le" date,
  "saisi_par" text,
  "categorie" text,
  "reference" text,
  "ecriture_id" text,
  "compte_charge" text,
  "justificatif" jsonb,
  "compte_tresorerie" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."depenses" IS 'Collection « depenses » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_depenses_date" ON "m12"."depenses" ("date");
CREATE INDEX IF NOT EXISTS "ix_depenses_statut" ON "m12"."depenses" ("statut");
CREATE INDEX IF NOT EXISTS "ix_depenses_reference" ON "m12"."depenses" ("reference");
CREATE INDEX IF NOT EXISTS "ix_depenses_ecriture_id" ON "m12"."depenses" ("ecriture_id");
CREATE TABLE IF NOT EXISTS "m12"."depenses_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "libelle" text,
  "montant" integer,
  "compte_charge" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m12"."depenses" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m12"."depenses_lignes" IS 'Lignes « lignes » de « depenses »';
CREATE TABLE IF NOT EXISTS "m12"."echeances_fiscales" (
  "id" text PRIMARY KEY,
  "code" text,
  "note" text,
  "part" integer,
  "paye" boolean,
  "statut" text,
  "cree_le" timestamptz,
  "famille" text,
  "libelle" text,
  "montant" text,
  "periode" text,
  "cree_par" text,
  "echeance" date,
  "exercice" integer,
  "reportee" boolean,
  "reference" text,
  "archive_le" timestamptz,
  "modifie_le" timestamptz,
  "validee_par" text,
  "archive_par" text,
  "modifie_par" text,
  "declaration" text,
  "periodicite" text,
  "regeneree_le" timestamptz,
  "date_paiement" date,
  "regeneree_par" text,
  "motif_archivage" text,
  "echeance_theorique" date,
  "version_obligation" date,
  "paye_le" date,
  "paye_par" text,
  "quittance" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."echeances_fiscales" IS 'Collection « echeancesFiscales » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_echeances_fiscales_code" ON "m12"."echeances_fiscales" ("code");
CREATE INDEX IF NOT EXISTS "ix_echeances_fiscales_statut" ON "m12"."echeances_fiscales" ("statut");
CREATE INDEX IF NOT EXISTS "ix_echeances_fiscales_periode" ON "m12"."echeances_fiscales" ("periode");
CREATE INDEX IF NOT EXISTS "ix_echeances_fiscales_reference" ON "m12"."echeances_fiscales" ("reference");
CREATE TABLE IF NOT EXISTS "m12"."ecritures" (
  "id" text PRIMARY KEY,
  "date" date,
  "debit" integer,
  "compte" text,
  "credit" integer,
  "numero" text,
  "statut" text,
  "cree_le" timestamptz,
  "journal" text,
  "libelle" text,
  "origine" text,
  "piece_id" text,
  "cree_par" text,
  "piece_numero" text,
  "compte_libelle" text,
  "journal_libelle" text,
  "centre_cout" text,
  "piece_origine" text,
  "origine_cloture" text,
  "contre_passe_de" text,
  "archive_le" timestamptz,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "motif_archivage" text,
  "lettrage" text,
  "valide_le" date,
  "valide_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."ecritures" IS 'Collection « ecritures » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_ecritures_date" ON "m12"."ecritures" ("date");
CREATE INDEX IF NOT EXISTS "ix_ecritures_numero" ON "m12"."ecritures" ("numero");
CREATE INDEX IF NOT EXISTS "ix_ecritures_statut" ON "m12"."ecritures" ("statut");
CREATE INDEX IF NOT EXISTS "ix_ecritures_piece_id" ON "m12"."ecritures" ("piece_id");
CREATE TABLE IF NOT EXISTS "m12"."exercices" (
  "id" text PRIMARY KEY,
  "fin" date,
  "etat" text,
  "annee" integer,
  "debut" date,
  "motif" text,
  "source" text,
  "statut" text,
  "valide_le" timestamptz,
  "valide_par" text,
  "an_numero" text,
  "cl_numero" text,
  "resultat" integer,
  "demande_le" timestamptz,
  "empreinte" text,
  "rouvert_le" timestamptz,
  "modifie_le" timestamptz,
  "demande_par" text,
  "rouvert_par" text,
  "modifie_par" text,
  "resultat_prevu" integer,
  "motif_reouverture" text,
  "nb_ecritures_archivees" integer,
  "repris_le" timestamptz,
  "repris_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."exercices" IS 'Collection « exercices » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_exercices_etat" ON "m12"."exercices" ("etat");
CREATE INDEX IF NOT EXISTS "ix_exercices_annee" ON "m12"."exercices" ("annee");
CREATE INDEX IF NOT EXISTS "ix_exercices_statut" ON "m12"."exercices" ("statut");
CREATE TABLE IF NOT EXISTS "m12"."immobilisations" (
  "id" text PRIMARY KEY,
  "etat" text,
  "compte" text,
  "statut" text,
  "categorie" text,
  "reference" text,
  "designation" text,
  "fournisseur" text,
  "date_acquisition" date,
  "valeur_acquisition" integer,
  "duree_amortissement" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."immobilisations" IS 'Collection « immobilisations » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_immobilisations_etat" ON "m12"."immobilisations" ("etat");
CREATE INDEX IF NOT EXISTS "ix_immobilisations_statut" ON "m12"."immobilisations" ("statut");
CREATE INDEX IF NOT EXISTS "ix_immobilisations_reference" ON "m12"."immobilisations" ("reference");
CREATE TABLE IF NOT EXISTS "m12"."objectifs_pilotage" (
  "id" text PRIMARY KEY,
  "axe" text,
  "aide" text,
  "sens" text,
  "cible" integer,
  "label" text,
  "unite" text,
  "alerte" integer,
  "source" text,
  "statut" text,
  "a_valider" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."objectifs_pilotage" IS 'Collection « objectifsPilotage » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_objectifs_pilotage_statut" ON "m12"."objectifs_pilotage" ("statut");
CREATE TABLE IF NOT EXISTS "m12"."rapprochements" (
  "id" text PRIMARY KEY,
  "ecart" integer,
  "banque" text,
  "compte" text,
  "statut" text,
  "periode" text,
  "operateur" text,
  "reference" text,
  "solde_releve" integer,
  "statut_rappro" text,
  "solde_comptable" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m12"."rapprochements" IS 'Collection « rapprochements » — M12 Comptabilité SYSCOHADA';
CREATE INDEX IF NOT EXISTS "ix_rapprochements_statut" ON "m12"."rapprochements" ("statut");
CREATE INDEX IF NOT EXISTS "ix_rapprochements_periode" ON "m12"."rapprochements" ("periode");
CREATE INDEX IF NOT EXISTS "ix_rapprochements_reference" ON "m12"."rapprochements" ("reference");
CREATE TABLE IF NOT EXISTS "m13"."ambulance" (
  "id" text PRIMARY KEY,
  "etat" text,
  "motif" text,
  "tarif" integer,
  "statut" text,
  "cree_le" timestamptz,
  "facture" boolean,
  "patient" text,
  "cree_par" text,
  "chauffeur" text,
  "date_heure" timestamptz,
  "patient_id" text,
  "reference" text,
  "destination" text,
  "kilometrage" integer,
  "patient_code" text,
  "accompagnant" text,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."ambulance" IS 'Collection « ambulance » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_ambulance_etat" ON "m13"."ambulance" ("etat");
CREATE INDEX IF NOT EXISTS "ix_ambulance_statut" ON "m13"."ambulance" ("statut");
CREATE INDEX IF NOT EXISTS "ix_ambulance_date_heure" ON "m13"."ambulance" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_ambulance_patient_id" ON "m13"."ambulance" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_ambulance_reference" ON "m13"."ambulance" ("reference");
CREATE TABLE IF NOT EXISTS "m13"."ambulances" (
  "id" text PRIMARY KEY,
  "base" text,
  "type" text,
  "source" text,
  "statut" text,
  "cree_le" timestamptz,
  "contact" text,
  "libelle" text,
  "cree_par" text,
  "telephone" text,
  "verifie_le" date,
  "a_completer" boolean,
  "disponibilite" text,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."ambulances" IS 'Collection « ambulances » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_ambulances_type" ON "m13"."ambulances" ("type");
CREATE INDEX IF NOT EXISTS "ix_ambulances_statut" ON "m13"."ambulances" ("statut");
CREATE TABLE IF NOT EXISTS "m13"."courriers" (
  "id" text PRIMARY KEY,
  "date" date,
  "sens" text,
  "objet" text,
  "nature" text,
  "statut" text,
  "cree_le" timestamptz,
  "cree_par" text,
  "affecte_a" text,
  "numerise" boolean,
  "reference" text,
  "traitement" text,
  "correspondant" text,
  "accuse_reception" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."courriers" IS 'Collection « courriers » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_courriers_date" ON "m13"."courriers" ("date");
CREATE INDEX IF NOT EXISTS "ix_courriers_nature" ON "m13"."courriers" ("nature");
CREATE INDEX IF NOT EXISTS "ix_courriers_statut" ON "m13"."courriers" ("statut");
CREATE INDEX IF NOT EXISTS "ix_courriers_reference" ON "m13"."courriers" ("reference");
CREATE TABLE IF NOT EXISTS "m13"."enquetes" (
  "id" text PRIMARY KEY,
  "titre" text,
  "cree_le" date,
  "source" text,
  "statut" text,
  "a_valider" boolean,
  "valide_le" date,
  "reference" text,
  "valide_par" text,
  "description" text,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."enquetes" IS 'Collection « enquetes » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_enquetes_statut" ON "m13"."enquetes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_enquetes_reference" ON "m13"."enquetes" ("reference");
CREATE TABLE IF NOT EXISTS "m13"."enquetes_questions" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "code" text,
  "type" text,
  "libelle" text,
  "options" jsonb,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m13"."enquetes" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m13"."enquetes_questions" IS 'Lignes « questions » de « enquetes »';
CREATE TABLE IF NOT EXISTS "m13"."evenements_etablissement" (
  "id" text PRIMARY KEY,
  "date" date,
  "lieu" text,
  "heure" text,
  "canaux" jsonb,
  "statut" text,
  "libelle" text,
  "notifier" boolean,
  "categorie" text,
  "reference" text,
  "responsable" text,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."evenements_etablissement" IS 'Collection « evenementsEtablissement » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_evenements_etablissement_date" ON "m13"."evenements_etablissement" ("date");
CREATE INDEX IF NOT EXISTS "ix_evenements_etablissement_statut" ON "m13"."evenements_etablissement" ("statut");
CREATE INDEX IF NOT EXISTS "ix_evenements_etablissement_reference" ON "m13"."evenements_etablissement" ("reference");
CREATE TABLE IF NOT EXISTS "m13"."jetons_enquete" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."jetons_enquete" IS 'Collection « jetonsEnquete » — M13 Administration & ambulance';
CREATE TABLE IF NOT EXISTS "m13"."materiel" (
  "id" text PRIMARY KEY,
  "etat" text,
  "marque" text,
  "statut" text,
  "libelle" text,
  "categorie" text,
  "reference" text,
  "a_completer" boolean,
  "numero_serie" text,
  "observation" text,
  "localisation" text,
  "mise_en_service" text,
  "periodicite_mois" integer,
  "dernier_entretien" date,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."materiel" IS 'Collection « materiel » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_materiel_etat" ON "m13"."materiel" ("etat");
CREATE INDEX IF NOT EXISTS "ix_materiel_statut" ON "m13"."materiel" ("statut");
CREATE INDEX IF NOT EXISTS "ix_materiel_reference" ON "m13"."materiel" ("reference");
CREATE TABLE IF NOT EXISTS "m13"."plan_annuel" (
  "id" text PRIMARY KEY,
  "axe" text,
  "action" text,
  "statut" text,
  "reference" text,
  "avancement" text,
  "responsable" text,
  "trimestre_fin" integer,
  "trimestre_debut" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."plan_annuel" IS 'Collection « planAnnuel » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_plan_annuel_statut" ON "m13"."plan_annuel" ("statut");
CREATE INDEX IF NOT EXISTS "ix_plan_annuel_reference" ON "m13"."plan_annuel" ("reference");
CREATE TABLE IF NOT EXISTS "m13"."reponses_enquetes" (
  "id" text PRIMARY KEY,
  "date" date,
  "canal" text,
  "statut" text,
  "reponses" jsonb,
  "saisi_par" text,
  "enquete_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."reponses_enquetes" IS 'Collection « reponsesEnquetes » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_reponses_enquetes_date" ON "m13"."reponses_enquetes" ("date");
CREATE INDEX IF NOT EXISTS "ix_reponses_enquetes_statut" ON "m13"."reponses_enquetes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_reponses_enquetes_enquete_id" ON "m13"."reponses_enquetes" ("enquete_id");
CREATE TABLE IF NOT EXISTS "m13"."reunions" (
  "id" text PRIMARY KEY,
  "date" date,
  "lieu" text,
  "type" text,
  "heure" text,
  "statut" text,
  "president" text,
  "reference" text,
  "compte_rendu" boolean,
  "ordre_du_jour" text,
  "participants" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m13"."reunions" IS 'Collection « reunions » — M13 Administration & ambulance';
CREATE INDEX IF NOT EXISTS "ix_reunions_date" ON "m13"."reunions" ("date");
CREATE INDEX IF NOT EXISTS "ix_reunions_type" ON "m13"."reunions" ("type");
CREATE INDEX IF NOT EXISTS "ix_reunions_statut" ON "m13"."reunions" ("statut");
CREATE INDEX IF NOT EXISTS "ix_reunions_reference" ON "m13"."reunions" ("reference");
CREATE TABLE IF NOT EXISTS "m14"."audit" (
  "_rang" integer PRIMARY KEY,
  "id" text,
  "role" text,
  "apres" text,
  "avant" text,
  "action" text,
  "entite" text,
  "statut" text,
  "reference" text,
  "horodatage" timestamptz,
  "utilisateur" text,
  "poste" text,
  "module" text,
  "succes" boolean,
  "date_heure" timestamptz,
  "ancienne_valeur" text,
  "nouvelle_valeur" text,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."audit" IS 'Collection « audit » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_audit_statut" ON "m14"."audit" ("statut");
CREATE INDEX IF NOT EXISTS "ix_audit_reference" ON "m14"."audit" ("reference");
CREATE INDEX IF NOT EXISTS "ix_audit_date_heure" ON "m14"."audit" ("date_heure");
CREATE TABLE IF NOT EXISTS "m14"."comptes" (
  "id" text PRIMARY KEY,
  "num" text,
  "classe" integer,
  "source" text,
  "statut" text,
  "journal" text,
  "libelle" text,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."comptes" IS 'Collection « comptes » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_comptes_statut" ON "m14"."comptes" ("statut");
CREATE TABLE IF NOT EXISTS "m14"."fichiers_sauvegarde" (
  "id" text PRIMARY KEY,
  "date" date,
  "heure" text,
  "portee" text,
  "statut" text,
  "tables" integer,
  "taille" integer,
  "fichier" text,
  "generee_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."fichiers_sauvegarde" IS 'Collection « fichiersSauvegarde » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_fichiers_sauvegarde_date" ON "m14"."fichiers_sauvegarde" ("date");
CREATE INDEX IF NOT EXISTS "ix_fichiers_sauvegarde_statut" ON "m14"."fichiers_sauvegarde" ("statut");
CREATE TABLE IF NOT EXISTS "m14"."notifications" (
  "id" text PRIMARY KEY,
  "lue" boolean,
  "type" text,
  "poste" text,
  "cree_le" timestamptz,
  "detail" text,
  "statut" text,
  "cree_le_2" timestamptz,
  "libelle" text,
  "cree_par" text,
  "priorite" text,
  "demande_id" text,
  "facture_id" text,
  "patient_id" text,
  "reference" text,
  "destinataire" text,
  "ordonnance_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."notifications" IS 'Collection « notifications » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_notifications_type" ON "m14"."notifications" ("type");
CREATE INDEX IF NOT EXISTS "ix_notifications_statut" ON "m14"."notifications" ("statut");
CREATE INDEX IF NOT EXISTS "ix_notifications_demande_id" ON "m14"."notifications" ("demande_id");
CREATE INDEX IF NOT EXISTS "ix_notifications_facture_id" ON "m14"."notifications" ("facture_id");
CREATE INDEX IF NOT EXISTS "ix_notifications_patient_id" ON "m14"."notifications" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_notifications_reference" ON "m14"."notifications" ("reference");
CREATE INDEX IF NOT EXISTS "ix_notifications_ordonnance_id" ON "m14"."notifications" ("ordonnance_id");
CREATE TABLE IF NOT EXISTS "m14"."politique_securite" (
  "id" text PRIMARY KEY,
  "statut" text,
  "cree_le" date,
  "cree_par" text,
  "echecs_max" integer,
  "modifie_le" timestamptz,
  "blocage_min" integer,
  "historique" integer,
  "modifiee_le" timestamptz,
  "modifie_par" text,
  "longueur_min" integer,
  "inactivite_min" integer,
  "expiration_jours" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."politique_securite" IS 'Collection « politiqueSecurite » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_politique_securite_statut" ON "m14"."politique_securite" ("statut");
CREATE TABLE IF NOT EXISTS "m14"."rbac" (
  "id" text PRIMARY KEY,
  "role" text,
  "motif" text,
  "droits" jsonb,
  "statut" text,
  "libelle" text,
  "defini_le" date,
  "defini_par" text,
  "droits_ecrans" jsonb,
  "libelle_court" text,
  "libelle_origine" text,
  "transfere_a" text,
  "accueil" text,
  "couleur" text,
  "nouveau" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."rbac" IS 'Collection « rbac » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_rbac_statut" ON "m14"."rbac" ("statut");
CREATE TABLE IF NOT EXISTS "m14"."sessions_utilisateur" (
  "id" text PRIMARY KEY,
  "etat" text,
  "role" text,
  "debut" timestamptz,
  "poste" text,
  "source" text,
  "statut" text,
  "cree_le" timestamptz,
  "cree_par" text,
  "adresse_ip" text,
  "inactivite" integer,
  "nom_complet" text,
  "identifiant" text,
  "derniere_activite" timestamptz,
  "cloture_le" timestamptz,
  "modifie_le" timestamptz,
  "cloture_par" text,
  "modifie_par" text,
  "cloture_motif" text,
  "cloture_propre" boolean,
  "cloture_par_identifiant" text,
  "utilisateur_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."sessions_utilisateur" IS 'Collection « sessionsUtilisateur » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_sessions_utilisateur_etat" ON "m14"."sessions_utilisateur" ("etat");
CREATE INDEX IF NOT EXISTS "ix_sessions_utilisateur_statut" ON "m14"."sessions_utilisateur" ("statut");
CREATE INDEX IF NOT EXISTS "ix_sessions_utilisateur_utilisateur_id" ON "m14"."sessions_utilisateur" ("utilisateur_id");
CREATE TABLE IF NOT EXISTS "m14"."soignants" (
  "id" text PRIMARY KEY,
  "poste" text,
  "source" text,
  "statut" text,
  "execute" boolean,
  "qualite" text,
  "prescrit" boolean,
  "secteurs" jsonb,
  "supervise" boolean,
  "nom_complet" text,
  "personnel_id" text,
  "realise_imagerie" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."soignants" IS 'Collection « soignants » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_soignants_statut" ON "m14"."soignants" ("statut");
CREATE INDEX IF NOT EXISTS "ix_soignants_personnel_id" ON "m14"."soignants" ("personnel_id");
CREATE TABLE IF NOT EXISTS "m14"."tentatives_connexion" (
  "id" text PRIMARY KEY,
  "nom" text,
  "role" text,
  "motif" text,
  "poste" text,
  "statut" text,
  "traitee" boolean,
  "horodatage" timestamptz,
  "identifiant" text,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."tentatives_connexion" IS 'Collection « tentativesConnexion » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_tentatives_connexion_statut" ON "m14"."tentatives_connexion" ("statut");
CREATE TABLE IF NOT EXISTS "m14"."utilisateurs" (
  "id" text PRIMARY KEY,
  "mfa" boolean,
  "role" text,
  "actif" boolean,
  "poste" text,
  "cree_le" date,
  "echecs" integer,
  "statut" text,
  "service" text,
  "nom_complet" text,
  "identifiant" text,
  "dernier_acces" date,
  "employe_id" text,
  "matricule" text,
  "note" text,
  "bloque" boolean,
  "bloque_le" timestamptz,
  "bloque_par" text,
  "modifie_le" timestamptz,
  "debloque_le" timestamptz,
  "modifie_par" text,
  "bloque_motif" text,
  "debloque_par" text,
  "doit_changer_mot_de_passe" boolean,
  "reinitialisation_imposee_le" timestamptz,
  "reinitialisation_imposee_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m14"."utilisateurs" IS 'Collection « utilisateurs » — M14 Sécurité & audit';
CREATE INDEX IF NOT EXISTS "ix_utilisateurs_statut" ON "m14"."utilisateurs" ("statut");
CREATE INDEX IF NOT EXISTS "ix_utilisateurs_employe_id" ON "m14"."utilisateurs" ("employe_id");
CREATE TABLE IF NOT EXISTS "m1"."constantes" (
  "fr" integer,
  "id" text PRIMARY KEY,
  "imc" numeric,
  "spo2" integer,
  "poids" numeric,
  "pouls" integer,
  "moment" text,
  "statut" text,
  "taille" integer,
  "cree_le" timestamptz,
  "origine" text,
  "patient" text,
  "tension" text,
  "cree_par" text,
  "date_heure" timestamp,
  "patient_id" text,
  "reference" text,
  "relevee_par" text,
  "tension_dia" integer,
  "tension_sys" integer,
  "patient_code" text,
  "temperature" numeric,
  "dossier_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m1"."constantes" IS 'Collection « constantes » — M1 Patients & DMI';
CREATE INDEX IF NOT EXISTS "ix_constantes_statut" ON "m1"."constantes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_constantes_date_heure" ON "m1"."constantes" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_constantes_patient_id" ON "m1"."constantes" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_constantes_reference" ON "m1"."constantes" ("reference");
CREATE INDEX IF NOT EXISTS "ix_constantes_dossier_id" ON "m1"."constantes" ("dossier_id");
CREATE TABLE IF NOT EXISTS "m1"."contre_references" (
  "id" text PRIMARY KEY,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "service" text,
  "cree_par" text,
  "evolution" text,
  "justifiee" boolean,
  "patient_id" text,
  "reference" text,
  "chef_service" text,
  "concordance" boolean,
  "date_arrivee" date,
  "hospitalise" boolean,
  "patient_code" text,
  "heure_arrivee" text,
  "observations" text,
  "agent_referent" text,
  "centre_accueil" text,
  "numero_dossier" text,
  "numero_reference" text,
  "diagnostic_entree" text,
  "diagnostic_sortie" text,
  "motif_non_justifiee" text,
  "structure_provenance" text,
  "extra" jsonb
);
COMMENT ON TABLE "m1"."contre_references" IS 'Collection « contreReferences » — M1 Patients & DMI';
CREATE INDEX IF NOT EXISTS "ix_contre_references_statut" ON "m1"."contre_references" ("statut");
CREATE INDEX IF NOT EXISTS "ix_contre_references_patient_id" ON "m1"."contre_references" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_contre_references_reference" ON "m1"."contre_references" ("reference");
CREATE TABLE IF NOT EXISTS "m1"."documents_patient" (
  "id" text PRIMARY KEY,
  "code" text,
  "date" date,
  "etat" text,
  "type" text,
  "depose" text,
  "format" text,
  "statut" text,
  "taille" integer,
  "donnees" text,
  "fichier" text,
  "patient" text,
  "patient_id" text,
  "reference" text,
  "extra" jsonb
);
COMMENT ON TABLE "m1"."documents_patient" IS 'Collection « documentsPatient » — M1 Patients & DMI';
CREATE INDEX IF NOT EXISTS "ix_documents_patient_code" ON "m1"."documents_patient" ("code");
CREATE INDEX IF NOT EXISTS "ix_documents_patient_date" ON "m1"."documents_patient" ("date");
CREATE INDEX IF NOT EXISTS "ix_documents_patient_etat" ON "m1"."documents_patient" ("etat");
CREATE INDEX IF NOT EXISTS "ix_documents_patient_type" ON "m1"."documents_patient" ("type");
CREATE INDEX IF NOT EXISTS "ix_documents_patient_statut" ON "m1"."documents_patient" ("statut");
CREATE INDEX IF NOT EXISTS "ix_documents_patient_patient_id" ON "m1"."documents_patient" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_documents_patient_reference" ON "m1"."documents_patient" ("reference");
CREATE TABLE IF NOT EXISTS "m1"."fiches_reference" (
  "id" text PRIMARY KEY,
  "age" integer,
  "sens" text,
  "sexe" text,
  "moyen" text,
  "pouls" integer,
  "motifs" jsonb,
  "numero" text,
  "statut" text,
  "urgent" boolean,
  "cree_le" timestamptz,
  "adresse" text,
  "patient" text,
  "tension" text,
  "cree_par" text,
  "depart_le" text,
  "arrivee_le" text,
  "patient_id" text,
  "symptomes" text,
  "contact_nom" text,
  "ambulancier" text,
  "patient_code" text,
  "temperature" numeric,
  "traitements" text,
  "abord_veineux" boolean,
  "centre_alerte" boolean,
  "observations" text,
  "agent_referent" text,
  "date_admission" date,
  "date_reference" date,
  "contact_adresse" text,
  "heure_admission" text,
  "heure_reference" text,
  "centre_destination" text,
  "formation_sanitaire" text,
  "extra" jsonb
);
COMMENT ON TABLE "m1"."fiches_reference" IS 'Collection « fichesReference » — M1 Patients & DMI';
CREATE INDEX IF NOT EXISTS "ix_fiches_reference_numero" ON "m1"."fiches_reference" ("numero");
CREATE INDEX IF NOT EXISTS "ix_fiches_reference_statut" ON "m1"."fiches_reference" ("statut");
CREATE INDEX IF NOT EXISTS "ix_fiches_reference_patient_id" ON "m1"."fiches_reference" ("patient_id");
CREATE TABLE IF NOT EXISTS "m1"."patients" (
  "id" text PRIMARY KEY,
  "age" integer,
  "nom" text,
  "code" text,
  "sexe" text,
  "assure" boolean,
  "prenom" text,
  "statut" text,
  "cree_le" timestamptz,
  "adresse" text,
  "externe" boolean,
  "cree_par" text,
  "assureur" text,
  "quartier" text,
  "telephone" text,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "date_creation" date,
  "date_naissance" date,
  "age_reference_le" text,
  "origine_dossier" text,
  "taux_prise_en_charge" integer,
  "prescripteur_exterieur" text,
  "allergies" text,
  "antecedents" text,
  "assureur_nom" text,
  "numero_police" text,
  "groupe_sanguin" text,
  "souscripteur_id" text,
  "carte_expiration" date,
  "antecedents_autres" text,
  "personne_a_prevenir" text,
  "traitement_en_cours" text,
  "categorie_assurance" text,
  "souscripteur" text,
  "matricule" text,
  "personnel_id" text,
  "fonction_agent" text,
  "prise_en_charge_personnel" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m1"."patients" IS 'Collection « patients » — M1 Patients & DMI';
CREATE INDEX IF NOT EXISTS "ix_patients_code" ON "m1"."patients" ("code");
CREATE INDEX IF NOT EXISTS "ix_patients_statut" ON "m1"."patients" ("statut");
CREATE INDEX IF NOT EXISTS "ix_patients_souscripteur_id" ON "m1"."patients" ("souscripteur_id");
CREATE INDEX IF NOT EXISTS "ix_patients_personnel_id" ON "m1"."patients" ("personnel_id");
CREATE TABLE IF NOT EXISTS "m1"."pieces" (
  "id" text PRIMARY KEY,
  "annee" integer,
  "sigle" text,
  "numero" integer,
  "remis_a" text,
  "statut" text,
  "type_id" text,
  "cree_le" timestamptz,
  "contenu" text,
  "libelle" text,
  "medecin" text,
  "montant" integer,
  "patient" text,
  "cree_par" text,
  "direction" text,
  "patient_id" text,
  "reference" text,
  "couverture" text,
  "patient_code" text,
  "date_delivrance" date,
  "extra" jsonb
);
COMMENT ON TABLE "m1"."pieces" IS 'Collection « pieces » — M1 Patients & DMI';
CREATE INDEX IF NOT EXISTS "ix_pieces_annee" ON "m1"."pieces" ("annee");
CREATE INDEX IF NOT EXISTS "ix_pieces_numero" ON "m1"."pieces" ("numero");
CREATE INDEX IF NOT EXISTS "ix_pieces_statut" ON "m1"."pieces" ("statut");
CREATE INDEX IF NOT EXISTS "ix_pieces_type_id" ON "m1"."pieces" ("type_id");
CREATE INDEX IF NOT EXISTS "ix_pieces_patient_id" ON "m1"."pieces" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_pieces_reference" ON "m1"."pieces" ("reference");
CREATE TABLE IF NOT EXISTS "m2"."cliches_imagerie" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."cliches_imagerie" IS 'Collection « clichesImagerie » — M2 RDV, visites, consultations, imagerie';
CREATE TABLE IF NOT EXISTS "m2"."consultations" (
  "id" text PRIMARY KEY,
  "date" timestamptz,
  "type" text,
  "motif" text,
  "tarif" integer,
  "statut" text,
  "cree_le" timestamptz,
  "medecin" text,
  "patient" text,
  "cree_par" text,
  "medecin_id" text,
  "patient_id" text,
  "reference" text,
  "diagnostic" text,
  "patient_code" text,
  "frais_deplacement" integer,
  "adresse_intervention" text,
  "fc" integer,
  "poids" integer,
  "tension" text,
  "conduite" text,
  "orientation" text,
  "pathologies" jsonb,
  "temperature" numeric,
  "dossier_reference" text,
  "orientation_label" text,
  "resume_syndromique" text,
  "pathologies_libelles" jsonb,
  "pathologie_principale" text,
  "dossier_consultation_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."consultations" IS 'Collection « consultations » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_consultations_date" ON "m2"."consultations" ("date");
CREATE INDEX IF NOT EXISTS "ix_consultations_type" ON "m2"."consultations" ("type");
CREATE INDEX IF NOT EXISTS "ix_consultations_statut" ON "m2"."consultations" ("statut");
CREATE INDEX IF NOT EXISTS "ix_consultations_medecin_id" ON "m2"."consultations" ("medecin_id");
CREATE INDEX IF NOT EXISTS "ix_consultations_patient_id" ON "m2"."consultations" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_consultations_reference" ON "m2"."consultations" ("reference");
CREATE INDEX IF NOT EXISTS "ix_consultations_dossier_consultation_id" ON "m2"."consultations" ("dossier_consultation_id");
CREATE TABLE IF NOT EXISTS "m2"."demandes_imagerie" (
  "id" text PRIMARY KEY,
  "prix" integer,
  "examen" text,
  "statut" text,
  "urgent" boolean,
  "cree_le" timestamptz,
  "origine" text,
  "patient" text,
  "cree_par" text,
  "modalite" text,
  "date_heure" timestamptz,
  "facture_id" text,
  "patient_id" text,
  "reference" text,
  "modifie_le" timestamptz,
  "examen_code" text,
  "indication" text,
  "motif_tarif" text,
  "modifie_par" text,
  "patient_code" text,
  "ordonnance_id" text,
  "prescripteur" text,
  "facture_numero" text,
  "ordonnance_numero" text,
  "secteur_demandeur" text,
  "bloque_par_paiement" boolean,
  "dossier_consultation_id" text,
  "regle_le" timestamptz,
  "valide_le" timestamptz,
  "execute_le" timestamptz,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."demandes_imagerie" IS 'Collection « demandesImagerie » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_demandes_imagerie_statut" ON "m2"."demandes_imagerie" ("statut");
CREATE INDEX IF NOT EXISTS "ix_demandes_imagerie_date_heure" ON "m2"."demandes_imagerie" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_demandes_imagerie_facture_id" ON "m2"."demandes_imagerie" ("facture_id");
CREATE INDEX IF NOT EXISTS "ix_demandes_imagerie_patient_id" ON "m2"."demandes_imagerie" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_demandes_imagerie_reference" ON "m2"."demandes_imagerie" ("reference");
CREATE INDEX IF NOT EXISTS "ix_demandes_imagerie_ordonnance_id" ON "m2"."demandes_imagerie" ("ordonnance_id");
CREATE INDEX IF NOT EXISTS "ix_demandes_imagerie_dossier_consultation_id" ON "m2"."demandes_imagerie" ("dossier_consultation_id");
CREATE TABLE IF NOT EXISTS "m2"."dossiers_consultation" (
  "id" text PRIMARY KEY,
  "age" integer,
  "imc" numeric,
  "etat" text,
  "sexe" text,
  "spo2" integer,
  "poids" integer,
  "pouls" integer,
  "statut" text,
  "taille" integer,
  "cree_le" timestamptz,
  "patient" text,
  "recu_par" text,
  "tension" text,
  "cree_par" text,
  "assureur" text,
  "histoire" text,
  "ouvert_le" timestamptz,
  "soignant" text,
  "allergies" text,
  "patient_id" text,
  "reference" text,
  "type_venue" text,
  "modifie_le" timestamptz,
  "motif_venue" text,
  "modifie_par" text,
  "date_arrivee" date,
  "etat_general" text,
  "patient_code" text,
  "temperature" numeric,
  "ant_medicaux" text,
  "heure_arrivee" text,
  "groupe_sanguin" text,
  "dossier_saisi_le" timestamptz,
  "statut_vaccinal" text,
  "ant_chirurgicaux" text,
  "electrophorese_hb" text,
  "examens_physiques" jsonb,
  "constantes_accueil" jsonb,
  "traitement_en_cours" text,
  "etat_general_precision" text,
  "ant_gyneco_obstetricaux" text,
  "allergies_medicamenteuses" text,
  "clotur_le" timestamptz,
  "fiches_ids" jsonb,
  "orientation" text,
  "derniere_fiche_id" text,
  "diagnostic_retenu" text,
  "pathologies_retenues" jsonb,
  "antecedents_obstetricaux" jsonb,
  "examen_obstetrical" jsonb,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."dossiers_consultation" IS 'Collection « dossiersConsultation » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_dossiers_consultation_etat" ON "m2"."dossiers_consultation" ("etat");
CREATE INDEX IF NOT EXISTS "ix_dossiers_consultation_statut" ON "m2"."dossiers_consultation" ("statut");
CREATE INDEX IF NOT EXISTS "ix_dossiers_consultation_patient_id" ON "m2"."dossiers_consultation" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_dossiers_consultation_reference" ON "m2"."dossiers_consultation" ("reference");
CREATE INDEX IF NOT EXISTS "ix_dossiers_consultation_derniere_fiche_id" ON "m2"."dossiers_consultation" ("derniere_fiche_id");
CREATE TABLE IF NOT EXISTS "m2"."file_attente" (
  "id" text PRIMARY KEY,
  "etat" text,
  "motif" text,
  "poste" text,
  "numero" text,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "servi_le" timestamptz,
  "cree_par" text,
  "priorite" text,
  "appele_par" text,
  "arrivee_le" timestamptz,
  "patient_id" text,
  "praticien" text,
  "poste_label" text,
  "patient_code" text,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."file_attente" IS 'Collection « fileAttente » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_file_attente_etat" ON "m2"."file_attente" ("etat");
CREATE INDEX IF NOT EXISTS "ix_file_attente_numero" ON "m2"."file_attente" ("numero");
CREATE INDEX IF NOT EXISTS "ix_file_attente_statut" ON "m2"."file_attente" ("statut");
CREATE INDEX IF NOT EXISTS "ix_file_attente_patient_id" ON "m2"."file_attente" ("patient_id");
CREATE TABLE IF NOT EXISTS "m2"."ordonnances" (
  "id" text PRIMARY KEY,
  "date" timestamptz,
  "actes" jsonb,
  "numero" text,
  "statut" text,
  "urgent" boolean,
  "cree_le" timestamptz,
  "medecin" text,
  "montant" integer,
  "patient" text,
  "cree_par" text,
  "imagerie" jsonb,
  "facture_id" text,
  "patient_id" text,
  "modifie_le" timestamptz,
  "diagnostic" text,
  "modifie_par" text,
  "patient_code" text,
  "statut_actes" text,
  "montant_actes" integer,
  "facture_numero" text,
  "consultation_id" text,
  "statut_analyses" text,
  "statut_imagerie" text,
  "statut_paiement" text,
  "montant_analyses" integer,
  "montant_imagerie" integer,
  "montant_medicaments" integer,
  "statut_dispensation" text,
  "dossier_consultation_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."ordonnances" IS 'Collection « ordonnances » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_ordonnances_date" ON "m2"."ordonnances" ("date");
CREATE INDEX IF NOT EXISTS "ix_ordonnances_numero" ON "m2"."ordonnances" ("numero");
CREATE INDEX IF NOT EXISTS "ix_ordonnances_statut" ON "m2"."ordonnances" ("statut");
CREATE INDEX IF NOT EXISTS "ix_ordonnances_facture_id" ON "m2"."ordonnances" ("facture_id");
CREATE INDEX IF NOT EXISTS "ix_ordonnances_patient_id" ON "m2"."ordonnances" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_ordonnances_consultation_id" ON "m2"."ordonnances" ("consultation_id");
CREATE INDEX IF NOT EXISTS "ix_ordonnances_dossier_consultation_id" ON "m2"."ordonnances" ("dossier_consultation_id");
CREATE TABLE IF NOT EXISTS "m2"."ordonnances_analyses" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "code" text,
  "prix" integer,
  "delai" text,
  "categorie" text,
  "designation" text,
  "echantillon" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m2"."ordonnances" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m2"."ordonnances_analyses" IS 'Lignes « analyses » de « ordonnances »';
CREATE TABLE IF NOT EXISTS "m2"."ordonnances_medicaments" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "prix" integer,
  "duree" text,
  "total" integer,
  "unite" text,
  "produit" text,
  "quantite" integer,
  "posologie" text,
  "produit_id" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m2"."ordonnances" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m2"."ordonnances_medicaments" IS 'Lignes « medicaments » de « ordonnances »';
CREATE TABLE IF NOT EXISTS "m2"."pathologies" (
  "id" text PRIMARY KEY,
  "code" text,
  "source" text,
  "statut" text,
  "libelle" text,
  "a_valider" boolean,
  "chapitre" text,
  "valide_le" date,
  "valide_par" text,
  "notifiable" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."pathologies" IS 'Collection « pathologies » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_pathologies_code" ON "m2"."pathologies" ("code");
CREATE INDEX IF NOT EXISTS "ix_pathologies_statut" ON "m2"."pathologies" ("statut");
CREATE TABLE IF NOT EXISTS "m2"."prescriptions" (
  "id" text PRIMARY KEY,
  "date" timestamptz,
  "type" text,
  "statut" text,
  "cree_le" timestamptz,
  "montant" integer,
  "origine" text,
  "patient" text,
  "cree_par" text,
  "modalite" text,
  "patient_id" text,
  "reference" text,
  "patient_code" text,
  "ordonnance_id" text,
  "prescripteur" text,
  "prescripteur_id" text,
  "statut_paiement" text,
  "secteur_destinataire" text,
  "premier_administrateur" text,
  "assure" boolean,
  "modifie_le" timestamptz,
  "indication" text,
  "modifie_par" text,
  "admission_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."prescriptions" IS 'Collection « prescriptions » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_prescriptions_date" ON "m2"."prescriptions" ("date");
CREATE INDEX IF NOT EXISTS "ix_prescriptions_type" ON "m2"."prescriptions" ("type");
CREATE INDEX IF NOT EXISTS "ix_prescriptions_statut" ON "m2"."prescriptions" ("statut");
CREATE INDEX IF NOT EXISTS "ix_prescriptions_patient_id" ON "m2"."prescriptions" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_prescriptions_reference" ON "m2"."prescriptions" ("reference");
CREATE INDEX IF NOT EXISTS "ix_prescriptions_ordonnance_id" ON "m2"."prescriptions" ("ordonnance_id");
CREATE INDEX IF NOT EXISTS "ix_prescriptions_prescripteur_id" ON "m2"."prescriptions" ("prescripteur_id");
CREATE INDEX IF NOT EXISTS "ix_prescriptions_admission_id" ON "m2"."prescriptions" ("admission_id");
CREATE TABLE IF NOT EXISTS "m2"."prescriptions_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "prix" integer,
  "duree" text,
  "libelle" text,
  "quantite" integer,
  "posologie" text,
  "produit_id" text,
  "nb_administrations" integer,
  "tarif" text,
  "famille" text,
  "acte_code" text,
  "frequence" text,
  "motif_tarif" text,
  "prix_a_valider" boolean,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m2"."prescriptions" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m2"."prescriptions_lignes" IS 'Lignes « lignes » de « prescriptions »';
CREATE TABLE IF NOT EXISTS "m2"."resultats_imagerie" (
  "id" text PRIMARY KEY,
  "age" integer,
  "ddr" text,
  "date" timestamptz,
  "examen" text,
  "statut" text,
  "cree_le" timestamptz,
  "annexes" text,
  "patient" text,
  "rendu_le" timestamptz,
  "valeurs" jsonb,
  "cree_par" text,
  "condition" text,
  "patient_id" text,
  "reference" text,
  "conclusion" text,
  "examen_code" text,
  "indication" text,
  "patient_code" text,
  "realisateur" text,
  "prescripteur" text,
  "realisateur_id" text,
  "demande_reference" text,
  "demande_imagerie_id" text,
  "resultats" text,
  "prescripteur_id" text,
  "recommandation" text,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."resultats_imagerie" IS 'Collection « resultatsImagerie » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_resultats_imagerie_date" ON "m2"."resultats_imagerie" ("date");
CREATE INDEX IF NOT EXISTS "ix_resultats_imagerie_statut" ON "m2"."resultats_imagerie" ("statut");
CREATE INDEX IF NOT EXISTS "ix_resultats_imagerie_patient_id" ON "m2"."resultats_imagerie" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_resultats_imagerie_reference" ON "m2"."resultats_imagerie" ("reference");
CREATE INDEX IF NOT EXISTS "ix_resultats_imagerie_realisateur_id" ON "m2"."resultats_imagerie" ("realisateur_id");
CREATE INDEX IF NOT EXISTS "ix_resultats_imagerie_demande_imagerie_id" ON "m2"."resultats_imagerie" ("demande_imagerie_id");
CREATE INDEX IF NOT EXISTS "ix_resultats_imagerie_prescripteur_id" ON "m2"."resultats_imagerie" ("prescripteur_id");
CREATE TABLE IF NOT EXISTS "m2"."soins" (
  "id" text PRIMARY KEY,
  "lit" text,
  "acte" text,
  "date" date,
  "etat" text,
  "heure" text,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "produit" text,
  "cree_par" text,
  "quantite" integer,
  "soignant" text,
  "patient_id" text,
  "admission_id" text,
  "patient_code" text,
  "observations" text,
  "extra" jsonb
);
COMMENT ON TABLE "m2"."soins" IS 'Collection « soins » — M2 RDV, visites, consultations, imagerie';
CREATE INDEX IF NOT EXISTS "ix_soins_date" ON "m2"."soins" ("date");
CREATE INDEX IF NOT EXISTS "ix_soins_etat" ON "m2"."soins" ("etat");
CREATE INDEX IF NOT EXISTS "ix_soins_statut" ON "m2"."soins" ("statut");
CREATE INDEX IF NOT EXISTS "ix_soins_patient_id" ON "m2"."soins" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_soins_admission_id" ON "m2"."soins" ("admission_id");
CREATE TABLE IF NOT EXISTS "m3"."administrations" (
  "id" text PRIMARY KEY,
  "rang" integer,
  "total" integer,
  "statut" text,
  "cree_le" timestamptz,
  "libelle" text,
  "patient" text,
  "secteur" text,
  "cree_par" text,
  "modalite" text,
  "date_heure" date,
  "executant" text,
  "patient_id" text,
  "reference" text,
  "ligne_index" integer,
  "executant_id" text,
  "observation" text,
  "patient_code" text,
  "motif_secteur" text,
  "prescription_id" text,
  "prescription_ref" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."administrations" IS 'Collection « administrations » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_administrations_statut" ON "m3"."administrations" ("statut");
CREATE INDEX IF NOT EXISTS "ix_administrations_date_heure" ON "m3"."administrations" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_administrations_patient_id" ON "m3"."administrations" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_administrations_reference" ON "m3"."administrations" ("reference");
CREATE INDEX IF NOT EXISTS "ix_administrations_executant_id" ON "m3"."administrations" ("executant_id");
CREATE INDEX IF NOT EXISTS "ix_administrations_prescription_id" ON "m3"."administrations" ("prescription_id");
CREATE TABLE IF NOT EXISTS "m3"."admissions" (
  "id" text PRIMARY KEY,
  "lit" text,
  "statut" text,
  "cree_le" timestamptz,
  "chambre" text,
  "patient" text,
  "cree_par" text,
  "infirmier" text,
  "patient_id" text,
  "reference" text,
  "symptomes" text,
  "date_entree" date,
  "date_sortie" date,
  "infirmier_id" text,
  "patient_code" text,
  "type_chambre" text,
  "prise_en_charge" text,
  "diagnostic_entree" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."admissions" IS 'Collection « admissions » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_admissions_statut" ON "m3"."admissions" ("statut");
CREATE INDEX IF NOT EXISTS "ix_admissions_patient_id" ON "m3"."admissions" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_admissions_reference" ON "m3"."admissions" ("reference");
CREATE INDEX IF NOT EXISTS "ix_admissions_infirmier_id" ON "m3"."admissions" ("infirmier_id");
CREATE TABLE IF NOT EXISTS "m3"."checklists_bloc" (
  "id" text PRIMARY KEY,
  "total" integer,
  "coches" integer,
  "moment" text,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "cree_par" text,
  "date_heure" timestamptz,
  "patient_id" text,
  "reference" text,
  "responsable" text,
  "responsable_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."checklists_bloc" IS 'Collection « checklistsBloc » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_checklists_bloc_statut" ON "m3"."checklists_bloc" ("statut");
CREATE INDEX IF NOT EXISTS "ix_checklists_bloc_date_heure" ON "m3"."checklists_bloc" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_checklists_bloc_patient_id" ON "m3"."checklists_bloc" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_checklists_bloc_reference" ON "m3"."checklists_bloc" ("reference");
CREATE INDEX IF NOT EXISTS "ix_checklists_bloc_responsable_id" ON "m3"."checklists_bloc" ("responsable_id");
CREATE TABLE IF NOT EXISTS "m3"."checklists_bloc_items" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "coche" boolean,
  "label" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m3"."checklists_bloc" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m3"."checklists_bloc_items" IS 'Lignes « items » de « checklistsBloc »';
CREATE TABLE IF NOT EXISTS "m3"."cpa" (
  "id" text PRIMARY KEY,
  "asa" text,
  "date" date,
  "statut" text,
  "patient" text,
  "allergies" text,
  "patient_id" text,
  "reference" text,
  "technique" text,
  "conclusion" text,
  "mallampati" text,
  "patient_code" text,
  "anesthesiste" text,
  "observations" text,
  "jeune_consigne" boolean,
  "antecedents_anesthesiques" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."cpa" IS 'Collection « cpa » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_cpa_date" ON "m3"."cpa" ("date");
CREATE INDEX IF NOT EXISTS "ix_cpa_statut" ON "m3"."cpa" ("statut");
CREATE INDEX IF NOT EXISTS "ix_cpa_patient_id" ON "m3"."cpa" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_cpa_reference" ON "m3"."cpa" ("reference");
CREATE TABLE IF NOT EXISTS "m3"."cr_operatoires" (
  "id" text PRIMARY KEY,
  "cro" text,
  "nip" text,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "cree_par" text,
  "operateur" text,
  "patient_id" text,
  "reference" text,
  "anesthesie" text,
  "operateur_id" text,
  "patient_code" text,
  "anesthesiste" text,
  "intervention" text,
  "aide_operateur" text,
  "date_operation" date,
  "anesthesiste_id" text,
  "aide_operateur_id" text,
  "diagnostic_peroperatoire" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."cr_operatoires" IS 'Collection « crOperatoires » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_cr_operatoires_statut" ON "m3"."cr_operatoires" ("statut");
CREATE INDEX IF NOT EXISTS "ix_cr_operatoires_patient_id" ON "m3"."cr_operatoires" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_cr_operatoires_reference" ON "m3"."cr_operatoires" ("reference");
CREATE INDEX IF NOT EXISTS "ix_cr_operatoires_operateur_id" ON "m3"."cr_operatoires" ("operateur_id");
CREATE INDEX IF NOT EXISTS "ix_cr_operatoires_anesthesiste_id" ON "m3"."cr_operatoires" ("anesthesiste_id");
CREATE INDEX IF NOT EXISTS "ix_cr_operatoires_aide_operateur_id" ON "m3"."cr_operatoires" ("aide_operateur_id");
CREATE TABLE IF NOT EXISTS "m3"."observations" (
  "id" text PRIMARY KEY,
  "motif" text,
  "place" text,
  "unite" text,
  "statut" text,
  "medecin" text,
  "patient" text,
  "infirmier" text,
  "patient_id" text,
  "reference" text,
  "conclusion" text,
  "date_entree" timestamptz,
  "date_sortie" timestamptz,
  "unite_label" text,
  "orientation" text,
  "patient_code" text,
  "orientation_label" text,
  "statut_observation" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."observations" IS 'Collection « observations » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_observations_statut" ON "m3"."observations" ("statut");
CREATE INDEX IF NOT EXISTS "ix_observations_patient_id" ON "m3"."observations" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_observations_reference" ON "m3"."observations" ("reference");
CREATE TABLE IF NOT EXISTS "m3"."observations_constantes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "par" text,
  "spo2" integer,
  "heure" timestamptz,
  "pouls" integer,
  "tension" text,
  "observation" text,
  "temperature" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m3"."observations" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m3"."observations_constantes" IS 'Lignes « constantes » de « observations »';
CREATE TABLE IF NOT EXISTS "m3"."rapports_medicaux" (
  "id" text PRIMARY KEY,
  "age" integer,
  "sexe" text,
  "motif" text,
  "statut" text,
  "cree_le" timestamptz,
  "adresse" text,
  "medecin" text,
  "patient" text,
  "cree_par" text,
  "anamnese" text,
  "evolution" text,
  "medecin_id" text,
  "patient_id" text,
  "reference" text,
  "telephone" text,
  "date_entree" date,
  "date_sortie" date,
  "hypotheses" text,
  "patient_code" text,
  "examen_physique" text,
  "diagnostic_retenu" text,
  "diagnostic_sortie" text,
  "traitement_entree" text,
  "traitement_sortie" text,
  "traitement_reajuste" text,
  "examens_paracliniques" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."rapports_medicaux" IS 'Collection « rapportsMedicaux » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_rapports_medicaux_statut" ON "m3"."rapports_medicaux" ("statut");
CREATE INDEX IF NOT EXISTS "ix_rapports_medicaux_medecin_id" ON "m3"."rapports_medicaux" ("medecin_id");
CREATE INDEX IF NOT EXISTS "ix_rapports_medicaux_patient_id" ON "m3"."rapports_medicaux" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_rapports_medicaux_reference" ON "m3"."rapports_medicaux" ("reference");
CREATE TABLE IF NOT EXISTS "m3"."releves" (
  "fc" integer,
  "fr" integer,
  "id" text PRIMARY KEY,
  "date" date,
  "spo2" integer,
  "heure" text,
  "poids" integer,
  "statut" text,
  "taille" integer,
  "diurese" integer,
  "tension" text,
  "saisi_par" text,
  "traitement" text,
  "admission_id" text,
  "temperature" numeric,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."releves" IS 'Collection « releves » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_releves_date" ON "m3"."releves" ("date");
CREATE INDEX IF NOT EXISTS "ix_releves_statut" ON "m3"."releves" ("statut");
CREATE INDEX IF NOT EXISTS "ix_releves_admission_id" ON "m3"."releves" ("admission_id");
CREATE TABLE IF NOT EXISTS "m3"."scores_glasgow" (
  "id" text PRIMARY KEY,
  "nip" text,
  "score" integer,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "cree_par" text,
  "date_heure" timestamp,
  "evalue_par" text,
  "patient_id" text,
  "reference" text,
  "evaluateur" text,
  "observation" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."scores_glasgow" IS 'Collection « scoresGlasgow » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_scores_glasgow_statut" ON "m3"."scores_glasgow" ("statut");
CREATE INDEX IF NOT EXISTS "ix_scores_glasgow_date_heure" ON "m3"."scores_glasgow" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_scores_glasgow_patient_id" ON "m3"."scores_glasgow" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_scores_glasgow_reference" ON "m3"."scores_glasgow" ("reference");
CREATE TABLE IF NOT EXISTS "m3"."scores_glasgow_axes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "axe" text,
  "points" integer,
  "libelle" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m3"."scores_glasgow" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m3"."scores_glasgow_axes" IS 'Lignes « axes » de « scoresGlasgow »';
CREATE TABLE IF NOT EXISTS "m3"."surveillances_transfusion" (
  "id" text PRIMARY KEY,
  "date" date,
  "debut" text,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "releves" integer,
  "service" text,
  "valeurs" jsonb,
  "cree_par" text,
  "attendus" integer,
  "incident" boolean,
  "poche_psl" text,
  "patient_id" text,
  "reference" text,
  "conclusion" text,
  "patient_code" text,
  "responsable" text,
  "responsable_id" text,
  "nature_incident" text,
  "extra" jsonb
);
COMMENT ON TABLE "m3"."surveillances_transfusion" IS 'Collection « surveillancesTransfusion » — M3 Hospitalisation & bloc';
CREATE INDEX IF NOT EXISTS "ix_surveillances_transfusion_date" ON "m3"."surveillances_transfusion" ("date");
CREATE INDEX IF NOT EXISTS "ix_surveillances_transfusion_statut" ON "m3"."surveillances_transfusion" ("statut");
CREATE INDEX IF NOT EXISTS "ix_surveillances_transfusion_patient_id" ON "m3"."surveillances_transfusion" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_surveillances_transfusion_reference" ON "m3"."surveillances_transfusion" ("reference");
CREATE INDEX IF NOT EXISTS "ix_surveillances_transfusion_responsable_id" ON "m3"."surveillances_transfusion" ("responsable_id");
CREATE TABLE IF NOT EXISTS "m4"."accouchements" (
  "id" text PRIMARY KEY,
  "type" text,
  "voie" text,
  "actes" jsonb,
  "duree" text,
  "issue" text,
  "statut" text,
  "patient" text,
  "nn_decede" boolean,
  "placenta" jsonb,
  "date_heure" timestamptz,
  "patient_id" text,
  "reference" text,
  "sage_femme" text,
  "hemorragie" boolean,
  "degre_mort_ne" text,
  "nn_reference" boolean,
  "patient_code" text,
  "femme_decedee" boolean,
  "femme_referee" boolean,
  "quantite_sang" integer,
  "surveillance" jsonb,
  "complications" text,
  "mode_delivrance" text,
  "gestes_delivrance" jsonb,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."accouchements" IS 'Collection « accouchements » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_accouchements_type" ON "m4"."accouchements" ("type");
CREATE INDEX IF NOT EXISTS "ix_accouchements_statut" ON "m4"."accouchements" ("statut");
CREATE INDEX IF NOT EXISTS "ix_accouchements_date_heure" ON "m4"."accouchements" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_accouchements_patient_id" ON "m4"."accouchements" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_accouchements_reference" ON "m4"."accouchements" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."cpon" (
  "id" text PRIMARY KEY,
  "hpp" boolean,
  "date" date,
  "type" text,
  "examen" text,
  "statut" text,
  "patient" text,
  "conseil_pf" boolean,
  "patient_id" text,
  "reference" text,
  "sage_femme" text,
  "patient_code" text,
  "etat_nouveau_ne" text,
  "etiologie_ante" text,
  "accouchement_ref" text,
  "supplementation" text,
  "hemorragie_ante_partum" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."cpon" IS 'Collection « cpon » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_cpon_date" ON "m4"."cpon" ("date");
CREATE INDEX IF NOT EXISTS "ix_cpon_type" ON "m4"."cpon" ("type");
CREATE INDEX IF NOT EXISTS "ix_cpon_statut" ON "m4"."cpon" ("statut");
CREATE INDEX IF NOT EXISTS "ix_cpon_patient_id" ON "m4"."cpon" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_cpon_reference" ON "m4"."cpon" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."cr_maternite" (
  "id" text PRIMARY KEY,
  "cree_le" timestamptz,
  "statut" text,
  "suites" text,
  "type_cr" text,
  "cree_le_2" timestamptz,
  "patient" text,
  "terme_sa" integer,
  "cree_par" text,
  "date_heure" timestamp,
  "patient_id" text,
  "reference" text,
  "sage_femme" text,
  "type_label" text,
  "anesthesie" text,
  "indication" text,
  "deroulement" text,
  "operateur_id" text,
  "patient_code" text,
  "sage_femme_id" text,
  "complications" text,
  "produit_aspire" text,
  "geste" text,
  "methode" text,
  "date_acte" date,
  "counseling" boolean,
  "prochain_rdv" date,
  "observations" text,
  "effets_secondaires" boolean,
  "voie" text,
  "apgar1" integer,
  "apgar5" integer,
  "etat_mere" text,
  "dechirure" text,
  "delivrance" text,
  "sexe_enfant" text,
  "episiotomie" boolean,
  "poids_enfant" integer,
  "presentation" text,
  "travail_duree" integer,
  "pertes_sanguines" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."cr_maternite" IS 'Collection « crMaternite » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_cr_maternite_statut" ON "m4"."cr_maternite" ("statut");
CREATE INDEX IF NOT EXISTS "ix_cr_maternite_date_heure" ON "m4"."cr_maternite" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_cr_maternite_patient_id" ON "m4"."cr_maternite" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_cr_maternite_reference" ON "m4"."cr_maternite" ("reference");
CREATE INDEX IF NOT EXISTS "ix_cr_maternite_operateur_id" ON "m4"."cr_maternite" ("operateur_id");
CREATE INDEX IF NOT EXISTS "ix_cr_maternite_sage_femme_id" ON "m4"."cr_maternite" ("sage_femme_id");
CREATE TABLE IF NOT EXISTS "m4"."deces" (
  "id" text PRIMARY KEY,
  "lieu" text,
  "cause" text,
  "statut" text,
  "declare" boolean,
  "medecin" text,
  "patient" text,
  "date_heure" timestamptz,
  "patient_id" text,
  "reference" text,
  "patient_code" text,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."deces" IS 'Collection « deces » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_deces_statut" ON "m4"."deces" ("statut");
CREATE INDEX IF NOT EXISTS "ix_deces_date_heure" ON "m4"."deces" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_deces_patient_id" ON "m4"."deces" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_deces_reference" ON "m4"."deces" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."dossiers_obstetricaux" (
  "id" text PRIMARY KEY,
  "age" integer,
  "ddr" date,
  "dpa" date,
  "vat" jsonb,
  "plan" jsonb,
  "droits" jsonb,
  "info_pf" text,
  "parite" integer,
  "statut" text,
  "taille" numeric,
  "examens" jsonb,
  "gestite" integer,
  "patient" text,
  "referee" boolean,
  "facteurs" jsonb,
  "maladies" text,
  "quartier" text,
  "allergies" text,
  "patient_id" text,
  "sage_femme" text,
  "telephone" text,
  "date_entree" date,
  "profession" text,
  "referee_par" text,
  "avortements" integer,
  "nationalite" text,
  "patient_code" text,
  "traitements" text,
  "classes_meres" jsonb,
  "reference_cpn" text,
  "transfusions" integer,
  "numero_dossier" text,
  "procreateur_gs" text,
  "statut_dossier" text,
  "enfants_decedes" integer,
  "enfants_vivants" integer,
  "procreateur_nom" text,
  "personne_contact" text,
  "telephone_contact" text,
  "procreateur_serologie" text,
  "procreateur_profession" text,
  "reference_accouchement" text,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."dossiers_obstetricaux" IS 'Collection « dossiersObstetricaux » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_dossiers_obstetricaux_statut" ON "m4"."dossiers_obstetricaux" ("statut");
CREATE INDEX IF NOT EXISTS "ix_dossiers_obstetricaux_patient_id" ON "m4"."dossiers_obstetricaux" ("patient_id");
CREATE TABLE IF NOT EXISTS "m4"."grossesses" (
  "id" text PRIMARY KEY,
  "sp" jsonb,
  "ddr" date,
  "dpa" date,
  "fer" boolean,
  "gar" boolean,
  "vat" text,
  "milda" boolean,
  "statut" text,
  "folates" boolean,
  "patient" text,
  "terme_sa" integer,
  "patient_id" text,
  "reference" text,
  "sage_femme" text,
  "mebendazole" boolean,
  "patient_code" text,
  "groupe_sanguin" text,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."grossesses" IS 'Collection « grossesses » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_grossesses_statut" ON "m4"."grossesses" ("statut");
CREATE INDEX IF NOT EXISTS "ix_grossesses_patient_id" ON "m4"."grossesses" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_grossesses_reference" ON "m4"."grossesses" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."grossesses_visites" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "n" integer,
  "hu" integer,
  "pb" text,
  "sp" text,
  "ta" text,
  "fer" boolean,
  "imc" numeric,
  "omi" text,
  "bdcf" integer,
  "date" date,
  "milda" boolean,
  "poids" integer,
  "pouls" integer,
  "seins" text,
  "sucre" text,
  "terme" text,
  "vulve" text,
  "bassin" text,
  "rdv_cpn" date,
  "urines" text,
  "arrivee" text,
  "foldine" boolean,
  "albumine" text,
  "conduite" text,
  "plaintes" text,
  "speculum" text,
  "heure_cpnr" text,
  "methode_pf" text,
  "muqueuses" text,
  "rdv_classe" text,
  "conscience" text,
  "diagnostic" text,
  "inspection" text,
  "echographie" text,
  "prestataire" text,
  "temperature" text,
  "counseling_pf" boolean,
  "deparasitage" boolean,
  "presentation" text,
  "signes_danger" boolean,
  "toucher_vaginal" text,
  "points_ureteraux" text,
  "recherche_active" text,
  "conseils_nutrition" boolean,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m4"."grossesses" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m4"."grossesses_visites" IS 'Lignes « visites » de « grossesses »';
CREATE TABLE IF NOT EXISTS "m4"."naissances" (
  "id" text PRIMARY KEY,
  "pc" numeric,
  "pt" numeric,
  "bcg" boolean,
  "mere" text,
  "sexe" text,
  "vpo0" boolean,
  "hep_b0" boolean,
  "poids" text,
  "vit_k1" boolean,
  "apgar1" integer,
  "apgar5" integer,
  "mere_id" text,
  "statut" text,
  "taille" integer,
  "vivant" boolean,
  "apgar10" integer,
  "collyre" boolean,
  "declare" boolean,
  "mere_code" text,
  "date_heure" timestamptz,
  "reference" text,
  "soins_fiche" jsonb,
  "apgar_detail" jsonb,
  "reanimation" boolean,
  "accouchement_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."naissances" IS 'Collection « naissances » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_naissances_mere_id" ON "m4"."naissances" ("mere_id");
CREATE INDEX IF NOT EXISTS "ix_naissances_statut" ON "m4"."naissances" ("statut");
CREATE INDEX IF NOT EXISTS "ix_naissances_date_heure" ON "m4"."naissances" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_naissances_reference" ON "m4"."naissances" ("reference");
CREATE INDEX IF NOT EXISTS "ix_naissances_accouchement_id" ON "m4"."naissances" ("accouchement_id");
CREATE TABLE IF NOT EXISTS "m4"."naissances_elements24h" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "sein" text,
  "heure" text,
  "neuro" text,
  "cordon" text,
  "ictere" text,
  "urines" text,
  "meconium" text,
  "coloration" text,
  "respiration" integer,
  "temperature" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m4"."naissances" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m4"."naissances_elements24h" IS 'Lignes « elements24h » de « naissances »';
CREATE TABLE IF NOT EXISTS "m4"."partogrammes" (
  "id" text PRIMARY KEY,
  "clos" boolean,
  "debut" timestamptz,
  "issue" text,
  "parite" integer,
  "resume" text,
  "statut" text,
  "gestite" integer,
  "patient" text,
  "rupture" timestamptz,
  "patient_id" text,
  "reference" text,
  "accoucheur" text,
  "patient_code" text,
  "dilatation_finale" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."partogrammes" IS 'Collection « partogrammes » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_partogrammes_statut" ON "m4"."partogrammes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_partogrammes_patient_id" ON "m4"."partogrammes" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_partogrammes_reference" ON "m4"."partogrammes" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."partogrammes_mesures" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "ta" text,
  "bdf" integer,
  "heure" integer,
  "pouls" integer,
  "urines" text,
  "liquide" text,
  "descente" integer,
  "ocytocine" text,
  "dilatation" integer,
  "temperature" text,
  "contractions" integer,
  "chevauchement" integer,
  "descente_cotee" text,
  "duree_contractions" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m4"."partogrammes" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m4"."partogrammes_mesures" IS 'Lignes « mesures » de « partogrammes »';
CREATE TABLE IF NOT EXISTS "m4"."planification_familiale" (
  "id" text PRIMARY KEY,
  "ddr" date,
  "rdv" date,
  "date" date,
  "statut" text,
  "methode" text,
  "patient" text,
  "patient_id" text,
  "reference" text,
  "sage_femme" text,
  "acceptante" text,
  "constantes" text,
  "patient_code" text,
  "methode_label" text,
  "methode_anterieure" text,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."planification_familiale" IS 'Collection « planificationFamiliale » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_planification_familiale_date" ON "m4"."planification_familiale" ("date");
CREATE INDEX IF NOT EXISTS "ix_planification_familiale_statut" ON "m4"."planification_familiale" ("statut");
CREATE INDEX IF NOT EXISTS "ix_planification_familiale_patient_id" ON "m4"."planification_familiale" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_planification_familiale_reference" ON "m4"."planification_familiale" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."ptme" (
  "id" text PRIMARY KEY,
  "ctm" boolean,
  "pcr1" text,
  "pcr2" text,
  "ag_hbs" text,
  "hep_bj0" boolean,
  "statut" text,
  "patient" text,
  "vih_type" text,
  "duree_arv" text,
  "syphilis" text,
  "patient_id" text,
  "reference" text,
  "allaitement" text,
  "patient_code" text,
  "charge_virale" text,
  "pcr_naissance" text,
  "protocole_arv" text,
  "serologie18m" text,
  "vih_trimestre" integer,
  "prophylaxie_nn" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."ptme" IS 'Collection « ptme » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_ptme_statut" ON "m4"."ptme" ("statut");
CREATE INDEX IF NOT EXISTS "ix_ptme_patient_id" ON "m4"."ptme" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_ptme_reference" ON "m4"."ptme" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."ptme_dispensations" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "mois" text,
  "servie" boolean,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m4"."ptme" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m4"."ptme_dispensations" IS 'Lignes « dispensations » de « ptme »';
CREATE TABLE IF NOT EXISTS "m4"."registre_sonu" (
  "id" text PRIMARY KEY,
  "agent" text,
  "parite" integer,
  "statut" text,
  "gestite" integer,
  "patient" text,
  "date_heure" timestamptz,
  "evolution" text,
  "fonctions" jsonb,
  "patient_id" text,
  "reference" text,
  "autre_geste" text,
  "evacuation" boolean,
  "provenance" text,
  "patient_code" text,
  "heure_fin_gestes" text,
  "heure_abord_veineux" text,
  "diagnostic_evacuation" text,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."registre_sonu" IS 'Collection « registreSONU » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_registre_sonu_statut" ON "m4"."registre_sonu" ("statut");
CREATE INDEX IF NOT EXISTS "ix_registre_sonu_date_heure" ON "m4"."registre_sonu" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_registre_sonu_patient_id" ON "m4"."registre_sonu" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_registre_sonu_reference" ON "m4"."registre_sonu" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."soins_curatifs_maternite" (
  "id" text PRIMARY KEY,
  "date" date,
  "agent" text,
  "statut" text,
  "patient" text,
  "patient_id" text,
  "reference" text,
  "symptomes" text,
  "diagnostic" text,
  "traitement" text,
  "tranche_age" text,
  "patient_code" text,
  "femme_observee" boolean,
  "milda_delivree" boolean,
  "urgence_maternite" text,
  "femme_hospitalisee" boolean,
  "jours_hospitalisation" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."soins_curatifs_maternite" IS 'Collection « soinsCuratifsMaternite » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_soins_curatifs_maternite_date" ON "m4"."soins_curatifs_maternite" ("date");
CREATE INDEX IF NOT EXISTS "ix_soins_curatifs_maternite_statut" ON "m4"."soins_curatifs_maternite" ("statut");
CREATE INDEX IF NOT EXISTS "ix_soins_curatifs_maternite_patient_id" ON "m4"."soins_curatifs_maternite" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_soins_curatifs_maternite_reference" ON "m4"."soins_curatifs_maternite" ("reference");
CREATE TABLE IF NOT EXISTS "m4"."suivi_maternite" (
  "id" text PRIMARY KEY,
  "cpn" integer,
  "dpa" date,
  "date" date,
  "poids" integer,
  "risque" text,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "terme_sa" integer,
  "cree_par" text,
  "patient_id" text,
  "sage_femme" text,
  "patient_code" text,
  "observations" text,
  "groupe_sanguin" text,
  "extra" jsonb
);
COMMENT ON TABLE "m4"."suivi_maternite" IS 'Collection « suiviMaternite » — M4 Maternité, naissances, décès';
CREATE INDEX IF NOT EXISTS "ix_suivi_maternite_date" ON "m4"."suivi_maternite" ("date");
CREATE INDEX IF NOT EXISTS "ix_suivi_maternite_statut" ON "m4"."suivi_maternite" ("statut");
CREATE INDEX IF NOT EXISTS "ix_suivi_maternite_patient_id" ON "m4"."suivi_maternite" ("patient_id");
CREATE TABLE IF NOT EXISTS "m5"."analyses" (
  "n" integer,
  "id" text PRIMARY KEY,
  "code" text,
  "prix" integer,
  "delai" text,
  "statut" text,
  "categorie" text,
  "designation" text,
  "echantillon" text,
  "tarif_provisoire" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."analyses" IS 'Collection « analyses » — M5 Laboratoire';
CREATE INDEX IF NOT EXISTS "ix_analyses_code" ON "m5"."analyses" ("code");
CREATE INDEX IF NOT EXISTS "ix_analyses_statut" ON "m5"."analyses" ("statut");
CREATE TABLE IF NOT EXISTS "m5"."demandes_analyses" (
  "id" text PRIMARY KEY,
  "prix" integer,
  "delai" text,
  "statut" text,
  "urgent" boolean,
  "cree_le" timestamptz,
  "analyse_" text,
  "origine" text,
  "patient" text,
  "regle_le" timestamptz,
  "cree_par" text,
  "categorie" text,
  "date_heure" timestamptz,
  "patient_id" text,
  "reference" text,
  "modifie_le" timestamptz,
  "laborantin" text,
  "modifie_par" text,
  "analyse_code" text,
  "code_analyse" text,
  "echantillon" text,
  "etat_analyse" text,
  "patient_code" text,
  "ordonnance_id" text,
  "prescripteur" text,
  "statut_paiement" text,
  "ordonnance_numero" text,
  "secteur_demandeur" text,
  "bloque_par_paiement" boolean,
  "dossier_consultation_id" text,
  "recu_par" text,
  "saisi_le" timestamptz,
  "valeurs" jsonb,
  "version" integer,
  "resultat" text,
  "saisi_par" text,
  "valide_le" timestamptz,
  "anormales" integer,
  "preleve_le" timestamptz,
  "conclusion" text,
  "preleve_par" text,
  "recu_labo_le" timestamptz,
  "preleve_par_id" text,
  "qualite_validateur" text,
  "resultat_structure" boolean,
  "valide_technique_le" timestamptz,
  "valide_technique_par" text,
  "valide_biologique_par" text,
  "facture_id" text,
  "indication" text,
  "hospitalise" boolean,
  "facture_numero" text,
  "origine_demande" text,
  "service_demandeur" text,
  "valide_bio_le" date,
  "valide_bio_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."demandes_analyses" IS 'Collection « demandesAnalyses » — M5 Laboratoire';
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_statut" ON "m5"."demandes_analyses" ("statut");
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_date_heure" ON "m5"."demandes_analyses" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_patient_id" ON "m5"."demandes_analyses" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_reference" ON "m5"."demandes_analyses" ("reference");
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_ordonnance_id" ON "m5"."demandes_analyses" ("ordonnance_id");
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_dossier_consultation_id" ON "m5"."demandes_analyses" ("dossier_consultation_id");
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_preleve_par_id" ON "m5"."demandes_analyses" ("preleve_par_id");
CREATE INDEX IF NOT EXISTS "ix_demandes_analyses_facture_id" ON "m5"."demandes_analyses" ("facture_id");
CREATE TABLE IF NOT EXISTS "m5"."donneurs" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."donneurs" IS 'Collection « donneurs » — M5 Laboratoire';
CREATE TABLE IF NOT EXISTS "m5"."examens_labo" (
  "id" text PRIMARY KEY,
  "code" text,
  "note" text,
  "delai" text,
  "source" text,
  "statut" text,
  "section" text,
  "documente" boolean,
  "designation" text,
  "echantillon" text,
  "section_bulletin" text,
  "section_resultat" text,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."examens_labo" IS 'Collection « examensLabo » — M5 Laboratoire';
CREATE INDEX IF NOT EXISTS "ix_examens_labo_code" ON "m5"."examens_labo" ("code");
CREATE INDEX IF NOT EXISTS "ix_examens_labo_statut" ON "m5"."examens_labo" ("statut");
CREATE TABLE IF NOT EXISTS "m5"."plages_reactif" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."plages_reactif" IS 'Collection « plagesReactif » — M5 Laboratoire';
CREATE TABLE IF NOT EXISTS "m5"."poches" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."poches" IS 'Collection « poches » — M5 Laboratoire';
CREATE TABLE IF NOT EXISTS "m5"."unites_labo" (
  "id" text PRIMARY KEY,
  "source" text,
  "statut" text,
  "domaine" text,
  "libelle" text,
  "symbole" text,
  "a_valider" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."unites_labo" IS 'Collection « unitesLabo » — M5 Laboratoire';
CREATE INDEX IF NOT EXISTS "ix_unites_labo_statut" ON "m5"."unites_labo" ("statut");
CREATE TABLE IF NOT EXISTS "m5"."variables_labo" (
  "id" text PRIMARY KEY,
  "max" numeric,
  "min" numeric,
  "code" text,
  "type" text,
  "actif" boolean,
  "ordre" integer,
  "regle" text,
  "unite" text,
  "examen" text,
  "normal" text,
  "parent" text,
  "source" text,
  "statut" text,
  "libelle" text,
  "section" text,
  "valeurs" jsonb,
  "a_valider" boolean,
  "decimales" integer,
  "retractable" boolean,
  "examen_libelle" text,
  "accompagnement" boolean,
  "valide_le" date,
  "valide_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "m5"."variables_labo" IS 'Collection « variablesLabo » — M5 Laboratoire';
CREATE INDEX IF NOT EXISTS "ix_variables_labo_code" ON "m5"."variables_labo" ("code");
CREATE INDEX IF NOT EXISTS "ix_variables_labo_type" ON "m5"."variables_labo" ("type");
CREATE INDEX IF NOT EXISTS "ix_variables_labo_statut" ON "m5"."variables_labo" ("statut");
CREATE TABLE IF NOT EXISTS "m6"."dispensations" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."dispensations" IS 'Collection « dispensations » — M6 Pharmacie & stocks';
CREATE TABLE IF NOT EXISTS "m6"."emplacements" (
  "id" text PRIMARY KEY,
  "code" text,
  "zone" text,
  "source" text,
  "statut" text,
  "libelle" text,
  "capacite" text,
  "temperature" text,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."emplacements" IS 'Collection « emplacements » — M6 Pharmacie & stocks';
CREATE INDEX IF NOT EXISTS "ix_emplacements_code" ON "m6"."emplacements" ("code");
CREATE INDEX IF NOT EXISTS "ix_emplacements_statut" ON "m6"."emplacements" ("statut");
CREATE TABLE IF NOT EXISTS "m6"."inventaires" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."inventaires" IS 'Collection « inventaires » — M6 Pharmacie & stocks';
CREATE TABLE IF NOT EXISTS "m6"."lots" (
  "id" text PRIMARY KEY,
  "statut" text,
  "produit" text,
  "numero_lot" text,
  "produit_id" text,
  "emplacement" text,
  "date_peremption" date,
  "quantite_restante" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."lots" IS 'Collection « lots » — M6 Pharmacie & stocks';
CREATE INDEX IF NOT EXISTS "ix_lots_statut" ON "m6"."lots" ("statut");
CREATE INDEX IF NOT EXISTS "ix_lots_produit_id" ON "m6"."lots" ("produit_id");
CREATE TABLE IF NOT EXISTS "m6"."mouvements" (
  "id" text PRIMARY KEY,
  "date" date,
  "type" text,
  "statut" text,
  "cree_le" timestamptz,
  "produit" text,
  "cree_par" text,
  "quantite" integer,
  "produit_id" text,
  "reference" text,
  "stock_type" text,
  "type_label" text,
  "utilisateur" text,
  "justificatif" text,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."mouvements" IS 'Collection « mouvements » — M6 Pharmacie & stocks';
CREATE INDEX IF NOT EXISTS "ix_mouvements_date" ON "m6"."mouvements" ("date");
CREATE INDEX IF NOT EXISTS "ix_mouvements_type" ON "m6"."mouvements" ("type");
CREATE INDEX IF NOT EXISTS "ix_mouvements_statut" ON "m6"."mouvements" ("statut");
CREATE INDEX IF NOT EXISTS "ix_mouvements_produit_id" ON "m6"."mouvements" ("produit_id");
CREATE INDEX IF NOT EXISTS "ix_mouvements_reference" ON "m6"."mouvements" ("reference");
CREATE TABLE IF NOT EXISTS "m6"."produits" (
  "id" text PRIMARY KEY,
  "code" text,
  "cump" numeric,
  "stock" integer,
  "unite" text,
  "source" text,
  "statut" text,
  "categorie" text,
  "lot_import" text,
  "prix_achat" integer,
  "prix_vente" integer,
  "stock_gros" integer,
  "date_import" date,
  "designation" text,
  "emplacement" text,
  "fournisseur" text,
  "seuil_alerte" integer,
  "stock_detail" integer,
  "valorise_sage" boolean,
  "seuil_a_valider" boolean,
  "seuil_confirme_le" date,
  "quantite_importee" integer,
  "source_valorisation" text,
  "valorisation_provisoire" boolean,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."produits" IS 'Collection « produits » — M6 Pharmacie & stocks';
CREATE INDEX IF NOT EXISTS "ix_produits_code" ON "m6"."produits" ("code");
CREATE INDEX IF NOT EXISTS "ix_produits_statut" ON "m6"."produits" ("statut");
CREATE TABLE IF NOT EXISTS "m6"."transferts" (
  "id" text PRIMARY KEY,
  "date" date,
  "etat" text,
  "motif" text,
  "unite" text,
  "statut" text,
  "valeur" numeric,
  "cree_le" timestamptz,
  "produit" text,
  "cree_par" text,
  "nb_lignes" integer,
  "quantite" integer,
  "demandeur" text,
  "operateur" text,
  "reference" text,
  "date_reception" date,
  "quantite_totale" integer,
  "receptionnaire" text,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."transferts" IS 'Collection « transferts » — M6 Pharmacie & stocks';
CREATE INDEX IF NOT EXISTS "ix_transferts_date" ON "m6"."transferts" ("date");
CREATE INDEX IF NOT EXISTS "ix_transferts_etat" ON "m6"."transferts" ("etat");
CREATE INDEX IF NOT EXISTS "ix_transferts_statut" ON "m6"."transferts" ("statut");
CREATE INDEX IF NOT EXISTS "ix_transferts_reference" ON "m6"."transferts" ("reference");
CREATE TABLE IF NOT EXISTS "m6"."transferts_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "lot" text,
  "code" text,
  "cump" numeric,
  "unite" text,
  "produit" text,
  "quantite" integer,
  "categorie" text,
  "produit_id" text,
  "peremption" date,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m6"."transferts" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m6"."transferts_lignes" IS 'Lignes « lignes » de « transferts »';
CREATE TABLE IF NOT EXISTS "m6"."valorisations_sage" (
  "id" text PRIMARY KEY,
  "code" text,
  "date" date,
  "auteur" text,
  "source" text,
  "statut" text,
  "a_valider" boolean,
  "designation" text,
  "observation" text,
  "prix_revient" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m6"."valorisations_sage" IS 'Collection « valorisationsSage » — M6 Pharmacie & stocks';
CREATE INDEX IF NOT EXISTS "ix_valorisations_sage_code" ON "m6"."valorisations_sage" ("code");
CREATE INDEX IF NOT EXISTS "ix_valorisations_sage_date" ON "m6"."valorisations_sage" ("date");
CREATE INDEX IF NOT EXISTS "ix_valorisations_sage_statut" ON "m6"."valorisations_sage" ("statut");
CREATE TABLE IF NOT EXISTS "m7"."besoins" (
  "id" text PRIMARY KEY,
  "date" date,
  "etape" text,
  "motif" text,
  "statut" text,
  "service" text,
  "demandeur" text,
  "reference" text,
  "validee_par" text,
  "montant_estime" integer,
  "extra" jsonb
);
COMMENT ON TABLE "m7"."besoins" IS 'Collection « besoins » — M7 Achats & fournisseurs';
CREATE INDEX IF NOT EXISTS "ix_besoins_date" ON "m7"."besoins" ("date");
CREATE INDEX IF NOT EXISTS "ix_besoins_statut" ON "m7"."besoins" ("statut");
CREATE INDEX IF NOT EXISTS "ix_besoins_reference" ON "m7"."besoins" ("reference");
CREATE TABLE IF NOT EXISTS "m7"."besoins_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "unite" text,
  "produit" text,
  "prix_achat" integer,
  "produit_id" text,
  "quantite_livree" integer,
  "quantite_accordee" integer,
  "quantite_demandee" integer,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m7"."besoins" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m7"."besoins_lignes" IS 'Lignes « lignes » de « besoins »';
CREATE TABLE IF NOT EXISTS "m7"."commandes" (
  "id" text PRIMARY KEY,
  "date" date,
  "statut" text,
  "montant" integer,
  "reference" text,
  "validee_par" text,
  "fournisseur" text,
  "date_validation" date,
  "delai_livraison" integer,
  "fournisseur_nom" text,
  "statut_commande" text,
  "extra" jsonb
);
COMMENT ON TABLE "m7"."commandes" IS 'Collection « commandes » — M7 Achats & fournisseurs';
CREATE INDEX IF NOT EXISTS "ix_commandes_date" ON "m7"."commandes" ("date");
CREATE INDEX IF NOT EXISTS "ix_commandes_statut" ON "m7"."commandes" ("statut");
CREATE INDEX IF NOT EXISTS "ix_commandes_reference" ON "m7"."commandes" ("reference");
CREATE TABLE IF NOT EXISTS "m7"."commandes_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "unite" text,
  "montant" integer,
  "produit" text,
  "quantite" integer,
  "produit_id" text,
  "prix_unitaire" integer,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m7"."commandes" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m7"."commandes_lignes" IS 'Lignes « lignes » de « commandes »';
CREATE TABLE IF NOT EXISTS "m7"."factures_fournisseurs" (
  "id" text PRIMARY KEY,
  "date" date,
  "bl_ref" text,
  "ecart" integer,
  "statut" text,
  "echeance" date,
  "reference" text,
  "commande_ref" text,
  "fournisseur" text,
  "statut_rappro" text,
  "fournisseur_nom" text,
  "montant_facture" integer,
  "statut_paiement" text,
  "montant_livraison" integer,
  "numero_fournisseur" text,
  "extra" jsonb
);
COMMENT ON TABLE "m7"."factures_fournisseurs" IS 'Collection « facturesFournisseurs » — M7 Achats & fournisseurs';
CREATE INDEX IF NOT EXISTS "ix_factures_fournisseurs_date" ON "m7"."factures_fournisseurs" ("date");
CREATE INDEX IF NOT EXISTS "ix_factures_fournisseurs_statut" ON "m7"."factures_fournisseurs" ("statut");
CREATE INDEX IF NOT EXISTS "ix_factures_fournisseurs_reference" ON "m7"."factures_fournisseurs" ("reference");
CREATE TABLE IF NOT EXISTS "m7"."fournisseurs" (
  "id" text PRIMARY KEY,
  "ifu" text,
  "nom" text,
  "tel" text,
  "code" text,
  "type" text,
  "delai" integer,
  "ville" text,
  "banque" text,
  "cle_rib" text,
  "compte" text,
  "source" text,
  "statut" text,
  "adresse" text,
  "guichet" text,
  "habilite" boolean,
  "code_banque" text,
  "code_client" text,
  "certification" text,
  "extra" jsonb
);
COMMENT ON TABLE "m7"."fournisseurs" IS 'Collection « fournisseurs » — M7 Achats & fournisseurs';
CREATE INDEX IF NOT EXISTS "ix_fournisseurs_code" ON "m7"."fournisseurs" ("code");
CREATE INDEX IF NOT EXISTS "ix_fournisseurs_type" ON "m7"."fournisseurs" ("type");
CREATE INDEX IF NOT EXISTS "ix_fournisseurs_statut" ON "m7"."fournisseurs" ("statut");
CREATE TABLE IF NOT EXISTS "m7"."livraisons" (
  "id" text PRIMARY KEY,
  "date" date,
  "statut" text,
  "montant" integer,
  "reference" text,
  "commande_ref" text,
  "controle_par" jsonb,
  "fournisseur" text,
  "fournisseur_nom" text,
  "statut_reception" text,
  "extra" jsonb
);
COMMENT ON TABLE "m7"."livraisons" IS 'Collection « livraisons » — M7 Achats & fournisseurs';
CREATE INDEX IF NOT EXISTS "ix_livraisons_date" ON "m7"."livraisons" ("date");
CREATE INDEX IF NOT EXISTS "ix_livraisons_statut" ON "m7"."livraisons" ("statut");
CREATE INDEX IF NOT EXISTS "ix_livraisons_reference" ON "m7"."livraisons" ("reference");
CREATE TABLE IF NOT EXISTS "m7"."livraisons_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "ecart" integer,
  "unite" text,
  "montant" integer,
  "produit" text,
  "quantite" integer,
  "produit_id" text,
  "prix_unitaire" integer,
  "quantite_livree" integer,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m7"."livraisons" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m7"."livraisons_lignes" IS 'Lignes « lignes » de « livraisons »';
CREATE TABLE IF NOT EXISTS "m7"."pv_receptions" (
  "id" text PRIMARY KEY,
  "date" date,
  "nature" text,
  "statut" text,
  "reserves" text,
  "reference" text,
  "conclusion" text,
  "magasinier" text,
  "chaine_froid" boolean,
  "commande_ref" text,
  "livraison_ref" text,
  "fournisseur_nom" text,
  "representant_fournisseur" text,
  "extra" jsonb
);
COMMENT ON TABLE "m7"."pv_receptions" IS 'Collection « pvReceptions » — M7 Achats & fournisseurs';
CREATE INDEX IF NOT EXISTS "ix_pv_receptions_date" ON "m7"."pv_receptions" ("date");
CREATE INDEX IF NOT EXISTS "ix_pv_receptions_nature" ON "m7"."pv_receptions" ("nature");
CREATE INDEX IF NOT EXISTS "ix_pv_receptions_statut" ON "m7"."pv_receptions" ("statut");
CREATE INDEX IF NOT EXISTS "ix_pv_receptions_reference" ON "m7"."pv_receptions" ("reference");
CREATE TABLE IF NOT EXISTS "m7"."pv_receptions_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "ecart" integer,
  "unite" text,
  "livree" integer,
  "produit" text,
  "commandee" integer,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m7"."pv_receptions" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m7"."pv_receptions_lignes" IS 'Lignes « lignes » de « pvReceptions »';
CREATE TABLE IF NOT EXISTS "m8"."avoirs" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m8"."avoirs" IS 'Collection « avoirs » — M8 Facturation & caisse';
CREATE TABLE IF NOT EXISTS "m8"."factures" (
  "id" text PRIMARY KEY,
  "date" date,
  "type" text,
  "numero" text,
  "statut" text,
  "cree_le" timestamptz,
  "patient" text,
  "cree_par" text,
  "assureur" text,
  "reliquat" integer,
  "base_mecef" integer,
  "montant_ht" integer,
  "patient_id" text,
  "modifie_le" timestamptz,
  "montant_ttc" integer,
  "modifie_par" text,
  "montant_brut" integer,
  "montant_paye" integer,
  "numero_mecef" text,
  "part_patient" integer,
  "patient_code" text,
  "personnel_id" text,
  "statut_mecef" text,
  "total_remise" integer,
  "mode_paiement" text,
  "ordonnance_id" text,
  "part_assurance" integer,
  "part_personnel" integer,
  "statut_paiement" text,
  "dernier_reglement" jsonb,
  "ordonnance_numero" text,
  "taux_prise_en_charge" integer,
  "dossier_consultation_id" text,
  "prise_en_charge_personnel" boolean,
  "origine_demande" text,
  "prescripteur_exterieur" text,
  "taux_remise" integer,
  "motif_remise" text,
  "souscripteur" text,
  "extra" jsonb
);
COMMENT ON TABLE "m8"."factures" IS 'Collection « factures » — M8 Facturation & caisse';
CREATE INDEX IF NOT EXISTS "ix_factures_date" ON "m8"."factures" ("date");
CREATE INDEX IF NOT EXISTS "ix_factures_type" ON "m8"."factures" ("type");
CREATE INDEX IF NOT EXISTS "ix_factures_numero" ON "m8"."factures" ("numero");
CREATE INDEX IF NOT EXISTS "ix_factures_statut" ON "m8"."factures" ("statut");
CREATE INDEX IF NOT EXISTS "ix_factures_patient_id" ON "m8"."factures" ("patient_id");
CREATE INDEX IF NOT EXISTS "ix_factures_personnel_id" ON "m8"."factures" ("personnel_id");
CREATE INDEX IF NOT EXISTS "ix_factures_ordonnance_id" ON "m8"."factures" ("ordonnance_id");
CREATE INDEX IF NOT EXISTS "ix_factures_dossier_consultation_id" ON "m8"."factures" ("dossier_consultation_id");
CREATE TABLE IF NOT EXISTS "m8"."factures_lignes" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "id" text,
  "paye_le" timestamptz,
  "remise" integer,
  "montant" integer,
  "paye_par" text,
  "acte_code" text,
  "quantite" integer,
  "categorie" text,
  "demande_id" text,
  "produit_id" text,
  "designation" text,
  "montant_brut" integer,
  "motif_remise" text,
  "part_patient" integer,
  "montant_regle" integer,
  "part_assureur" integer,
  "prix_unitaire" integer,
  "part_personnel" integer,
  "statut_paiement" text,
  "prix_unitaire_net" integer,
  "demande_imagerie_id" text,
  "taux_remise" integer,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m8"."factures" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m8"."factures_lignes" IS 'Lignes « lignes » de « factures »';
CREATE TABLE IF NOT EXISTS "m9"."assureurs" (
  "n" integer,
  "id" text PRIMARY KEY,
  "nom" text,
  "tel" jsonb,
  "code" text,
  "email" text,
  "statut" text,
  "assures" integer,
  "convention" text,
  "extra" jsonb
);
COMMENT ON TABLE "m9"."assureurs" IS 'Collection « assureurs » — M9 Assurances & créances';
CREATE INDEX IF NOT EXISTS "ix_assureurs_code" ON "m9"."assureurs" ("code");
CREATE INDEX IF NOT EXISTS "ix_assureurs_statut" ON "m9"."assureurs" ("statut");
CREATE TABLE IF NOT EXISTS "m9"."couvertures_assurance" (
  "_rang" integer PRIMARY KEY,
  "extra" jsonb
);
COMMENT ON TABLE "m9"."couvertures_assurance" IS 'Collection « couverturesAssurance » — M9 Assurances & créances';
CREATE TABLE IF NOT EXISTS "m9"."factures_mere" (
  "id" text PRIMARY KEY,
  "fin" date,
  "etat" text,
  "debut" date,
  "numero" text,
  "statut" text,
  "cree_le" timestamptz,
  "periode" text,
  "cree_par" text,
  "controle" jsonb,
  "emise_par" text,
  "reliquat" integer,
  "compagnie" text,
  "nb_factures" integer,
  "date_emission" date,
  "montant_regle" integer,
  "periode_label" text,
  "pieces_filles" jsonb,
  "compagnie_code" text,
  "date_reglement" date,
  "montant_reclame" integer,
  "nb_souscripteurs" integer,
  "reference_reglement" text,
  "extra" jsonb
);
COMMENT ON TABLE "m9"."factures_mere" IS 'Collection « facturesMere » — M9 Assurances & créances';
CREATE INDEX IF NOT EXISTS "ix_factures_mere_etat" ON "m9"."factures_mere" ("etat");
CREATE INDEX IF NOT EXISTS "ix_factures_mere_numero" ON "m9"."factures_mere" ("numero");
CREATE INDEX IF NOT EXISTS "ix_factures_mere_statut" ON "m9"."factures_mere" ("statut");
CREATE INDEX IF NOT EXISTS "ix_factures_mere_periode" ON "m9"."factures_mere" ("periode");
CREATE TABLE IF NOT EXISTS "m9"."factures_mere_souscripteurs" (
  "parent_id" text NOT NULL,
  "rang" integer NOT NULL,
  "montant" integer,
  "patient" integer,
  "assureur" integer,
  "nb_factures" integer,
  "souscripteur" text,
  "extra" jsonb,
  PRIMARY KEY ("parent_id", "rang"),
  FOREIGN KEY ("parent_id") REFERENCES "m9"."factures_mere" ("id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE "m9"."factures_mere_souscripteurs" IS 'Lignes « souscripteurs » de « facturesMere »';
CREATE TABLE IF NOT EXISTS "m9"."garanties" (
  "id" text PRIMARY KEY,
  "code" text,
  "taux" integer,
  "statut" text,
  "cree_le" timestamptz,
  "libelle" text,
  "plafond" integer,
  "cree_par" text,
  "assureur" text,
  "categorie" text,
  "unite_plafond" text,
  "souscripteur_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "m9"."garanties" IS 'Collection « garanties » — M9 Assurances & créances';
CREATE INDEX IF NOT EXISTS "ix_garanties_code" ON "m9"."garanties" ("code");
CREATE INDEX IF NOT EXISTS "ix_garanties_statut" ON "m9"."garanties" ("statut");
CREATE INDEX IF NOT EXISTS "ix_garanties_souscripteur_id" ON "m9"."garanties" ("souscripteur_id");
CREATE TABLE IF NOT EXISTS "m9"."souscripteurs" (
  "id" text PRIMARY KEY,
  "nom" text,
  "police" text,
  "source" text,
  "statut" text,
  "contact" text,
  "date_fin" text,
  "assureur" text,
  "effectif" integer,
  "categorie" text,
  "date_debut" date,
  "actes_exclus" jsonb,
  "assureur_nom" text,
  "grille_saisie" boolean,
  "produits_exclus" jsonb,
  "accord_prealable" jsonb,
  "extra" jsonb
);
COMMENT ON TABLE "m9"."souscripteurs" IS 'Collection « souscripteurs » — M9 Assurances & créances';
CREATE INDEX IF NOT EXISTS "ix_souscripteurs_statut" ON "m9"."souscripteurs" ("statut");
CREATE TABLE IF NOT EXISTS "socle"."appels" (
  "id" text PRIMARY KEY,
  "sens" text,
  "agent" text,
  "objet" text,
  "suite" text,
  "statut" text,
  "date_heure" timestamptz,
  "reference" text,
  "telephone" text,
  "interlocuteur" text,
  "extra" jsonb
);
COMMENT ON TABLE "socle"."appels" IS 'Collection « appels » — Socle commun (référentiels lus par plusieurs modules)';
CREATE INDEX IF NOT EXISTS "ix_appels_statut" ON "socle"."appels" ("statut");
CREATE INDEX IF NOT EXISTS "ix_appels_date_heure" ON "socle"."appels" ("date_heure");
CREATE INDEX IF NOT EXISTS "ix_appels_reference" ON "socle"."appels" ("reference");
CREATE TABLE IF NOT EXISTS "socle"."taches" (
  "id" text PRIMARY KEY,
  "date" timestamptz,
  "icon" text,
  "role" text,
  "type" text,
  "ecran" text,
  "titre" text,
  "detail" text,
  "fait_le" timestamptz,
  "module" text,
  "statut" text,
  "urgent" boolean,
  "cree_le" timestamptz,
  "fait_par" text,
  "montant" integer,
  "patient" text,
  "cree_par" text,
  "facture_id" text,
  "reference" text,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "patient_code" text,
  "ordonnance_id" text,
  "facture_numero" text,
  "poste" text,
  "cree_le_2" timestamptz,
  "libelle" text,
  "patient_id" text,
  "extra" jsonb
);
COMMENT ON TABLE "socle"."taches" IS 'Collection « taches » — Socle commun (référentiels lus par plusieurs modules)';
CREATE INDEX IF NOT EXISTS "ix_taches_date" ON "socle"."taches" ("date");
CREATE INDEX IF NOT EXISTS "ix_taches_type" ON "socle"."taches" ("type");
CREATE INDEX IF NOT EXISTS "ix_taches_statut" ON "socle"."taches" ("statut");
CREATE INDEX IF NOT EXISTS "ix_taches_facture_id" ON "socle"."taches" ("facture_id");
CREATE INDEX IF NOT EXISTS "ix_taches_reference" ON "socle"."taches" ("reference");
CREATE INDEX IF NOT EXISTS "ix_taches_ordonnance_id" ON "socle"."taches" ("ordonnance_id");
CREATE INDEX IF NOT EXISTS "ix_taches_patient_id" ON "socle"."taches" ("patient_id");
CREATE TABLE IF NOT EXISTS "socle"."visites_hospi" (
  "id" text PRIMARY KEY,
  "lit" text,
  "date" date,
  "type" text,
  "heure" text,
  "statut" text,
  "patient" text,
  "visiteur" text,
  "admission_id" text,
  "observation" text,
  "patient_code" text,
  "extra" jsonb
);
COMMENT ON TABLE "socle"."visites_hospi" IS 'Collection « visitesHospi » — Socle commun (référentiels lus par plusieurs modules)';
CREATE INDEX IF NOT EXISTS "ix_visites_hospi_date" ON "socle"."visites_hospi" ("date");
CREATE INDEX IF NOT EXISTS "ix_visites_hospi_type" ON "socle"."visites_hospi" ("type");
CREATE INDEX IF NOT EXISTS "ix_visites_hospi_statut" ON "socle"."visites_hospi" ("statut");
CREATE INDEX IF NOT EXISTS "ix_visites_hospi_admission_id" ON "socle"."visites_hospi" ("admission_id");
CREATE TABLE IF NOT EXISTS "sup"."support" (
  "id" text PRIMARY KEY,
  "date" date,
  "etat" text,
  "type" text,
  "objet" text,
  "auteur" text,
  "etapes" text,
  "module" text,
  "statut" text,
  "cree_le" timestamptz,
  "capture" text,
  "cree_par" text,
  "courriel" text,
  "reference" text,
  "description" text,
  "modifie_le" timestamptz,
  "modifie_par" text,
  "extra" jsonb
);
COMMENT ON TABLE "sup"."support" IS 'Collection « support » — Support';
CREATE INDEX IF NOT EXISTS "ix_support_date" ON "sup"."support" ("date");
CREATE INDEX IF NOT EXISTS "ix_support_etat" ON "sup"."support" ("etat");
CREATE INDEX IF NOT EXISTS "ix_support_type" ON "sup"."support" ("type");
CREATE INDEX IF NOT EXISTS "ix_support_statut" ON "sup"."support" ("statut");
CREATE INDEX IF NOT EXISTS "ix_support_reference" ON "sup"."support" ("reference");
