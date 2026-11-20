import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mat_commun.dart';

/// `m4-partogramme` — la PARTOGRAPHIE nationale, dynamique. La ligne d'ALERTE part de 4 cm et monte de 1 cm/h ; la ligne d'ACTION lui est parallèle,
/// décalée de 4 h. Une mesure qui franchit la ligne d'action est SIGNALÉE : le partogramme est un instrument de décision, pas un simple relevé.
/// Les règles (franchissement, séries, clôture à 10 cm) sont dans `mat_regles.dart`, rejouées sur les vecteurs de la maquette.
class EcranPartogramme extends StatefulWidget with EcranMaquette {
  const EcranPartogramme({super.key});
  @override
  String? get titre => 'Partogramme';
  @override
  String? get description => 'Suivi dynamique du travail : dilatation, lignes d’alerte et d’action, BDF, contractions.';
  @override
  String? get regle =>
      'Modèle de la PARTOGRAPHIE nationale (formulaire scanné) : ligne d’alerte de 4 cm à 1 cm/h, ligne d’action décalée de 4 heures. Une dilatation qui franchit la ligne d’action appelle une DÉCISION (codes actions 1 à 7 du formulaire) — le graphique la signale, il ne la prend pas.';
  @override
  List<Widget> actionsEntete(BuildContext context) => const [];

  @override
  State<EcranPartogramme> createState() => _EtatPartogramme();
}

class _EtatPartogramme extends State<EcranPartogramme> {
  String? _courant;
  ControleurFormulaire? _sel;
  String _signature = '';

