import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'res_commun.dart';

/// `m5-stats` — « Statistiques du laboratoire ». « Pouvoir ressortir les statistiques des examens réalisés en fonction des services, de l'âge,
/// du sexe, période, interne ou externe. » — les cinq axes sont demandés nommément. Chaque axe est un FILTRE : compteurs, graphiques et tableau se
/// recalculent sur la population filtrée. Le comptage porte sur les demandes ENREGISTRÉES, qu'elles soient rendues ou en cours.
class EcranStatsLabo extends StatefulWidget with EcranMaquette {
  const EcranStatsLabo({super.key, this.periode, this.du, this.au});

  /// Périodicité et plage initiales (lien profond) ; sans elles, le mois en cours.
  final String? periode;
  final String? du;
  final String? au;

  @override
  String get titre => 'Statistiques du laboratoire';

  @override
  String get description =>
      'Examens réalisés par service, âge, sexe, période et origine du patient ; consommation des réactifs.';

  @override
  String get regle =>
      'Les cinq axes demandés par le laboratoire : service demandeur, âge, sexe, période, patient interne ou externe. La périodicité va de la semaine à l’année, plage libre comprise. Le comptage porte sur les demandes enregistrées, qu’elles soient rendues ou en cours.';

  @override
  State<EcranStatsLabo> createState() => _EtatStatsLabo();
}

class _EtatStatsLabo extends State<EcranStatsLabo> {
  ControleurFormulaire? _f;
  String _periodeVue = 'mois';

