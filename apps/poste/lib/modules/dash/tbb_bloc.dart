import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tbb_commun.dart';

/// Tableaux de bord du bloc (chirurgien, anesthésiste) et de la comptabilité (assistant comptable). Lecture seule : règles dans
/// `packages/domaine/lib/src/tableaux_de_bord/tbb_regles.dart`, rejouées sur les vecteurs de la maquette.

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-chirurgien
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashChirurgien extends StatelessWidget with EcranMaquette {
  const EcranDashChirurgien({super.key});

  @override
  String get titre => 'Tableau de bord — Chirurgien';

  @override
  String get description => 'Bloc opératoire : check-listes, comptes rendus, transfusion et suites opératoires.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['checklistsBloc', 'crOperatoires', 'admissions'],
        construire: (c) => TbbDisposition(
          releve: tbbChirurgien(
              checklists: lire(c, 'checklistsBloc'),
              comptesRendus: lire(c, 'crOperatoires'),
              admissions: lire(c, 'admissions'),
              auj: c.aujourdhui),
          raccourcis: [
            raccourci('m3-bloc-cro', 'file-text', 'Comptes rendus opératoires'),
            raccourci('m3-bloc-checklist', 'clipboard-check', 'Check-listes du bloc'),
            raccourci('m3-transfusion', 'droplets', 'Transfusion'),
            raccourci('m1-patients', 'users', 'Répertoire des patients'),
          ],
          parcours: const [
            ParcoursDef('Opérer et documenter', 'slice', action: 'Check-listes', detail: 'De la check-liste d’entrée au compte rendu signé.', [
              EtapeDef('Check-liste d’ENTRÉE', ecran: 'm3-bloc-checklist'),
              EtapeDef('Intervention, puis check-liste de SORTIE', ecran: 'm3-bloc-checklist'),
              EtapeDef('Compte rendu opératoire — trois intervenants nommés', ecran: 'm3-bloc-cro'),
              EtapeDef('Prescrire les suites',
                  ecran: 'm2-prescriptions', detail: 'La première administration revient à la salle de soins, les suivantes à l’hospitalisation.'),
            ]),
            ParcoursDef('Suivre un opéré', 'activity', action: 'Surveillance', [
              EtapeDef('Feuille de surveillance', ecran: 'm3-surveillance'),
              EtapeDef('Feuille de température', ecran: 'm3-feuille-temperature'),
              EtapeDef('Résultats de laboratoire', ecran: 'm5-resultats'),
              EtapeDef('Sortie d’hospitalisation',
                  ecran: 'm3-sorties', poste: 'Caisse', detail: 'Le solde s’apure à la caisse avant la signature de sortie (RG-06).'),
            ]),
          ],
          sections: const [
            CarteSigh(
                titre: 'Périmètre du profil',
                child: NoteSigh(
                    'Ce profil n’ouvre ni la maternité, ni la caisse, ni le stock — matrice cible des Instructions. Le dossier obstétrical relève de la '
                    'sage-femme ; une césarienne se documente au bloc (compte rendu opératoire), son suivi obstétrical en maternité.',
                    icone: LucideIcons.shield)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-anesthesiste
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashAnesthesiste extends StatelessWidget with EcranMaquette {
  const EcranDashAnesthesiste({super.key});

  @override
  String get titre => 'Tableau de bord — Anesthésiste';

  @override
  String get description => 'Sécurité péri-opératoire : check-listes d’entrée, Glasgow, transfusion et surveillance.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['checklistsBloc', 'crOperatoires', 'admissions'],
        construire: (c) => TbbDisposition(
          releve: tbbAnesthesiste(
              checklists: lire(c, 'checklistsBloc'),
              comptesRendus: lire(c, 'crOperatoires'),
              admissions: lire(c, 'admissions'),
              auj: c.aujourdhui),
          raccourcis: [
            raccourci('m3-bloc-checklist', 'clipboard-check', 'Check-listes du bloc'),
            raccourci('m3-glasgow', 'brain', 'Score de Glasgow'),
            raccourci('m3-transfusion', 'droplets', 'Transfusion'),
            raccourci('m5-resultats', 'flask-conical', 'Résultats (lecture)'),
          ],
          parcours: const [
            ParcoursDef('Sécuriser une intervention', 'shield-check', action: 'Check-listes', [
              EtapeDef('Check-liste d’ENTRÉE — avant induction', ecran: 'm3-bloc-checklist'),
              EtapeDef('Surveillance per-opératoire', ecran: 'm3-surveillance'),
              EtapeDef('Check-liste de SORTIE', ecran: 'm3-bloc-checklist'),
              EtapeDef('Glasgow et réveil', ecran: 'm3-glasgow'),
            ]),
            ParcoursDef('Une transfusion au bloc', 'droplets', action: 'Transfusion', [
              EtapeDef('Fiche de surveillance transfusionnelle', ecran: 'm3-transfusion'),
              EtapeDef('Constantes au lit du patient', ecran: 'm1-constantes'),
              EtapeDef('Résultats de laboratoire', ecran: 'm5-resultats'),
            ]),
          ],
          sections: const [
            CarteSigh(
                titre: 'Périmètre du profil',
                child: NoteSigh(
                    'Ce profil n’ouvre ni la maternité, ni la caisse, ni les consultations générales. Ses écrans propres — consultation '
                    'pré-anesthésique, feuille d’anesthésie, suites per et post-opératoires — sont prévus en phase 6 du plan et rejoindront '
                    'l’hospitalisation (M3), dont ce profil hérite.',
                    icone: LucideIcons.shield)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-aide-comptable (« Assistant Comptable », 16ᵉ rôle) — il SAISIT, le Comptable principal VALIDE.
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashAideComptable extends StatelessWidget with EcranMaquette {
  const EcranDashAideComptable({super.key});

  @override
  String get titre => 'Tableau de bord — Assistant Comptable';

  @override
  String get description => 'Saisie des dépenses et des écritures, réceptions fournisseurs et suivi des créances.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['ecritures', 'factures'],
        construire: (c) => TbbDisposition(
          releve: tbbAssistantComptable(ecritures: lire(c, 'ecritures'), factures: lire(c, 'factures'), auj: c.aujourdhui),
          raccourcis: [
            raccourci('m12-depenses', 'wallet', 'Dépenses courantes'),
            raccourci('m12-ecritures', 'book-open', 'Écritures'),
            raccourci('m9-creances', 'shield-alert', 'Créances'),
            raccourci('m7-receptions', 'package-check', 'Réceptions fournisseurs'),
          ],
          parcours: const [
            ParcoursDef('Saisir une dépense', 'wallet', action: 'Dépenses', [
              EtapeDef('Enregistrer la dépense avec son justificatif',
                  ecran: 'm12-depenses', detail: 'Une dépense sans justificatif n’est pas bloquée, elle est comptée et signalée.'),
              EtapeDef('L’écriture naît en brouillon', ecran: 'm12-ecritures'),
              EtapeDef('Validation',
                  ecran: 'm12-ecritures', poste: 'Comptable', detail: 'La validation et l’annulation restent au Comptable principal et à la DAF.'),
            ]),
            ParcoursDef('Suivre les créances', 'shield-alert', action: 'Créances', [
              EtapeDef('État des créances', ecran: 'm9-creances'),
              EtapeDef('Relancer la compagnie', ecran: 'm9-relances'),
              EtapeDef('Rapprocher le règlement', ecran: 'm12-banques'),
            ]),
          ],
          sections: const [
            CarteSigh(
                titre: 'Périmètre du profil',
                child: NoteSigh(
                    'Ce profil n’ouvre aucun écran clinique (RG-13) et la clôture annuelle lui est fermée : elle engage l’exercice et reste au '
                    'Comptable principal et à la DAF. Aucune suppression : D est interdit sur toute la matrice de ce rôle.',
                    icone: LucideIcons.shield)),
          ],
        ),
      );
}
