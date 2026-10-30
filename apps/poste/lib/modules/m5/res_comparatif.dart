import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'res_commun.dart';

/// `m5-resultats-comparatif` — « Comparatif des résultats » : le BI-PANNEAU des antériorités (la colonne « Antériorités » de la fiche de
/// résultats, à l'écran). Deux mesures du même examen côte à côte, variable par variable. Seuls les résultats RENDUS se comparent (comparer
/// une saisie non validée reviendrait à lire par-dessus l'épaule du laboratoire), dans le périmètre du RBAC métier ; chaque colonne se compare
/// aux bornes de SON époque — le lot de réactif en service à sa date.
class EcranComparatifResultats extends StatefulWidget with EcranMaquette {
  const EcranComparatifResultats({super.key, this.fonction, this.secteur, this.agentId});
  final String? fonction;
  final String? secteur;
  final String? agentId;

  @override
  String get titre => 'Comparatif des résultats';

  @override
  String get description =>
      'Deux mesures du même examen côte à côte, variable par variable — la colonne « Antériorités » de la fiche de résultats, à l’écran.';

  @override
  String get regle =>
      'La fiche de résultats de la clinique porte une colonne Antériorités : c’est elle que cet écran développe. Seuls les résultats rendus (validés biologiquement) se comparent — comparer une saisie non validée reviendrait à lire par-dessus l’épaule du laboratoire. Le périmètre est celui du RBAC métier : chacun ne compare que ce qu’il a le droit de voir.';

  @override
  State<EcranComparatifResultats> createState() => _EtatComparatif();
}

class _EtatComparatif extends State<EcranComparatifResultats> {
  ControleurFormulaire? _patient;
  ControleurFormulaire? _examen;
  ControleurFormulaire? _ab;
  String _vuPatient = '', _vuExamen = '';
  String _signatureAb = '';
  List<PatientComparable> _patients = const [];

  @override
  void dispose() {
    _patient?.dispose();
    _examen?.dispose();
    _ab?.dispose();
    super.dispose();
  }

  /// Les patients comparables ont changé (autre agent, autre jeu) : le sélecteur est reconstruit, la comparaison repart de zéro.
  void _synchroniser(List<PatientComparable> patients) {
    final sig = [for (final p in patients) '${p.id}:${p.mesures.length}'].join('|');
    final avant = [for (final p in _patients) '${p.id}:${p.mesures.length}'].join('|');
    if (_patient != null && sig == avant) return;
    _patients = patients;
    _patient?.dispose();
    _patient = ControleurFormulaire([
      ChampDef(
          nom: 'patient',
          libelle: 'Patient',
          type: TypeChamp.select,
          col: ColChamp.plein,
          indicatif: '— Choisir un patient —',
          options: [for (final p in patients) OptionChamp(p.id, p.libelle)])
    ]);
    _patient!.addListener(_surPatient);
    _vuPatient = '';
    _vuExamen = '';
    _examen?.dispose();
    _examen = null;
    _ab = null;
  }

  void _surPatient() {
    final v = '${_patient!['patient'] ?? ''}';
    if (v == _vuPatient) return;
    _vuPatient = v;
    _vuExamen = '';
    _ab = null;
    _signatureAb = '';
    _examen?.dispose();
    _examen = null;
    if (mounted) setState(() {});
  }

