import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';

/// `m10-stats-permanences` — « Statistiques des permanences » : la permanence (08h–18h) n'est PAS la garde (24 h) — deux fatigues, deux rémunérations, deux
/// lignes de la NS 132. Les compter ensemble effacerait la distinction que la note de service a établie. Repos et congés restent exclus.
class EcranStatsPermanences extends StatefulWidget with EcranMaquette {
  const EcranStatsPermanences({super.key});

  @override
  String get description =>
      'Nombre de permanences assurées par agent, par service et par fonction, sur la période choisie.';

  @override
  String get regle =>
      'La permanence (08h–18h) n’est pas la garde (24h) : deux fatigues, deux rémunérations, deux lignes de la NS 132. Les compter ensemble effacerait la distinction que la note de service a établie — c’est pourquoi cet écran existe à côté des statistiques de garde. Repos et congés restent exclus : ils figurent au planning mais ne sont pas du travail effectué.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(libelle: 'Statistiques de garde', icone: LucideIcons.chartColumn, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m10-stats-gardes')),
      BoutonSigh(libelle: 'Planning', icone: LucideIcons.calendarClock, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m10-planning')),
    ];
  }

  @override
  State<EcranStatsPermanences> createState() => _EtatStatsPermanences();
}

class _EtatStatsPermanences extends State<EcranStatsPermanences> {
  RhbFiltre? _periode, _date, _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_periode != null) return;
    final c = ContexteEcran.of(context);
    final services = <String>{for (final a in rhbActives(c, 'personnel')) '${a['service']}'}.toList()..sort();
    _periode = RhbFiltre(
        ChampDef(nom: 'periode', libelle: 'Périodicité', type: TypeChamp.select, options: [for (final p in periodes) OptionChamp(p.id, p.label)]), 'mois');
    _date = RhbFiltre(const ChampDef(nom: 'arret', libelle: 'Arrêtée au', type: TypeChamp.date), iso(c.aujourdhui));
    _service = RhbFiltre(ChampDef(nom: 'service', libelle: 'Service', type: TypeChamp.select, options: [
      for (final s in ['— Tous les services —', ...services]) OptionChamp(s)
    ]));
    for (final f in [_periode!, _date!, _service!]) {
      f.controleur.addListener(_maj);
    }
  }

  @override
  void dispose() {
    for (final f in [_periode!, _date!, _service!]) {
      f.controleur.removeListener(_maj);
    }
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  Bornes _bornes() => bornes(_periode!.valeur, DateTime.tryParse(_date!.valeur) ?? DateTime.now());

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final b = _bornes();
    final rows = rhbPermanencesParAgent(rhbActives(c, 'planning'), rhbActives(c, 'personnel'), b, _service!.valeur);
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Statistiques des permanences',
            sousTitre: libellePeriode(b),
            cartouche: [
              ('Période', libellePeriode(b)),
              ('Service', _service!.valeur),
              ('Permanences assurées', nombre(rows.fold<int>(0, (s, x) => s + x.nombre))),
              ('Agents concernés', nombre(rows.length)),
            ],
            filtres: [('Périodicité', b.label), ('Arrêtée au', dateFR(b.fin)), ('Service', _service!.valeur)],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Agent', valeur: (r) => '${r['agent']}'),
                ColonneEtat(libelle: 'Matricule', valeur: (r) => '${r['matricule']}'),
                ColonneEtat(libelle: 'Service', valeur: (r) => '${r['service']}'),
                ColonneEtat(libelle: 'Fonction', valeur: (r) => '${r['fonction']}'),
                ColonneEtat(libelle: 'Permanences', valeur: (r) => nombre(r['nombre']), droite: true, somme: (r) => r['nombre'] as num),
              ], lignes: [
                for (final x in rows) {'agent': x.agent, 'matricule': x.matricule, 'service': x.service, 'fonction': x.fonction, 'nombre': x.nombre}
              ])
            ],
            signatures: const [Signature('Le Surveillant'), rhbSignDirecteurAdmin]));
  }

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['planning', 'personnel'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final b = _bornes();
    final rows = rhbPermanencesParAgent(rhbActives(c, 'planning'), rhbActives(c, 'personnel'), b, _service!.valeur);
    final total = rows.fold<int>(0, (s, x) => s + x.nombre);
    final parSvc = <String, int>{};
    for (final x in rows) {
      parSvc[x.service] = (parSvc[x.service] ?? 0) + x.nombre;
    }
    final svcRows = trierPar([for (final e in parSvc.entries) (e.key, e.value)], (e) => e.$2, descendant: true);
    return rhbEspace([
      rhbBarre([_periode!, _date!, _service!], colonnes: 6, boutons: [
        BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c)),
      ]),
      NoteSigh(
          '${libellePeriode(b)} — ${nombre(total)} permanence(s) assurée(s) par ${nombre(rows.length)} agent(s). La permanence court de 08h à 18h ; la garde de vingt-quatre heures est comptée sur son propre écran.',
          icone: LucideIcons.clock9),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Permanences assurées', valeur: nombre(total), icone: LucideIcons.clock9, ton: TonSigh.navy),
        KpiSigh(libelle: 'Agents concernés', valeur: nombre(rows.length), icone: LucideIcons.users, ton: TonSigh.info),
        KpiSigh(libelle: 'Moyenne par agent', valeur: rows.isNotEmpty ? rhbUneDecimale(total / rows.length) : '0', icone: LucideIcons.scale, ton: TonSigh.neutre),
        KpiSigh(
            libelle: 'Le plus sollicité',
            valeur: rows.isNotEmpty ? rows.first.agent : '—',
            icone: LucideIcons.award,
            ton: TonSigh.attention,
            indice: rows.isNotEmpty ? '${nombre(rows.first.nombre)} permanence(s)' : ''),
      ]),
      TableauSigh(
          taillePage: 20,
          nomExport: 'stats-permanences',
          filtres: [
            FiltreTableau(nom: 'service', libelle: 'Service', options: [for (final s in (parSvc.keys.toList()..sort())) OptionChamp(s)])
          ],
          lignes: [
            for (final x in rows) {'agent': x.agent, 'matricule': x.matricule, 'service': x.service, 'fonction': x.fonction, 'nombre': x.nombre}
          ],
          colonnes: [
            ColonneTableau(
                cle: 'agent',
                libelle: 'Agent',
                texte: (r) => '${r['agent']}',
                rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('${r['agent']}', style: rhbCorps),
                      Text('Mat. ${r['matricule']}', style: const TextStyle(color: JetonsShell.slate400, fontSize: 10, height: 1.4)),
                    ])),
            ColonneTableau(cle: 'service', libelle: 'Service', texte: (r) => '${r['service']}', rendu: (_, r) => BadgeSigh('${r['service']}', ton: TonSigh.navy)),
            const ColonneTableau(cle: 'fonction', libelle: 'Fonction'),
            ColonneTableau(
                cle: 'nombre',
                libelle: 'Permanences',
                droite: true,
                texte: (r) => nombre(r['nombre']),
                rendu: (_, r) => Text(nombre(r['nombre']), style: const TextStyle(color: JetonsShell.navy800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700))),
          ]),
      if (rows.isNotEmpty)
        rhbDeuxCartes([
          CarteSigh(
              titre: 'Permanences par agent',
              child: GraphiqueBarres(
                  horizontal: true,
                  hauteur: 300,
                  etiquettes: [for (final x in rows.take(12)) x.agent.split(' ').first],
                  series: [SerieGraphique('Permanences', [for (final x in rows.take(12)) x.nombre], couleur: JetonsShell.navy600)])),
          CarteSigh(
              titre: 'Permanences par service',
              child: GraphiqueAnneau(etiquettes: [for (final e in svcRows) e.$1], valeurs: [for (final e in svcRows) e.$2])),
        ]),
    ]);
  }
}