  Magasin get _m => ContexteEcran.of(context).magasin;
  CollectionMagasin get _col => _m.collection('partogrammes');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _col.addListener(_maj);
    });
  }

  @override
  void dispose() {
    try {
      _col.removeListener(_maj);
    } catch (_) {}
    _sel?.dispose();
    super.dispose();
  }

  void _maj() => setState(() {});

  Fiche? _fiche(List<Fiche> rows) {
    if (rows.isEmpty) return null;
    return rows.where((r) => r['id'] == _courant).firstOrNull ?? rows.first;
  }

  void _ouvrirNouveau(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'patientCode', libelle: 'Parturiente', type: TypeChamp.select, requis: true, options: matOptionsFemmes(c.magasin), col: ColChamp.plein),
      ...matChampsDateHeure('debut', 'Début du suivi (dilatation ≥ 4 cm)'),
      const ChampDef(nom: 'gestite', libelle: 'Gestité', type: TypeChamp.nombre),
      const ChampDef(nom: 'parite', libelle: 'Parité', type: TypeChamp.nombre),
      ChampDef(nom: 'accoucheur', libelle: 'Accoucheur', type: TypeChamp.select, requis: true, options: matSagesFemmes(c.magasin)),
    ]);
    afficherModale<void>(ctx,
        titre: 'Ouvrir un partogramme',
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Ouvrir',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    matRattacher(v, matFemmes(c.magasin));
                    v['reference'] = matReferenceSuivante('PARTO-', _col.toutes);
                    matRecomposerDateHeure(v, 'debut');
                    v['debut'] = DateTime.parse('${v['debut']}').toUtc().toIso8601String();
                    v['gestite'] = matNombreSaisi(v['gestite']);
                    v['parite'] = matNombreSaisi(v['parite']);
                    v['mesures'] = <Object?>[];
                    v['clos'] = false;
                    final r = _col.inserer({'statut': 'actif', ...matSansNuls(v)}, prefixe: 'PAR');
                    fermer();
                    setState(() => _courant = '${r.fiche['id']}');
                    ToastsSigh.afficher(ctx, 'Partogramme ouvert.', type: TypeToast.succes, annuler: () {
                      r.annuler();
                      setState(() => _courant = null);
                    });
                  }),
            ]);
  }

  void _ajouterMesure(BuildContext ctx, Fiche r) {
    final c = ContexteEcran.of(ctx);
    final mesures = (r['mesures'] as List?) ?? const [];
    final prochaine = mesures.isEmpty ? 0 : (matNum((mesures.last as Map)['heure']) ?? 0) + 1;
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'heure', libelle: 'Heure depuis le début (h)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'dilatation', libelle: 'Dilatation cervicale (cm)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'descente', libelle: 'Descente de la présentation (/5)', type: TypeChamp.nombre),
      const ChampDef(nom: 'bdf', libelle: 'BDF (battements/min)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'contractions', libelle: 'Contractions / 10 min', type: TypeChamp.nombre),
      const ChampDef(nom: 'ta', libelle: 'TA maternelle', indicatif: '12/8'),
      const ChampDef(nom: 'pouls', libelle: 'Pouls maternel', type: TypeChamp.nombre),
      ChampDef(
          nom: 'liquide',
          libelle: 'Liquide amniotique',
          type: TypeChamp.select,
          options: [for (final l in (matPartogrammeModele['liquides'] as List)) OptionChamp('${(l as Map)['code']}', '${l['label']}')]),
    ], {
      'heure': matTexteNombre(prochaine)
    });
    afficherModale<void>(ctx,
        titre: 'Mesure — ${r['patient']}',
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    for (final k in const ['heure', 'dilatation', 'descente', 'bdf', 'contractions', 'pouls']) {
                      v[k] = matNombreSaisi(v[k]);
                    }
                    final res = matAjouterMesure(r, matSansNuls(v));
                    _col.mettreAJour(r['id'], {'mesures': res.mesures, 'clos': res.clos, if (res.resume != null) 'resume': res.resume});
                    fermer();
                    setState(() => _courant = '${r['id']}');
                    final apres = _col.parId(r['id'])!;
                    if (matFranchitAction(apres)) {
                      ToastsSigh.afficher(ctx, 'Un partogramme franchit la ligne d’action — une décision est attendue.', type: TypeToast.attention);
                    }
                  }),
            ]);
    c.hashCode;
  }

  void _imprimer(BuildContext ctx, Fiche r) {
    final mesures = [for (final x in ((r['mesures'] as List?) ?? const [])) (x as Map).cast<String, Object?>()];
    matImprimer(ctx,
        titre: 'PARTOGRAPHIE',
        sousTitre: '${r['reference']} — ${r['patient']}',
        cartouche: [
          ('Parturiente', '${r['patient']}'),
          ('Dossier', '${r['patientCode']}'),
          ('Gestité / parité', '${r['gestite'] != null ? matTexteNombre(r['gestite']) : '—'} / ${r['parite'] != null ? matTexteNombre(r['parite']) : '—'}'),
          ('Début du suivi', matDateHeure(r['debut'])),
          ('Accoucheur', '${r['accoucheur'] ?? ''}'),
          ('Résumé', '${r['resume'] ?? 'Travail en cours'}'),
        ],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'Heure (h)', valeur: (m) => matTexteNombre(m['heure']), droite: true),
            ColonneEtat(libelle: 'Dilatation (cm)', valeur: (m) => matTexteNombre(m['dilatation']), droite: true),
            ColonneEtat(libelle: 'Descente (/5)', valeur: (m) => matTexteNombre(m['descente']), droite: true),
            ColonneEtat(libelle: 'BDF', valeur: (m) => matTexteNombre(m['bdf']), droite: true),
            ColonneEtat(libelle: 'CU/10 min', valeur: (m) => matTexteNombre(m['contractions']), droite: true),
            ColonneEtat(libelle: 'TA', valeur: (m) => m['ta'] ?? ''),
            ColonneEtat(libelle: 'Pouls', valeur: (m) => matTexteNombre(m['pouls']), droite: true),
            ColonneEtat(libelle: 'Liquide', valeur: (m) => m['liquide'] ?? ''),
          ], lignes: mesures)),
        ],
        signatures: [Signature('L’Accoucheur', nom: '${r['accoucheur'] ?? ''}', mention: 'Nom, qualification et signature')]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final rows = _col.actives;
    final courant = _fiche(rows);
    _courant = courant == null ? null : '${courant['id']}';
    // le sélecteur « Travail suivi » : reconstruit quand la liste ou le choix change
    final sig = '${rows.map((r) => r['id']).join(',')}|$_courant';
    if (_sel == null || sig != _signature) {
      _sel?.dispose();
      _signature = sig;
      _sel = ControleurFormulaire([
        ChampDef(
            nom: 'travail',
            libelle: 'Travail suivi',
            type: TypeChamp.select,
            options: [for (final r in rows) OptionChamp('${r['id']}', '${r['patient']}')])
      ], {
        'travail': _courant ?? ''
      });
      _sel!.addListener(() {
        final v = '${_sel!['travail'] ?? ''}';
        if (v.isNotEmpty && v != _courant && mounted) setState(() => _courant = v);
      });
    }
    final tabCourant = courant;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Partogrammes', valeur: nombre(rows.length), icone: LucideIcons.activity, ton: TonSigh.navy),
        KpiSigh(libelle: 'Travaux en cours', valeur: nombre(rows.where((r) => r['clos'] != true).length), icone: LucideIcons.timer, ton: TonSigh.attention),
        KpiSigh(libelle: 'Ligne d’action franchie', valeur: nombre(rows.where(matFranchitAction).length), icone: LucideIcons.triangleAlert, ton: TonSigh.danger),
        KpiSigh(libelle: 'Dilatations complètes', valeur: nombre(rows.where((r) => r['clos'] == true).length), icone: LucideIcons.checkCheck, ton: TonSigh.succes),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
        SizedBox(width: 420, child: FormulaireSigh(controleur: _sel!)),
        if (c.droit.editer) BoutonSigh(libelle: 'Ouvrir un partogramme', icone: LucideIcons.plus, onPressed: () => _ouvrirNouveau(context)),
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Ajouter une mesure',
              icone: LucideIcons.activity,
              variante: VarianteBouton.secondaire,
              onPressed: () {
                if (tabCourant != null) _ajouterMesure(context, tabCourant);
              }),
        if (tabCourant != null)
          BoutonSigh(libelle: 'Imprimer', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, tabCourant)),
      ])),
      const SizedBox(height: 16),
      if (tabCourant == null)
        const VideSigh('Aucun partogramme ouvert.', icone: LucideIcons.activity)
      else ...[
        if (matFranchitAction(tabCourant)) ...[
          matNote(
              'La ligne d’ACTION est franchie : la dilatation est en retard de plus de ${matTexteNombre(matModelePartogramme.actionDecalageHeures)} heures sur la ligne d’alerte. Le formulaire national appelle une décision — codes 1 à 7 : ${(matPartogrammeModele['actions'] as List).join(', ')}.',
              ton: TonSigh.danger,
              icone: LucideIcons.siren),
          const SizedBox(height: 16),
        ],
        CarteSigh(titre: 'Dilatation cervicale — ${tabCourant['patient']} (${tabCourant['reference']})', child: _Graphe(tabCourant)),
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Mesures horaires',
            sansRemplissage: true,
            child: MiniTableauSigh(colonnes: [
              ColonneMini('Heure (h)', (m) => matTexteNombre(m['heure'])),
              ColonneMini('Dilatation (cm)', (m) => matTexteNombre(m['dilatation'])),
              ColonneMini('Descente (/5)', (m) => matTexteNombre(m['descente'])),
              ColonneMini('BDF (bpm)', (m) => matTexteNombre(m['bdf'])),
              ColonneMini('CU / 10 min', (m) => matTexteNombre(m['contractions'])),
              ColonneMini('TA', (m) => '${m['ta'] ?? ''}'),
              ColonneMini('Pouls', (m) => matTexteNombre(m['pouls'])),
              ColonneMini('Liquide', (m) => '${m['liquide'] ?? ''}'),
            ], lignes: [
              for (final x in ((tabCourant['mesures'] as List?) ?? const [])) (x as Map).cast<String, Object?>()
            ])),
      ],
    ]);
  }
}