  void _surExamen() {
    final v = '${_examen!['examen'] ?? ''}';
    if (v == _vuExamen) return;
    _vuExamen = v;
    _ab = null;
    _signatureAb = '';
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final p = profilLabo(c,
        fonction: widget.fonction, secteur: widget.secteur, agentId: widget.agentId);
    return ListenableBuilder(
      listenable: ecouteLabo(c),
      builder: (context, _) {
        final actives = c.magasin.collection('demandesAnalyses').actives;
        final rows = comparables(actives, p.session);
        final patients = parPatient(rows);
        _synchroniser(patients);
        final examens = examensLabo(c);
        final masques = actives.where((r) => estRendu(r['etatAnalyse'])).length - rows.length;

        // Le sélecteur d'examen naît du patient choisi.
        PatientComparable? choisi;
        for (final x in patients) {
          if (x.id == _vuPatient) choisi = x;
        }
        List<ExamenComparable> exs = const [];
        if (choisi != null) {
          exs = examensDuPatient(choisi.mesures, examens);
          _examen ??= ControleurFormulaire([
            ChampDef(
                nom: 'examen',
                libelle: 'Examen',
                type: TypeChamp.select,
                col: ColChamp.plein,
                indicatif: '— Choisir un examen —',
                options: [for (final e in exs) OptionChamp(e.code, e.libelle)])
          ])
            ..addListener(_surExamen);
        }

        Widget zone;
        ExamenComparable? ex;
        for (final e in exs) {
          if (e.code == _vuExamen) ex = e;
        }
        if (choisi == null) {
          zone = const VideSigh('Choisir un patient pour ouvrir la comparaison.',
              icone: LucideIcons.gitCompareArrows);
        } else if (_vuExamen.isEmpty || ex == null) {
          zone = VideSigh(
              _vuExamen.isEmpty
                  ? 'Choisir un examen : ceux qui portent plusieurs mesures se comparent.'
                  : 'Choisir un examen.',
              icone: LucideIcons.gitCompareArrows);
        } else if (ex.mesures.length < 2) {
          zone = const VideSigh(
              'Une seule mesure de cet examen : aucune antériorité à comparer. La colonne « Antériorités » se remplira à la prochaine mesure.',
              icone: LucideIcons.history);
        } else {
          zone = _bipanneau(c, ex);
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: LayoutBuilder(builder: (_, k) {
            final deux = k.maxWidth >= 768;
            final l = deux ? (k.maxWidth - 12) / 2 : k.maxWidth;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: l, child: FormulaireSigh(controleur: _patient!)),
              SizedBox(
                  width: l,
                  child: _examen == null
                      ? FormulaireSigh(
                          controleur: ControleurFormulaire(const [
                          ChampDef(
                              nom: 'examen',
                              libelle: 'Examen',
                              type: TypeChamp.select,
                              col: ColChamp.plein,
                              indicatif: '— Choisir un examen —')
                        ]))
                      : FormulaireSigh(controleur: _examen!)),
            ]);
          })),
          const SizedBox(height: 16),
          zone,
          if (masques > 0) ...[
            const SizedBox(height: 16),
            NoteSigh(
                '${nombre(masques)} résultat(s) rendus sont hors de votre périmètre et n’apparaissent pas ici — restriction du RBAC métier, pas donnée manquante.',
                icone: LucideIcons.shieldCheck),
          ],
        ]);
      },
    );
  }

  Widget _bipanneau(ContexteEcran c, ExamenComparable ex) {
    final n = ex.mesures.length;
    final sig = '${ex.code}|$n|$_vuPatient';
    if (_ab == null || _signatureAb != sig) {
      _ab?.dispose();
      final options = [
        for (final (i, r) in ex.mesures.indexed) OptionChamp('$i', libelleMesure(r))
      ];
      _ab = ControleurFormulaire([
        ChampDef(
            nom: 'a',
            libelle: 'Antériorité (colonne gauche)',
            type: TypeChamp.select,
            requis: true,
            options: options),
        ChampDef(
            nom: 'b',
            libelle: 'Mesure comparée (colonne droite)',
            type: TypeChamp.select,
            requis: true,
            options: options),
      ], {
        // Les deux plus récentes par défaut ; l'utilisateur choisit.
        'a': '${n - 2}',
        'b': '${n - 1}',
      });
      _signatureAb = sig;
    }
    final ab = _ab!;
    return ListenableBuilder(
      listenable: ab,
      builder: (context, _) {
        final a = ex.mesures[int.parse('${ab['a']}')];
        final b = ex.mesures[int.parse('${ab['b']}')];
        final variables = [
          for (final v in variablesExamen(ex.code, variablesLabo(c)))
            if (v['actif'] != false) v
        ];
        final lignes = comparer(a, b, variables, plagesLabo(c), unitesLabo(c),
            aujourdhui: c.aujourdhui);
        TableRow ligneEntete() => TableRow(
            decoration: const BoxDecoration(color: JetonsShell.slate50),
            children: [
              for (final (i, t) in [
                'Variable',
                dateFrJs(a['dateHeure']),
                dateFrJs(b['dateHeure']),
                'Évolution',
                'Références'
              ].indexed)
                _cellule(
                    Text(i == 0 || i >= 3 ? t.toUpperCase() : t,
                        style: styleLabo(12,
                            couleur: JetonsShell.slate500, poids: FontWeight.w600)),
                    droite: i > 0)
            ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: LayoutBuilder(builder: (_, k) {
            return SizedBox(
                width: k.maxWidth,
                child: FormulaireSigh(controleur: ab));
          })),
          const SizedBox(height: 16),
          CarteSigh(
              sansRemplissage: true,
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 640),
                      child: Table(
                          key: const Key('res:comparatif'),
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          columnWidths: const {
                            0: FlexColumnWidth(3),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(2),
                            3: FlexColumnWidth(2),
                            4: FlexColumnWidth(2.4),
                          },
                          children: [
                            ligneEntete(),
                            for (final l in lignes)
                              TableRow(
                                  decoration: const BoxDecoration(
                                      border: Border(
                                          top: BorderSide(color: JetonsShell.slate100))),
                                  children: [
                                    _cellule(Padding(
                                        padding: EdgeInsets.only(left: l.enfant ? 16 : 0),
                                        child: Text(l.libelle,
                                            style: styleLabo(14,
                                                couleur: l.enfant
                                                    ? JetonsShell.slate600
                                                    : JetonsShell.slate800,
                                                poids: l.enfant
                                                    ? FontWeight.w400
                                                    : FontWeight.w500)))),
                                    _cellule(
                                        Text(l.valeurA,
                                            style: styleLabo(14,
                                                couleur: l.horsA
                                                    ? JetonsShell.danger700
                                                    : JetonsShell.slate700,
                                                poids: l.horsA
                                                    ? FontWeight.w700
                                                    : FontWeight.w400)),
                                        droite: true),
                                    _cellule(
                                        Text(l.valeurB,
                                            style: styleLabo(14,
                                                couleur: l.horsB
                                                    ? JetonsShell.danger700
                                                    : JetonsShell.slate700,
                                                poids: l.horsB
                                                    ? FontWeight.w700
                                                    : FontWeight.w400)),
                                        droite: true),
                                    _cellule(
                                        l.evolution == null
                                            ? Text('—',
                                                style: styleLabo(12,
                                                    couleur: JetonsShell.slate300))
                                            : Text(l.evolution!,
                                                style: styleLabo(12,
                                                    poids: FontWeight.w500,
                                                    couleur: l.sens == 'hausse'
                                                        ? JetonsShell.danger700
                                                        : (l.sens == 'baisse'
                                                            ? JetonsShell.info700
                                                            : JetonsShell.slate500))),
                                        droite: true),
                                    _cellule(
                                        Text(l.reference,
                                            style: styleLabo(12, couleur: JetonsShell.slate500)),
                                        droite: true),
                                  ]),
                          ])))),
          const SizedBox(height: 16),
          const NoteSigh(
              'L’évolution se lit de gauche à droite. Les valeurs en gras sont hors des références de leur époque : chaque colonne se compare aux bornes du lot de réactif en service à sa date.',
              icone: LucideIcons.gitCompareArrows),
        ]);
      },
    );
  }

  Widget _cellule(Widget w, {bool droite = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Align(alignment: droite ? Alignment.centerRight : Alignment.centerLeft, child: w));
}
