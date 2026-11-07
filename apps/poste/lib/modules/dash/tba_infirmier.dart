import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m2/cs_commun.dart' show stockDe;
import 'tba_commun.dart';

/// `dash-infirmier` — « Tableau de bord — Infirmier / Sage-femme » : la règle de relais. L'infirmier et la sage-femme viennent chercher ce qui leur
/// revient MAINTENANT (les administrations dues à la salle de soins), pas la liste de tout.
class EcranDashInfirmier extends StatelessWidget with EcranMaquette {
  const EcranDashInfirmier({super.key});

  @override
  String get titre => 'Tableau de bord — Infirmier / Sage-femme';

  @override
  String get description =>
      'Patients hospitalisés, relevés de constantes attendus, sorties à préparer et gardes du jour.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['admissions', 'prescriptions', 'administrations', 'taches']),
      builder: (context, _) {
        // `PR.soinsDuSecteur('salle_soins')` : le rang du passage décide du secteur — la règle de relais vit au domaine (`csSoinsDuSecteur`).
        final dues = csSoinsDuSecteur(stockDe(c), 'salle_soins').fold<int>(0, (n, d) => n + d.lignes.length);
        final d = tbaInfirmier(admissions: tbaActives(c, 'admissions'), administrationsDues: dues, auj: c.aujourdhui);
        return TbaDash(
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m3-feuille-temperature', 'thermometer', 'Feuille de température', 'Saisie des constantes'),
              ('m3-admissions', 'user-plus', 'Nouvelle admission', 'Affecter un lit'),
              ('m3-sorties', 'door-open', 'Sortie d’hospitalisation', 'RG-06 / RG-07 — signatures'),
              ('m4-accouchements', 'baby', 'Accouchement', 'Maternité et naissance'),
            ]),
            tbaCarte('Ce que vous faites ici — vos parcours', const ParcoursSigh(_parcours)),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'Patients hospitalisés — service',
                d.hospitalises.isEmpty
                    ? const VideSigh('Aucun patient hospitalisé actuellement.', icone: LucideIcons.bed)
                    : tbaMiniTableau([
                        ColonneMini('Lit', (a) => '${a['lit'] ?? ''}',
                            rendu: (a) => Text('${a['lit'] ?? ''}',
                                style: const TextStyle(
                                    fontFamily: 'LiberationMono', fontSize: 12, fontWeight: FontWeight.w600, color: JetonsShell.slate700))),
                        ColonneMini('Patient', (a) => '${a['patient'] ?? ''}'),
                        ColonneMini('Dossier', (a) => '${a['patientCode'] ?? ''}', rendu: (a) => tbaMono(a['patientCode'])),
                        ColonneMini('Entrée', (a) => tbaDate(a['dateEntree'])),
                        ColonneMini('Jours', (a) => _jours(a['dateEntree'], c.aujourdhui), droite: true),
                        ColonneMini('Diagnostic', (a) => '${a['diagnosticEntree'] ?? ''}'),
                        ColonneMini('Prise en charge', (a) => '', rendu: (a) => statutBadge(a['priseEnCharge'])),
                      ], d.hospitalises),
                actions: [tbaLien(c, 'm3-plan-lits', 'Plan des lits', 'layout-grid')],
                sansRemplissage: d.hospitalises.isNotEmpty),
          ],
        );
      },
    );
  }
}

String _jours(Object? entree, DateTime auj) {
  final e = DateTime.tryParse('${entree ?? ''}');
  return e == null ? '' : '${joursEntre(e, auj)}';
}

const _parcours = [
  ParcoursTba('Administrer les soins dus', 'syringe', 'Salle de soins', 'Ce qui revient à votre poste maintenant.', [
    EtapeTba('Voir ce qui vous revient',
        ecran: 'm2-salle-soins', detail: 'Ambulatoire : tous les passages. Hospitalier : la PREMIÈRE administration.'),
    EtapeTba('Administrer sous votre nom', ecran: 'm2-salle-soins', detail: 'Une prescription non réglée reste visible mais non exécutable.'),
    EtapeTba('Les passages suivants', poste: 'Hospitalisation'),
  ]),
  ParcoursTba('Surveiller un hospitalisé', 'activity', 'Fiche de surveillance', 'Relevé des constantes au lit du patient.', [
    EtapeTba('Relever les constantes', ecran: 'm1-constantes'),
    EtapeTba('Lire la courbe à cinq échelles', ecran: 'm3-surveillance', detail: 'Même donnée que la feuille de température, autre présentation.'),
    EtapeTba('Évaluer la conscience si nécessaire', ecran: 'm3-glasgow', detail: 'Le score est calculé, borné de 3 à 15.'),
    EtapeTba('Prévenir le médecin si aggravation', poste: 'Consultation'),
  ]),
  ParcoursTba('Poser une transfusion', 'droplets', 'Surveiller', 'Une poche de PSL est posée.', [
    EtapeTba('Ouvrir la fiche de surveillance transfusionnelle',
        ecran: 'm3-transfusion', detail: 'Huit temps imposés : avant la pose, 15 min, toutes les 30 min, fin, 1 h, 2 h.'),
    EtapeTba('Relever à chaque temps', ecran: 'm3-transfusion'),
    EtapeTba('Signaler tout incident immédiatement', poste: 'Médecin'),
  ]),
  ParcoursTba('Préparer une sortie', 'log-out', 'Sorties', 'Le séjour se termine.', [
    EtapeTba('Vérifier le solde', ecran: 'm8-reliquats', detail: 'RG-06.'),
    EtapeTba('Établir la fiche de sortie', ecran: 'm3-sorties', detail: 'RG-07 — trois signatures, dont le constat du gardien.'),
    EtapeTba('Remettre le traitement de sortie', poste: 'Pharmacie'),
  ]),
];