/// Le graphique : dilatation relevée (marine), ligne d'alerte (ambre), ligne d'action (rouge) — des TRAITS sans remplissage, interrompus là où il n'y a
/// pas de mesure (le kit `GraphiqueLigne` n'accepte pas de trou).
class _Graphe extends StatelessWidget {
  const _Graphe(this.p);
  final Fiche p;

  @override
  Widget build(BuildContext context) {
    final s = matSeriesPartogramme(p);
    return Column(children: [
      SizedBox(
          height: 300,
          child: Semantics(
              label:
                  'Graphique en courbes. Dilatation : ${[for (var i = 0; i < s.dilatation.length; i++) if (s.dilatation[i] != null) '${s.etiquettes[i]} ${s.dilatation[i]}'].join(', ')}.',
              child: CustomPaint(size: Size.infinite, painter: _Peintre(s)))),
      const SizedBox(height: 8),
      Wrap(spacing: 16, children: const [
        _Legende('Dilatation', Color(0xFF1E3A5F)),
        _Legende('Ligne d’alerte', Color(0xFFB45309)),
        _Legende('Ligne d’action', Color(0xFFB3261E)),
      ]),
    ]);
  }
}

class _Legende extends StatelessWidget {
  const _Legende(this.t, this.c);
  final String t;
  final Color c;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(color: JetonsShell.slate500, fontSize: 11)),
      ]);
}