  ControleurFormulaire _creer(DateTime auj) {
    final b = bornesPeriodeLabo('mois', auj)!;
    _periodeVue = widget.periode ?? 'mois';
    final f = ControleurFormulaire([
      ChampDef(
          nom: 'periode',
          libelle: 'Périodicité',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in periodesLabo) OptionChamp(x.id, x.label)]),
      const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date),
      const ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date),
      ChampDef(nom: 'section', libelle: 'Section', type: TypeChamp.select, options: [
        const OptionChamp('', 'Toutes les sections'),
        for (final s in sectionsLabo) OptionChamp(s.$1, s.$2)
      ]),
      ChampDef(
          nom: 'service',
          libelle: 'Service demandeur',
          type: TypeChamp.select,
          options: [
            const OptionChamp('', 'Tous les services'),
            for (final s in servicesDemandeursLabo) OptionChamp(s.$2, s.$2)
          ]),
      ChampDef(
          nom: 'origine',
          libelle: 'Origine du patient',
          type: TypeChamp.select,
          options: [
            const OptionChamp('', 'Interne et externe'),
            for (final s in originesPatient) OptionChamp(s.$1, s.$2)
          ]),
      const ChampDef(nom: 'sexe', libelle: 'Sexe', type: TypeChamp.select, options: [
        OptionChamp('', 'Les deux sexes'),
        OptionChamp('M', 'Masculin'),
        OptionChamp('F', 'Féminin')
      ]),
    ], {
      'periode': widget.periode ?? 'mois',
      'du': widget.du ?? b.du,
      'au': widget.au ?? b.au
    });
    f.addListener(_surChangement);
    return f;
  }

  void _surChangement() {
    final f = _f!;
    final per = '${f['periode']}';
    if (per != _periodeVue) {
      _periodeVue = per;
      final b = bornesPeriodeLabo(per, _auj);
      if (b != null) {
        f.removeListener(_surChangement);
        f.poser('du', b.du);
        f.poser('au', b.au);
        f.addListener(_surChangement);
      }
    }
    if (mounted) setState(() {});
  }

  DateTime _auj = DateTime.now();

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  FiltresStatsLabo _filtres() {
    final f = _f!;
    return FiltresStatsLabo(
        du: '${f['du'] ?? ''}',
        au: '${f['au'] ?? ''}',
        section: '${f['section'] ?? ''}',
        service: '${f['service'] ?? ''}',
        origine: '${f['origine'] ?? ''}',
        sexe: '${f['sexe'] ?? ''}');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    _auj = c.aujourdhui;
    _f ??= _creer(c.aujourdhui);
    final f = _f!;
    final examens = examensLabo(c);
    return ListenableBuilder(
      listenable: ecouteLabo(c),
      builder: (context, _) {
        final patients = c.magasin.collection('patients').actives;
        final rows = lignesStats(c.magasin.collection('demandesAnalyses').actives, patients, _filtres(), examens);
        final s = calculerStatsLabo(rows, patients, examens, maintenant: c.aujourdhui);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: LayoutBuilder(builder: (_, k) {
            final l = k.maxWidth >= 1024
                ? (k.maxWidth - 5 * 12) / 6
                : (k.maxWidth >= 768 ? (k.maxWidth - 2 * 12) / 3 : k.maxWidth);
            return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
              for (final nom in ['periode', 'du', 'au', 'section', 'service', 'origine', 'sexe'])
                SizedBox(width: l, child: _ChampLie(f, nom)),
              Wrap(spacing: 8, children: [
                BoutonSigh(
                    key: const Key('res:appliquer'),
                    libelle: 'Appliquer',
                    icone: LucideIcons.filter,
                    onPressed: () => setState(() {})),
                BoutonSigh(
                    key: const Key('res:imprimer-etat'),
                    libelle: 'Imprimer l’état',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _imprimer(context, c, s)),
              ]),
            ]);
          })),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Examens demandés',
                valeur: nombre(s.demandes),
                icone: LucideIcons.clipboardList,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Résultats rendus',
                valeur: nombre(s.rendus),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.succes,
                indice: s.indiceRendus),
            KpiSigh(
                libelle: 'Demandes urgentes',
                valeur: nombre(s.urgents),
                icone: LucideIcons.siren,
                ton: s.urgents > 0 ? TonSigh.danger : TonSigh.neutre),
            KpiSigh(
                libelle: 'Patients distincts',
                valeur: nombre(s.patientsDistincts),
                icone: LucideIcons.users,
                ton: TonSigh.info),
          ]),
          const SizedBox(height: 16),
          if (s.demandes == 0)
            const CarteSigh(
                titre: 'Statistiques',
                child: VideSigh('Aucun examen sur la période et les filtres retenus.',
                    icone: LucideIcons.chartColumn))
          else
            ..._corps(c, s),
        ]);
      },
    );
  }

  List<Widget> _corps(ContexteEcran c, StatsLabo s) {
    final f = _f!;
    Widget carte(String t, Widget w) => CarteSigh(titre: t, child: w);
    Widget trois(List<Widget> l) => LayoutBuilder(builder: (_, k) {
          final n = k.maxWidth >= 1024 ? l.length : 1;
          final w = n == 1 ? k.maxWidth : (k.maxWidth - 16 * (n - 1)) / n;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final x in l) SizedBox(width: w, child: x)
          ]);
        });
    final legende = tranchesAge.map((t) => t.label).toList();
    return [
      carte('Les examens les plus demandés',
          ClassementLabo(s.topExamens, unite: 'demande(s)')),
      const SizedBox(height: 16),
      trois([
        carte('Par section du bulletin',
            GraphiqueAnneau(
                etiquettes: [for (final x in s.parSection) x.$1],
                valeurs: [for (final x in s.parSection) x.$2],
                hauteur: 260,
                trou: 0)),
        carte('Par service demandeur',
            GraphiqueBarres(
                horizontal: true,
                hauteur: 260,
                etiquettes: [for (final x in s.parService) x.$1],
                series: [
                  SerieGraphique('Examens', [for (final x in s.parService) x.$2],
                      couleur: JetonsShell.navy900)
                ])),
        carte('Patient interne ou externe',
            GraphiqueAnneau(
                etiquettes: [for (final x in s.parOrigine) x.$1],
                valeurs: [for (final x in s.parOrigine) x.$2],
                hauteur: 260)),
      ]),
      const SizedBox(height: 16),
      trois([
        carte('Par sexe',
            GraphiqueAnneau(
                etiquettes: [for (final x in s.parSexe) x.$1],
                valeurs: [for (final x in s.parSexe) x.$2],
                hauteur: 260)),
        carte('Par tranche d’âge',
            GraphiqueBarres(
                hauteur: 260,
                etiquettes: legende,
                series: [
                  SerieGraphique('Examens', s.parAge, couleur: JetonsShell.success500)
                ])),
      ]),
      if (s.parJour.length > 1) ...[
        const SizedBox(height: 16),
        carte('Volume d’examens au fil du temps',
            GraphiqueLigne(
                hauteur: 240,
                etiquettes: [for (final j in s.parJour) dateFrJs(j.$1)],
                series: [
                  SerieGraphique('Examens', [for (final j in s.parJour) j.$2],
                      couleur: JetonsShell.navy900)
                ])),
      ],
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Détail des examens — ${dateFrJs('${f['du']}')} au ${dateFrJs('${f['au']}')}',
        taillePage: 20,
        nomExport: 'statistiques-laboratoire',
        lignes: [
          for (final d in s.detail)
            {
              'examen': d.examen,
              'section': d.section,
              'total': d.total,
              'rendus': d.rendus,
              'urgents': d.urgents,
              'externes': d.externes
            }
        ],
        colonnes: [
          const ColonneTableau(cle: 'examen', libelle: 'Examen'),
          ColonneTableau(
              cle: 'section',
              libelle: 'Section',
              texte: (r) => '${r['section']}',
              rendu: (_, r) => BadgeSigh('${r['section']}', ton: TonSigh.navy)),
          ColonneTableau(
              cle: 'total',
              libelle: 'Demandes',
              droite: true,
              texte: (r) => nombre(r['total']),
              rendu: (_, r) => Text(nombre(r['total']),
                  style: styleLabo(14, poids: FontWeight.w600))),
          const ColonneTableau(cle: 'rendus', libelle: 'Rendus', droite: true),
          const ColonneTableau(cle: 'urgents', libelle: 'Urgents', droite: true),
          const ColonneTableau(
              cle: 'externes', libelle: 'Patients externes', droite: true),
        ],
      ),
    ];
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, StatsLabo s) {
    final f = _f!;
    final du = dateFrJs('${f['du']}'), au = dateFrJs('${f['au']}');
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Activité du laboratoire d’analyses biomédicales',
          sousTitre: 'Du $du au $au',
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Période', '$du – $au'),
            ('Examens demandés', nombre(s.demandes)),
            ('Résultats rendus', nombre(s.rendus)),
            ('Patients distincts', nombre(s.patientsDistincts)),
            ('Établi par', c.utilisateur),
            ('Date d’édition', dateFR(c.aujourdhui)),
          ],
          blocs: [
            // Des comptages, pas des francs : chaque colonne porte sa somme.
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Examen', valeur: (l) => l['examen']),
              ColonneEtat(
                  libelle: 'Demandes',
                  valeur: (l) => nombre(l['total']),
                  droite: true,
                  somme: (l) => l['total'] as num),
              ColonneEtat(
                  libelle: 'Rendus',
                  valeur: (l) => nombre(l['rendus']),
                  droite: true,
                  somme: (l) => l['rendus'] as num),
              ColonneEtat(
                  libelle: 'Urgents',
                  valeur: (l) => nombre(l['urgents']),
                  droite: true,
                  somme: (l) => l['urgents'] as num),
              ColonneEtat(
                  libelle: 'Patients externes',
                  valeur: (l) => nombre(l['externes']),
                  droite: true,
                  somme: (l) => l['externes'] as num),
            ], lignes: [
              for (final d in s.detail)
                {
                  'examen': d.examen,
                  'total': d.total,
                  'rendus': d.rendus,
                  'urgents': d.urgents,
                  'externes': d.externes
                }
            ])),
          ],
          signatures: const [
            Signature('Le Biologiste médical'),
            Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko'),
          ],
        ));
  }
}

