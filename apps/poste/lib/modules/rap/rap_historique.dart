import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../dash/tbb_commun.dart' show ClassementSigh;
import 'rap_commun.dart';

/// `rapports-historique` — « Historique des éditions » : le journal des documents générés, imprimés et exportés, avec l'utilisateur à l'origine de
/// l'édition (RG-12). Écran en LECTURE SEULE : l'historique retrace ce qui a été imprimé, il constitue une preuve et ne peut être retouché — aucune
/// commande d'écriture.
///
/// Les éditions sont celles que le journal d'audit a retenues (action « Impression », écrite par « Archiver » à l'aperçu), complétées par un jeu de
/// démonstration jusqu'à soixante lignes (`rapEditions`, graine 3221 — comme la maquette). L'écran PRODUIT une trace : fermé aux rôles qui n'écrivent pas.
class EcranRapHistorique extends StatelessWidget with EcranMaquette {
  const EcranRapHistorique({super.key});

  @override
  String get titre => 'Historique des éditions';

  @override
  String get description =>
      'Journal des documents générés, imprimés et exportés, avec l’utilisateur à l’origine de l’édition.';

  @override
  String get regle =>
      'Écran en lecture seule. L’historique des éditions retrace ce qui a été imprimé : il constitue une preuve et ne peut être retouché.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final audit = c.magasin.collection('audit'),
        personnel = c.magasin.collection('personnel');
    return ListenableBuilder(
        listenable: Listenable.merge([audit, personnel]),
        builder: (context, _) {
          final rows = rapEditions(
              audit.toutes,
              [for (final p in personnel.actives) '${p['nomComplet']}'],
              c.aujourdhui);
          final st = rapStatsHistorique(rows, c.aujourdhui);
          final parModule = rapGrouper(rows, 'module');
          final modules = parModule.keys.toList()..sort();
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KpiGrilleSigh(kpis: [
                  KpiSigh(
                      libelle: 'Éditions enregistrées',
                      valeur: nombre(st.editions),
                      icone: LucideIcons.printer,
                      ton: TonSigh.navy),
                  KpiSigh(
                      libelle: 'Ce mois-ci',
                      valeur: nombre(st.ceMois),
                      icone: LucideIcons.calendar,
                      ton: TonSigh.info),
                  KpiSigh(
                      libelle: 'Exports PDF',
                      valeur: nombre(st.pdf),
                      icone: LucideIcons.fileText,
                      ton: TonSigh.succes),
                  KpiSigh(
                      libelle: 'Utilisateurs distincts',
                      valeur: nombre(st.utilisateurs),
                      icone: LucideIcons.users,
                      ton: TonSigh.neutre),
                ]),
                const SizedBox(height: 16),
                const NoteSigh(
                    'Chaque édition est journalisée avec son identifiant unique de document, l’utilisateur générateur et l’horodatage, conformément à l’exigence de traçabilité (RG-12).'),
                const SizedBox(height: 16),
                TableauSigh(
                  titre: 'Journal des éditions',
                  lignes: rows,
                  taillePage: 20,
                  nomExport: 'historique-editions',
                  filtres: [
                    FiltreTableau(
                        nom: 'format',
                        libelle: 'Format',
                        options: [for (final f in rapFormats) OptionChamp(f)]),
                    FiltreTableau(
                        nom: 'module',
                        libelle: 'Module',
                        options: [for (final m in modules) OptionChamp(m)]),
                  ],
                  colonnes: [
                    ColonneTableau(
                        cle: 'reference',
                        libelle: 'Réf. document',
                        sansCoupure: true,
                        rendu: (_, r) =>
                            Text('${r['reference']}', style: rapMono)),
                    ColonneTableau(
                        cle: 'dateHeure',
                        libelle: 'Horodatage',
                        sansCoupure: true,
                        valeur: (r) => rapMs(r['dateHeure']) ?? 0,
                        texte: (r) {
                          final d = rapDateHeure(r['dateHeure']);
                          return d == null ? '' : dateHeure(d);
                        }),
                    const ColonneTableau(cle: 'etat', libelle: 'État édité'),
                    ColonneTableau(
                        cle: 'module',
                        libelle: 'Module',
                        rendu: (_, r) =>
                            BadgeSigh('${r['module']}', ton: TonSigh.navy)),
                    ColonneTableau(
                        cle: 'format',
                        libelle: 'Format',
                        rendu: (_, r) => BadgeSigh('${r['format']}')),
                    const ColonneTableau(
                        cle: 'utilisateur', libelle: 'Généré par'),
                    ColonneTableau(
                        cle: 'poste',
                        libelle: 'Poste',
                        sansCoupure: true,
                        rendu: (_, r) => Text('${r['poste']}',
                            style:
                                rapMono.copyWith(color: JetonsShell.slate500))),
                  ],
                ),
                const SizedBox(height: 16),
                rapDeux(
                  CarteSigh(
                      titre: 'Éditions par module',
                      child: GraphiqueBarres(
                          etiquettes: parModule.keys.toList(),
                          series: [
                            SerieGraphique('Éditions',
                                [for (final l in parModule.values) l.length])
                          ])),
                  CarteSigh(
                      titre: 'États les plus édités',
                      child: ClassementSigh(rapEtatsLesPlusEdites(rows))),
                ),
              ]);
        });
  }
}