class _Peintre extends CustomPainter {
  _Peintre(this.s);
  final ({List<String> etiquettes, List<num> alerte, List<num?> action, List<num?> dilatation}) s;

  @override
  void paint(Canvas c, Size size) {
    const gauche = 32.0, bas = 22.0;
    final z = Rect.fromLTWH(gauche, 8, size.width - gauche - 8, size.height - bas - 8);
    final grille = Paint()..color = const Color(0xFFF1F5F9);
    for (var v = 0; v <= 10; v += 2) {
      final y = z.bottom - z.height * v / 10;
      c.drawLine(Offset(z.left, y), Offset(z.right, y), grille);
      final tp = TextPainter(text: TextSpan(text: '$v', style: const TextStyle(color: JetonsShell.slate400, fontSize: 11)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, Offset(z.left - 8 - tp.width, y - tp.height / 2));
    }
    final n = s.etiquettes.length;
    double x(int i) => n == 1 ? z.center.dx : z.left + z.width * i / (n - 1);
    double y(num v) => z.bottom - z.height * v / 10;
    for (var i = 0; i < n; i += (n > 14 ? 2 : 1)) {
      final tp = TextPainter(text: TextSpan(text: s.etiquettes[i], style: const TextStyle(color: JetonsShell.slate400, fontSize: 11)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, Offset(x(i) - tp.width / 2, z.bottom + 4));
    }
    void trait(List<num?> d, Color col, {bool points = false}) {
      final p = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      Offset? prev;
      for (var i = 0; i < n; i++) {
        final v = d[i];
        if (v == null) {
          prev = null;
          continue;
        }
        final o = Offset(x(i), y(v));
        if (prev != null) c.drawLine(prev, o, p);
        if (points) c.drawCircle(o, 3, Paint()..color = col);
        prev = o;
      }
    }

    trait(s.alerte, const Color(0xFFB45309));
    trait(s.action, const Color(0xFFB3261E));
    trait(s.dilatation, const Color(0xFF1E3A5F), points: true);
  }

  @override
  bool shouldRepaint(_Peintre o) => true;
}
