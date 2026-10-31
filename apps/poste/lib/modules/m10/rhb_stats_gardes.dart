import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';

const _navy = Color(0xFF12315E);
const _bleu = Color(0xFF3765A6);
const _vert = Color(0xFF22A170);

/// `m10-stats-gardes` — « Statistiques de garde » : combien de gardes (et de vacations travaillées) chaque agent a effectuées, sur la plage choisie.
/// Les repos et les congés sont EXCLUS : les compter ferait apparaître les agents les plus reposés comme les plus chargés. Ces nombres multiplient
/// les primes de la NS 132.
class EcranStatsGardes extends StatefulWidget with EcranMaquette {
  const EcranStatsGardes({super.key});

  @override
  String get description =>
      'Nombre de gardes effectuées par agent, par service et par type de vacation, sur la période choisie.';

  @override
  String get regle =>
      'Le comptage porte sur les vacations travaillées — gardes, permanences, soirées, entretien et incinération. Les repos et congés en sont exclus : ils figurent au planning mais ne constituent pas du travail effectué, et les compter inverserait le classement. Ces nombres sont ceux qui multiplient les primes de la NS 132.';

  @override
  State<EcranStatsGardes> createState() => _EtatStatsGardes();
}

class _EtatStatsGardes extends State<EcranStatsGardes> {
  RhbFiltre? _periode, _du, _au, _agent, _service, _type, _fonction;
  List<RhbFiltre> get _tous => [_periode!, _du!, _au!, _agent!, _service!, _type!, _fonction!];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_periode != null) return;
    final c = ContexteEcran.of(context);
    _periode = RhbFiltre(
        ChampDef(
            nom: 'periode',
            libelle: 'Périodicité',
            type: TypeChamp.select,
            options: [for (final p in rhbPeriodesGarde) OptionChamp(p.id, p.label)]),
        'mois');
    _du = RhbFiltre(const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date));
    _au = RhbFiltre(const ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date));
    _agent = RhbFiltre(ChampDef(nom: 'agent', libelle: 'Agent', type: TypeChamp.select, options: [
      const OptionChamp('', 'Tous les agents'),
      for (final e in rhbPersonnelTrie(c)) OptionChamp('${e['id']}', '${e['nomComplet']}')
    ]));
    _service = RhbFiltre(ChampDef(nom: 'service', libelle: 'Service', type: TypeChamp.select, options: [
      const OptionChamp('', 'Tous les services'),
      for (final s in rhbServices) OptionChamp(s)
    ]));
    _type = RhbFiltre(ChampDef(nom: 'type', libelle: 'Type de vacation', type: TypeChamp.select, options: [
      const OptionChamp('', 'Toutes les vacations travaillées'),
      for (final t in rhbTypesPlanning)
        if (rhbVacationsTravaillees.contains(t.id)) OptionChamp(t.id, t.label)
    ]));
    _fonction = RhbFiltre(ChampDef(nom: 'fonction', libelle: 'Fonction', type: TypeChamp.select, options: [
      const OptionChamp('', 'Toutes les fonctions'),
      for (final f in rhbFonctions) OptionChamp(f.id, f.label)
    ]));
    _appliquerPeriode(c);
    for (final f in _tous) {
      f.controleur.addListener(_maj);
    }
    _periode!.controleur.addListener(() => _appliquerPeriode(ContexteEcran.of(context)));
  }

  @override
  void dispose() {
    for (final f in _tous) {
      f.controleur.removeListener(_maj);
    }
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  /// La périodicité POSITIONNE la plage ; « plage libre » la laisse à l'agent (sans quoi les deux réglages se contrrediraient).
  void _appliquerPeriode(ContexteEcran c) {
    final p = rhbPlageDePeriode(_periode!.valeur, c.aujourdhui);
    if (p == null) return;
    _au!.poser(p.$2);
    _du!.poser(p.$1);
  }

  List<Fiche> _lignes(ContexteEcran c) => rhbLignesGardes(rhbActives(c, 'planning'),
      du: _du!.valeur, au: _au!.valeur, agent: _agent!.valeur, service: _service!.valeur, type: _type!.valeur, fonction: _fonction!.valeur);

  List<(String, String)> _filtres() => [
        ('Périodicité', rhbPeriodesGarde.firstWhere((p) => p.id == _periode!.valeur).label),
        ('Du', _du!.valeur.isEmpty ? '—' : dateFR(DateTime.parse(_du!.valeur))),
        ('Au', _au!.valeur.isEmpty ? '—' : dateFR(DateTime.parse(_au!.valeur))),
        if (_agent!.valeur.isNotEmpty) ('Agent', _agent!.def.options.firstWhere((o) => o.valeur == _agent!.valeur).libelle),
        if (_service!.valeur.isNotEmpty) ('Service', _service!.valeur),
        if (_type!.valeur.isNotEmpty) ('Type de vacation', rhbTypePlanningLabel(_type!.valeur)),
        if (_fonction!.valeur.isNotEmpty) ('Fonction', rhbFonctionLabel(_fonction!.valeur)),
      ];

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final agents = rhbParAgentGardes(_lignes(c));
    final lib = rhbLibellePlageGardes(_du!.valeur, _au!.valeur);
    final lignes = <Fiche>[
      for (final a in agents)
        {
          'agent': a.agent, 'fonction': a.fonctionLabel, 'service': a.service,
          'gardes': a.gardes, 'permanences': a.permanences, 'soirees': a.soirees, 'total': a.total, 'heures': a.heures
        }
    ];
    ColonneEtat n(String l, String k) => ColonneEtat(libelle: l, valeur: (r) => nombre(r[k]), droite: true, somme: (r) => r[k] as num);
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'État des gardes effectuées',
            sousTitre: lib,
            cartouche: [
              ('Période', lib),
              ('Agents concernés', nombre(agents.length)),
              ('Vacations travaillées', nombre(agents.fold<int>(0, (s, a) => s + a.total))),
              ('Dont gardes', nombre(agents.fold<int>(0, (s, a) => s + a.gardes))),
              ('Établi par', c.utilisateur),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            filtres: _filtres(),
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Agent', valeur: (r) => '${r['agent']}'),
                ColonneEtat(libelle: 'Fonction', valeur: (r) => '${r['fonction']}'),
                ColonneEtat(libelle: 'Service', valeur: (r) => '${r['service']}'),
                n('Gardes', 'gardes'),
                n('Permanences', 'permanences'),
                n('Soirées', 'soirees'),
                n('Total', 'total'),
                ColonneEtat(libelle: 'Heures', valeur: (r) => '${nombre(r['heures'])} h', droite: true, somme: (r) => r['heures'] as num),
              ], lignes: lignes)
            ],
            blocs: const [
              BlocTexte(
                  'Comptage des vacations travaillées : gardes, permanences, soirées, entretien général et incinération. Les repos et congés en sont exclus. Ce décompte est celui qui multiplie les primes de garde et de permanence de la note de service NS n° 132/07/DM/DA/CNT/2026.',
                  italique: true)
            ],
            signatures: [rhbSignSurveillant, rhbSignDaf]));
  }

  @override
  Widget build(BuildContext context) {
    return RhbEcoute(collections: const ['planning', 'personnel'], construire: (ctx, c) => _corps(ctx, c));
  }

  Widget _corps(BuildContext context, ContexteEcran c) {
    final rows = _lignes(c);
    final agents = rhbParAgentGardes(rows);
    final jours = rhbJoursPlage(_du!.valeur, _au!.valeur);
    final lib = rhbLibellePlageGardes(_du!.valeur, _au!.valeur);
    final nGardes = rows.where((v) => '${v['type']}'.startsWith('garde')).length;
    return rhbEspace([
      rhbBarre(_tous, colonnes: 6, boutons: [
        BoutonSigh(libelle: 'Appliquer', icone: LucideIcons.filter, onPressed: () => setState(() {})),
        BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, c)),
      ]),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Vacations travaillées', valeur: nombre(rows.length), icone: LucideIcons.calendarCheck, ton: TonSigh.navy, indice: jours > 0 ? 'sur ${nombre(jours)} jour(s)' : null),
        KpiSigh(libelle: 'Gardes', valeur: nombre(nGardes), icone: LucideIcons.moon, ton: TonSigh.danger, indice: 'multiplicateur des primes NS 132'),
        KpiSigh(libelle: 'Agents concernés', valeur: nombre(agents.length), icone: LucideIcons.users, ton: TonSigh.info),
        KpiSigh(
            libelle: 'Moyenne par agent',
            valeur: agents.isNotEmpty ? rhbDecimalJs(rows.length / agents.length) : '0',
            icone: LucideIcons.scale,
            ton: TonSigh.neutre,
            indice: 'vacations sur la période'),
      ]),
      if (rows.isEmpty)
        const CarteSigh(
            titre: 'Statistiques de garde',
            child: VideSigh('Aucune vacation sur la période et les filtres retenus.',
                icone: LucideIcons.calendarX,
                indice: 'Élargir la plage de dates ou retirer un filtre. Les repos et congés ne sont jamais comptés.'))
      else ...[
        TableauSigh(
            titre: 'Gardes par agent — $lib',
            taillePage: 20,
            triInitial: 'total',
            sensInitial: 'desc',
            nomExport: 'statistiques-gardes',
            lignes: [
              for (final a in agents)
                {
                  'agent': a.agent, 'fonctionLabel': a.fonctionLabel, 'service': a.service, 'gardes': a.gardes,
                  'permanences': a.permanences, 'soirees': a.soirees, 'autres': a.autres, 'total': a.total, 'heures': a.heures
                }
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'agent',
                  libelle: 'Agent',
                  texte: (r) => '${r['agent']}',
                  rendu: (_, r) => rhbAgentCellule('${r['agent']}', '${r['fonctionLabel']} · ${r['service']}')),
              ColonneTableau(
                  cle: 'gardes', libelle: 'Gardes', droite: true, texte: (r) => nombre(r['gardes']),
                  rendu: (_, r) => Text(nombre(r['gardes']), style: const TextStyle(color: Color(0xFFA1281F), fontSize: 14, fontWeight: FontWeight.w600))),
              const ColonneTableau(cle: 'permanences', libelle: 'Permanences', droite: true),
              const ColonneTableau(cle: 'soirees', libelle: 'Soirées', droite: true),
              const ColonneTableau(cle: 'autres', libelle: 'Autres', droite: true),
              ColonneTableau(
                  cle: 'total', libelle: 'Total', droite: true, texte: (r) => nombre(r['total']),
                  rendu: (_, r) => Text(nombre(r['total']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              ColonneTableau(cle: 'heures', libelle: 'Heures', droite: true, texte: (r) => '${nombre(r['heures'])} h'),
            ]),
        rhbTroisCartes([
          CarteSigh(
              titre: 'Charge par agent — les dix premiers',
              child: GraphiqueBarres(
                  horizontal: true,
                  hauteur: 280,
                  etiquettes: [for (final a in agents.take(10)) a.agent],
                  series: [SerieGraphique('Vacations', [for (final a in agents.take(10)) a.total], couleur: _navy)])),
          () {
            final g = rhbGrouper(rows, (v) => v['service'] == null || v['service'] == '' ? 'Non renseigné' : '${v['service']}');
            return CarteSigh(
                titre: 'Répartition par service',
                child: GraphiqueAnneau(
                    trou: 0, hauteur: 280, etiquettes: g.keys.toList(), valeurs: [for (final l in g.values) l.length]));
          }(),
          () {
            final g = rhbGrouper(rows, (v) => '${v['type']}');
            return CarteSigh(
                titre: 'Répartition par type de vacation',
                child: GraphiqueBarres(
                    hauteur: 280,
                    etiquettes: [for (final k in g.keys) rhbTypePlanningLabel(k)],
                    series: [SerieGraphique('Vacations', [for (final l in g.values) l.length], couleur: _bleu)]));
          }(),
        ]),
        ...() {
          final g = rhbGrouper(rows, (v) => '${v['date']}'.substring(0, 7));
          final mois = g.keys.toList()..sort();
          if (mois.length <= 1) return <Widget>[];
          return <Widget>[
            CarteSigh(
                titre: 'Évolution du nombre de vacations',
                child: GraphiqueLigne(
                    hauteur: 240,
                    etiquettes: [for (final m in mois) moisAnnee(DateTime.parse('$m-01'))],
                    series: [SerieGraphique('Vacations', [for (final m in mois) g[m]!.length], couleur: _vert)]))
          ];
        }(),
      ],
    ]);
  }
}
