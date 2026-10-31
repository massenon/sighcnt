import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_commun.dart';

/// `m10-stats-presence` — « Taux de présence par service » : LE TAUX SE CALCULE SUR LES JOURS RENSEIGNÉS, pas sur le calendrier (un service dont on n'a pointé que
/// dix jours ne doit pas paraître absent les vingt autres) ; LE RETARD EST COMPTÉ À PART DE L'ABSENCE (un agent en retard est présent).
class EcranStatsPresence extends StatefulWidget with EcranMaquette {
  const EcranStatsPresence({super.key});

  @override
  String get description => 'Présences, retards et absences par service et par agent, sur la période choisie.';

  @override
  String get regle =>
      'Le taux est calculé sur les jours effectivement pointés, non sur le calendrier : un service dont on n’a pointé que dix jours ne doit pas paraître absent les vingt autres. Le retard est compté à part de l’absence — un agent en retard est présent, et les fondre gonflerait l’absentéisme en masquant le vrai sujet.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(libelle: 'Registre des présences', icone: LucideIcons.userCheck, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m10-presences')),
    ];
  }

  @override
  State<EcranStatsPresence> createState() => _EtatStatsPresence();
}

class _EtatStatsPresence extends State<EcranStatsPresence> {
  RhbFiltre? _du, _au;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_du != null) return;
    final c = ContexteEcran.of(context);
    _du = RhbFiltre(const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date), iso(ajouterJours(c.aujourdhui, -29)));
    _au = RhbFiltre(const ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date), iso(c.aujourdhui));
    _du!.controleur.addListener(_maj);
    _au!.controleur.addListener(_maj);
  }

  @override
  void dispose() {
    _du?.controleur.removeListener(_maj);
    _au?.controleur.removeListener(_maj);
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  void _trente(ContexteEcran c) {
    _du!.poser(iso(ajouterJours(c.aujourdhui, -29)));
    _au!.poser(iso(c.aujourdhui));
  }

  String _plage() {
    String f(String s) => DateTime.tryParse(s) == null ? 'NaN/NaN/NaN' : dateFR(DateTime.parse(s));
    return 'Du ${f(_du!.valeur)} au ${f(_au!.valeur)}';
  }

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final rows = rhbPresenceParService(rhbPointagesDans(rhbActives(c, 'presences'), _du!.valeur, _au!.valeur));
    int s(int Function(RhbServicePresence) f) => rows.fold<int>(0, (a, x) => a + f(x));
    ColonneEtat n(String l, int Function(RhbServicePresence) f) =>
        ColonneEtat(libelle: l, droite: true, valeur: (r) => nombre(r[l]), somme: (r) => (r[l] as num));
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'Taux de présence par service',
            sousTitre: _plage(),
            cartouche: [
              ('Période', _plage()),
              ('Services observés', nombre(rows.length)),
              ('Journées pointées', nombre(s((x) => x.observes))),
              ('Retards constatés', nombre(s((x) => x.retards))),
            ],
            filtres: [('Du', _du!.valeur), ('Au', _au!.valeur)],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Service', valeur: (r) => '${r['Service']}'),
                n('Agents', (x) => x.agents),
                n('Journées pointées', (x) => x.observes),
                n('Présents', (x) => x.presents),
                n('Retards', (x) => x.retards),
                n('Absents', (x) => x.absents),
                ColonneEtat(libelle: 'Taux', valeur: (r) => pourcent(r['Taux']), droite: true),
              ], lignes: [
                for (final x in rows)
                  {'Service': x.service, 'Agents': x.agents, 'Journées pointées': x.observes, 'Présents': x.presents, 'Retards': x.retards, 'Absents': x.absents, 'Taux': x.taux}
              ])
            ],
            blocs: const [
              BlocTexte('Le taux est calculé sur les journées effectivement pointées. Le retard est compté comme une présence : l’agent est là.', italique: true)
            ],
            signatures: const [Signature('Le Surveillant'), rhbSignDirecteurAdmin]));
  }

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['presences'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final tous = rhbPointagesDans(rhbActives(c, 'presences'), _du!.valeur, _au!.valeur);
    final rows = rhbPresenceParService(tous);
    final presents = tous.where((x) => x['etat'] != 'absent').length;
    final retards = tous.where((x) => x['etat'] == 'retard').length;
    final absences = tous.length - presents;
    TextStyle txt(Color couleur) => TextStyle(color: couleur, fontSize: 14, height: 20 / 14);
    return rhbEspace([
      rhbBarre([_du!, _au!], boutons: [
        BoutonSigh(libelle: 'Trente derniers jours', taille: TailleBouton.sm, icone: LucideIcons.calendarRange, variante: VarianteBouton.secondaire, onPressed: () => _trente(c)),
        BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c)),
      ]),
      NoteSigh(
          '${nombre(tous.length)} journée(s) pointée(s) sur la période, pour ${nombre(rows.length)} service(s). Le taux porte sur ces journées effectivement renseignées — un pourcentage calculé sur le calendrier ferait passer pour absents des jours qu’on n’a simplement pas pointés.',
          icone: LucideIcons.userCheck),
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Taux de présence global',
            valeur: tous.isNotEmpty ? pourcent(presents / tous.length * 100) : '—',
            icone: LucideIcons.userCheck,
            ton: TonSigh.succes,
            indice: '${nombre(tous.length)} journée(s) observée(s)'),
        KpiSigh(
            libelle: 'Retards',
            valeur: nombre(retards),
            icone: LucideIcons.clockAlert,
            ton: retards > 0 ? TonSigh.attention : TonSigh.succes,
            indice: tous.isNotEmpty ? '${pourcent(retards / tous.length * 100)} des journées' : ''),
        KpiSigh(libelle: 'Absences', valeur: nombre(absences), icone: LucideIcons.userX, ton: absences > 0 ? TonSigh.danger : TonSigh.succes),
        KpiSigh(
            libelle: 'Service le plus assidu',
            valeur: rows.isNotEmpty ? rows.first.service : '—',
            icone: LucideIcons.award,
            ton: TonSigh.navy,
            indice: rows.isNotEmpty ? pourcent(rows.first.taux) : ''),
      ]),
      TableauSigh(
          taillePage: 15,
          nomExport: 'taux-presence-service',
          lignes: [
            for (final x in rows)
              {'service': x.service, 'agents': x.agents, 'observes': x.observes, 'presents': x.presents, 'retards': x.retards, 'absents': x.absents, 'taux': x.taux}
          ],
          colonnes: [
            ColonneTableau(cle: 'service', libelle: 'Service', rendu: (_, r) => Text('${r['service']}', style: rhbCorps)),
            const ColonneTableau(cle: 'agents', libelle: 'Agents', droite: true),
            const ColonneTableau(cle: 'observes', libelle: 'Journées pointées', droite: true),
            ColonneTableau(cle: 'presents', libelle: 'Présents', droite: true, texte: (r) => nombre(r['presents']), rendu: (_, r) => Text(nombre(r['presents']), style: txt(JetonsShell.success700))),
            ColonneTableau(
                cle: 'retards',
                libelle: 'Retards',
                droite: true,
                texte: (r) => (r['retards'] as int) > 0 ? nombre(r['retards']) : '—',
                rendu: (_, r) => (r['retards'] as int) > 0
                    ? Text(nombre(r['retards']), style: txt(JetonsShell.warning700))
                    : Text('—', style: txt(JetonsShell.slate300))),
            ColonneTableau(
                cle: 'absents',
                libelle: 'Absents',
                droite: true,
                texte: (r) => (r['absents'] as int) > 0 ? nombre(r['absents']) : '—',
                rendu: (_, r) => (r['absents'] as int) > 0
                    ? Text(nombre(r['absents']), style: txt(JetonsShell.danger600))
                    : Text('—', style: txt(JetonsShell.slate300))),
            ColonneTableau(
                cle: 'taux',
                libelle: 'Taux de présence',
                droite: true,
                texte: (r) => pourcent(r['taux']),
                rendu: (_, r) {
                  final t = r['taux'] as num;
                  return BadgeSigh(pourcent(t), ton: t >= 95 ? TonSigh.succes : (t >= 85 ? TonSigh.attention : TonSigh.danger));
                }),
          ]),
      if (rows.isNotEmpty)
        rhbDeuxCartes([
          CarteSigh(
              titre: 'Taux de présence par service',
              child: GraphiqueBarres(
                  horizontal: true,
                  hauteur: 300,
                  etiquettes: [for (final x in rows) x.service],
                  series: [SerieGraphique('Taux de présence (%)', [for (final x in rows) x.taux], couleur: rhbTonVert)])),
          CarteSigh(
              titre: 'Présents, retards et absences par service',
              child: GraphiqueBarres(horizontal: true, hauteur: 300, etiquettes: [
                for (final x in rows) x.service
              ], series: [
                SerieGraphique('Présents', [for (final x in rows) x.presents], couleur: rhbTonVert),
                SerieGraphique('Retards', [for (final x in rows) x.retards], couleur: rhbTonOrange),
                SerieGraphique('Absents', [for (final x in rows) x.absents], couleur: rhbTonRouge),
              ])),
        ]),
    ]);
  }
}