/// Un champ du bandeau de filtres, relié au contrôleur commun : un `FormulaireSigh` à UN champ qui lit et écrit la valeur du contrôleur partagé.
class _ChampLie extends StatefulWidget {
  const _ChampLie(this.maitre, this.nom);
  final ControleurFormulaire maitre;
  final String nom;
  @override
  State<_ChampLie> createState() => _EtatChampLie();
}

class _EtatChampLie extends State<_ChampLie> {
  late ControleurFormulaire _local;

  @override
  void initState() {
    super.initState();
    _local = ControleurFormulaire(
        [widget.maitre.champs.firstWhere((x) => x.nom == widget.nom)],
        {widget.nom: widget.maitre[widget.nom]});
    _local.addListener(_versMaitre);
    widget.maitre.addListener(_depuisMaitre);
  }

  void _versMaitre() {
    final v = _local[widget.nom];
    if (widget.maitre[widget.nom] != v) widget.maitre.poser(widget.nom, v);
  }

  void _depuisMaitre() {
    final v = widget.maitre[widget.nom];
    if (_local[widget.nom] != v) {
      _local.removeListener(_versMaitre);
      _local.poser(widget.nom, v);
      _local.addListener(_versMaitre);
    }
  }

  @override
  void dispose() {
    widget.maitre.removeListener(_depuisMaitre);
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormulaireSigh(controleur: _local);
}
