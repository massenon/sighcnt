import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/adm_commun.dart';
import 'rhb_commun.dart';

const _etats = [OptionChamp('present', 'Présent'), OptionChamp('retard', 'Retard'), OptionChamp('absent', 'Absent'), OptionChamp('conge', 'Congé')];

/// `m10-presences` — « Présences & absences » : pointage quotidien. Le registre couvre ~25 jours par agent, soit plus de mille lignes : sans bornes, on ne
/// trouve rien — la plage se règle puis s'APPLIQUE (les champs de date ne rafraîchissent pas d'eux-mêmes, comme dans la maquette).
class EcranPresences extends StatefulWidget with EcranMaquette {
  const EcranPresences({super.key});

  @override
  String get description => 'Pointage quotidien, retards et absences, avec incidence sur l’évaluation mensuelle.';

  @override
  State<EcranPresences> createState() => _EtatPresences();
}

class _EtatPresences extends State<EcranPresences> {
  RhbFiltre? _du, _au;
  String _duA = '', _auA = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_du != null) return;
    final c = ContexteEcran.of(context);
    _duA = iso(ajouterJours(c.aujourdhui, -30));
    _auA = iso(c.aujourdhui);
    _du = RhbFiltre(const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date), _duA);
    _au = RhbFiltre(const ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date), _auA);
  }

  void _appliquer() => setState(() {
        _duA = _du!.valeur;
        _auA = _au!.valeur;
      });

  void _poser(String du, String au) {
    _du!.poser(du);
    _au!.poser(au);
    _appliquer();
  }

  List<ChampDef> _champs(ContexteEcran c) => [
        ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [
          for (final e in rhbPersonnelTrie(c)) OptionChamp('${e['id']}', '${e['matricule']} — ${e['nomComplet']} (${e['poste']})')
        ]),
        const ChampDef(nom: 'date', libelle: 'Date du pointage', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'etat', libelle: 'État', type: TypeChamp.select, requis: true, options: _etats),
        admChampHeure('heureArrivee', 'Heure d’arrivée', requis: false),
        admChampHeure('heureDepart', 'Heure de départ', requis: false),
        const ChampDef(nom: 'motif', libelle: 'Motif / justification', col: ColChamp.plein),
      ];

  /// `transform` de la maquette : le pointage porte le nom, le matricule et le service de l'agent désigné.
  Fiche _fiche(ContexteEcran c, Map<String, Object?> v, Fiche? existante) {
    final e = rhbActives(c, 'personnel').where((x) => x['id'] == v['employeId']).firstOrNull;
    return {...v, if (e != null) ...{'employe': e['nomComplet'], 'matricule': e['matricule'], 'service': e['service']}};
  }

  void _saisir(BuildContext ctx, ContexteEcran c, {Fiche? existante}) => admSaisir(ctx,
      col: c.magasin.collection('presences'),
      champs: _champs(c),
      fiche: (v, e) => _fiche(c, v, e),
      existante: existante,
      titreCreation: 'Nouveau pointage',
      entite: 'Pointage',
      prefixeId: 'PRS',
      libelleCreer: 'Créer',
      initiales: {'date': iso(c.aujourdhui), 'etat': 'present', 'heureArrivee': '07:45'});

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['presences', 'personnel'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final m = rhbPointagesRegistre(rhbActives(c, 'presences'), _duA, _auA);
    int n(String e) => m.where((r) => r['etat'] == e).length;
    String f(String s) => DateTime.tryParse(s) == null ? 'NaN/NaN/NaN' : dateFR(DateTime.parse(s));
    final col = c.magasin.collection('presences');
    return rhbEspace([
      rhbBarre([_du!, _au!], boutons: [
        BoutonSigh(libelle: 'Appliquer', icone: LucideIcons.filter, onPressed: _appliquer),
        BoutonSigh(
            libelle: 'Mois en cours',
            icone: LucideIcons.calendar,
            variante: VarianteBouton.secondaire,
            onPressed: () => _poser(iso(DateTime(c.aujourdhui.year, c.aujourdhui.month, 1)), iso(c.aujourdhui))),
        BoutonSigh(
            libelle: 'Sept derniers jours',
            icone: LucideIcons.calendarDays,
            variante: VarianteBouton.secondaire,
            onPressed: () => _poser(iso(ajouterJours(c.aujourdhui, -6)), iso(c.aujourdhui))),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KpiGrilleSigh(kpis: [
          KpiSigh(libelle: 'Pointages de la période', valeur: nombre(m.length), icone: LucideIcons.clipboardCheck, ton: TonSigh.navy),
          KpiSigh(libelle: 'Présences', valeur: nombre(n('present')), icone: LucideIcons.circleCheck, ton: TonSigh.succes),
          KpiSigh(libelle: 'Retards', valeur: nombre(n('retard')), icone: LucideIcons.clockAlert, ton: TonSigh.attention, indice: 'Critère NS 131'),
          KpiSigh(libelle: 'Absences', valeur: nombre(n('absent')), icone: LucideIcons.userX, ton: TonSigh.danger),
        ]),
        const SizedBox(height: 8),
        const NoteSigh(
            'Les retards et absences non justifiées alimentent le critère « Ponctualité et assiduité » du barème NS 131, avec incidence directe sur la fiche d’évaluation et le solde du mois.'),
      ]),
      TableauSigh(
          titre: 'Registre des présences — ${f(_duA)} au ${f(_auA)}',
          taillePage: 20,
          triInitial: 'date',
          sensInitial: 'desc',
          nomExport: 'presences',
          selectionnable: true,
          lignes: m,
          filtres: [
            const FiltreTableau(nom: 'etat', libelle: 'État', options: [OptionChamp('present', 'Présent'), OptionChamp('retard', 'Retard'), OptionChamp('absent', 'Absent')]),
            FiltreTableau(nom: 'service', libelle: 'Service', options: [for (final s in rhbServices) OptionChamp(s)]),
          ],
          actions: [
            if (c.droit.editer)
              BoutonSigh(libelle: 'Ajouter un pointage', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _saisir(context, c)),
          ],
          actionsLigne: (ctx, r) => admActionsLigne(ctx, c, col, r, modifier: (x) => _saisir(ctx, c, existante: x)),
          colonnes: [
            ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => f('${r['date']}'), rendu: (_, r) => Text(f('${r['date']}'))),
            const ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
            const ColonneTableau(cle: 'employe', libelle: 'Agent'),
            const ColonneTableau(cle: 'service', libelle: 'Service'),
            ColonneTableau(
                cle: 'etat',
                libelle: 'État',
                texte: (r) => switch (r['etat']) { 'present' => 'Présent', 'retard' => 'Retard', 'absent' => 'Absent', var x => '$x' },
                rendu: (_, r) => switch (r['etat']) {
                      'present' => const BadgeSigh('Présent', ton: TonSigh.succes),
                      'retard' => const BadgeSigh('Retard', ton: TonSigh.attention),
                      'absent' => const BadgeSigh('Absent', ton: TonSigh.danger),
                      // Un congé n'a pas de pastille dans la maquette : sa recherche d'étiquette lève une erreur (écart E657) — le poste le dit en clair.
                      var x => Text('$x'),
                    }),
            const ColonneTableau(cle: 'heureArrivee', libelle: 'Arrivée', droite: true),
            const ColonneTableau(cle: 'heureDepart', libelle: 'Départ', droite: true),
            const ColonneTableau(cle: 'motif', libelle: 'Motif'),
          ]),
      ..._graphes(m),
    ]);
  }

  List<Widget> _graphes(List<Fiche> m) {
    if (m.isEmpty) {
      return const [CarteSigh(titre: 'Statistiques', child: VideSigh('Aucun pointage sur la plage retenue.', icone: LucideIcons.calendarX))];
    }
    final parService = rhbGrouper(m, (r) => '${r['service']}');
    int n(String e) => m.where((r) => r['etat'] == e).length;
    final parJour = rhbGrouper(m, (r) => '${r['date']}');
    final jours = parJour.keys.toList()..sort();
    final rang = trierPar([
      for (final e in parService.entries)
        (e.key, arrondiJs(e.value.where((r) => r['etat'] == 'present').length / e.value.length * 100).toInt())
    ], (e) => e.$2, descendant: true);
    return [
      rhbTroisCartes([
        CarteSigh(titre: 'Taux de présence par service', child: RhbClassement([for (final e in rang) (libelle: e.$1, valeur: e.$2)])),
        CarteSigh(
            titre: 'Répartition des pointages',
            child: GraphiqueAnneau(
                etiquettes: const ['Présences', 'Retards', 'Absences'],
                valeurs: [n('present'), n('retard'), n('absent')],
                couleurs: const [rhbTonVert, rhbTonOrange, rhbTonRouge])),
        CarteSigh(
            titre: 'Volume de pointages par service',
            child: GraphiqueBarres(
                horizontal: true,
                hauteur: 260,
                etiquettes: parService.keys.toList(),
                series: [SerieGraphique('Pointages', [for (final l in parService.values) l.length], couleur: rhbTonNavy)])),
      ]),
      if (jours.length > 1)
        CarteSigh(
            titre: 'Retards et absences au fil des jours',
            child: GraphiqueLigne(hauteur: 240, etiquettes: [
              for (final j in jours) dateFR(DateTime.parse(j))
            ], series: [
              SerieGraphique('Retards', [for (final j in jours) parJour[j]!.where((r) => r['etat'] == 'retard').length], couleur: rhbTonOrange, aire: false),
              SerieGraphique('Absences', [for (final j in jours) parJour[j]!.where((r) => r['etat'] == 'absent').length], couleur: rhbTonRouge, aire: false),
            ])),
    ];
  }
}

/// `K.ranking` avec `format: v + ' %'` : un classement en barres horizontales.
class RhbClassement extends StatelessWidget {
  const RhbClassement(this.lignes, {super.key, this.suffixe = ' %', this.couleur = JetonsShell.success500});
  final List<({String libelle, num valeur})> lignes;
  final String suffixe;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) return const VideSigh('Aucune donnée.');
    final max = lignes.fold<num>(0, (a, l) => l.valeur > a ? l.valeur : a);
    return Column(children: [
      for (final l in lignes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(l.libelle, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              Text('${nombre(l.valeur)}$suffixe', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: max == 0 ? 0 : (l.valeur / max).toDouble(), minHeight: 8, backgroundColor: JetonsShell.slate100, color: couleur)),
          ]),
        ),
    ]);
  }
}
