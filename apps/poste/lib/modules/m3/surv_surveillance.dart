import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'surv_commun.dart';

/// `m3-surveillance` — « Fiche de surveillance » : le relevé horodaté des constantes et la COURBE À CINQ ÉCHELLES (TA, pouls, température, FR, diurèse)
/// sur sept dates à trois moments. La feuille de température et cette fiche sont deux présentations d'UNE donnée : les relevés viennent de l'accueil
/// (`constantes`) et du lit du patient (`releves`). L'échelle du pouls n'est pas linéaire (interpolation entre graduations) et une mesure ABSENTE
/// n'est pas tracée à zéro (E365). Règles : `hosRelevesDe`, `hosCourbe`, `hosPositionSurEchelle` (packages/domaine).
class EcranSurveillance extends StatefulWidget with EcranMaquette {
  const EcranSurveillance({super.key});

  @override
  String get titre => 'Fiche de surveillance';

  @override
  String get description => 'Relevé horodaté des constantes et courbe de surveillance à cinq échelles.';

  @override
  String get regle =>
      'La feuille de température et la fiche de surveillance sont deux présentations d’une même donnée : une seule collection les alimente, sans quoi un même patient aurait deux séries de constantes divergentes. L’échelle du pouls n’est pas linéaire — elle est tracée telle que le document la porte.';

  @override
  State<EcranSurveillance> createState() => _EtatSurveillance();
}

class _EtatSurveillance extends State<EcranSurveillance> {
  ControleurFormulaire? _choix;
  String _liste = '';

  @override
  void dispose() {
    _choix?.dispose();
    super.dispose();
  }

  /// Les patients suivis viennent des DEUX sources : un hospitalisé dont les constantes sont relevées au lit doit apparaître même si personne ne l'a
  /// mesuré à l'accueil.
  static List<Fiche> patientsSuivis(Magasin m) {
    final ids = <Object?>{};
    for (final c in m.collection('constantes').actives) {
      if (vrai(c['patientId'])) ids.add(c['patientId']);
    }
    final parAdmission = {for (final a in m.collection('admissions').actives) a['id']: a['patientId']};
    for (final r in m.collection('releves').actives) {
      final pid = parAdmission[r['admissionId']];
      if (pid != null) ids.add(pid);
    }
    return m.collection('patients').actives.where((p) => ids.contains(p['id'])).toList();
  }

  static List<Fiche> relevesDe(Magasin m, Object? patientId) => hosRelevesDe('$patientId',
      constantes: m.collection('constantes').actives,
      admissions: m.collection('admissions').actives,
      releves: m.collection('releves').actives);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
      listenable: Listenable.merge(
          [m.collection('constantes'), m.collection('releves'), m.collection('admissions'), m.collection('patients')]),
      builder: (context, _) {
        final pts = patientsSuivis(m);
        if (pts.isEmpty) {
          return CarteSigh(
              child: VideSigh('Aucune constante relevée.',
                  indice: 'Les constantes se saisissent à l’accueil ou au lit du patient ; elles alimentent cette fiche.',
                  icone: LucideIcons.thermometer,
                  action: BoutonSigh(
                      libelle: 'Relever des constantes',
                      icone: LucideIcons.plus,
                      onPressed: () => c.aller('m1-constantes'))));
        }
        // la liste des patients suivis a changé : le sélecteur repart du premier, comme la maquette qui rebâtit sa vue
        final liste = pts.map((p) => p['id']).join('|');
        if (_choix == null || liste != _liste) {
          _choix?.dispose();
          _liste = liste;
          _choix = champUnique(
              ChampDef(
                  nom: 'patient',
                  libelle: '',
                  type: TypeChamp.select,
                  col: ColChamp.plein,
                  options: [
                    for (final p in pts) OptionChamp('${p['id']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
                  ]),
              '${pts.first['id']}')
            ..addListener(() {
              if (mounted) setState(() {});
            });
        }
        final tous = [for (final p in pts) ...relevesDe(m, p['id'])];
        final auj = iso(c.aujourdhui);
        final patient = pts.firstWhere((p) => '${p['id']}' == '${_choix!['patient']}', orElse: () => pts.first);
        final rel = relevesDe(m, patient['id']);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Patients suivis', valeur: nombre(pts.length), icone: LucideIcons.users, ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Relevés enregistrés',
                valeur: nombre(tous.length),
                icone: LucideIcons.activity,
                ton: TonSigh.info,
                indice: 'accueil et lit du patient réunis'),
            KpiSigh(
                libelle: 'Relevés du jour',
                valeur: nombre(tous.where((r) => r['date'] == auj).length),
                icone: LucideIcons.calendar,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Échelles suivies',
                valeur: nombre(hosEchelles.length),
                icone: LucideIcons.chartLine,
                ton: TonSigh.neutre,
                indice: 'TA, pouls, température, FR, diurèse'),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Patient suivi',
              child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Sélectionner un patient',
                    style: TextStyle(color: Color(0xFF475569), fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
                commande(_choix!, largeur: 360),
              ])),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Feuille de température — ${patient['nom']} ${patient['prenom']}',
              child: _Courbe(rel)),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Relevés horodatés',
              sansRemplissage: true,
              child: TableauSigh(
                lignes: rel.reversed.toList(),
                nomExport: 'releves',
                messageVide: 'Aucun relevé pour ce patient.',
                colonnes: [
                  ColonneTableau(cle: 'date', libelle: 'Date', texte: (r) => dateTexte(r['date'])),
                  const ColonneTableau(cle: 'heure', libelle: 'Heure'),
                  ColonneTableau(
                      cle: 'moment',
                      libelle: 'Moment',
                      texte: (r) => hosMoments.where((x) => x.$1 == r['moment']).map((x) => x.$3).firstOrNull ?? '—'),
                  ColonneTableau(
                      cle: 'temperature',
                      libelle: 'Température',
                      droite: true,
                      texte: (r) => r['temperature'] == null ? '—' : '${_n(r['temperature'])} °C'),
                  ColonneTableau(
                      cle: 'tension',
                      libelle: 'TA',
                      droite: true,
                      texte: (r) => vrai(r['tension']) ? '${r['tension']}' : '—'),
                  ColonneTableau(cle: 'fr', libelle: 'FR', droite: true, texte: (r) => r['fr'] == null ? '—' : _n(r['fr'])),
                  ColonneTableau(
                      cle: 'pouls', libelle: 'Pouls', droite: true, texte: (r) => r['pouls'] == null ? '—' : _n(r['pouls'])),
                  ColonneTableau(
                      cle: 'diurese',
                      libelle: 'Diurèse',
                      droite: true,
                      texte: (r) => r['diurese'] == null ? '—' : '${_n(r['diurese'])} L'),
                  const ColonneTableau(cle: 'par', libelle: 'Relevé par'),
                  ColonneTableau(
                      cle: 'origine',
                      libelle: 'Source',
                      texte: (r) => '${r['origine']}',
                      rendu: (_, r) =>
                          BadgeSigh('${r['origine']}', ton: r['origine'] == 'Accueil' ? TonSigh.info : TonSigh.neutre)),
                ],
              )),
        ]);
      },
    );
  }

  /// Un nombre comme JavaScript l'écrit (`3.5`, `3`).
  static String _n(Object? v) => v is num ? hosNum(v) : '$v';
}

/// La courbe à cinq échelles, telle que la feuille papier la porte : sept dates, trois moments par date, six lignes de grille partagées, une polyligne
/// par échelle. Tout le calcul est au domaine (`hosCourbe`) ; ce widget ne fait que le dessiner.
class _Courbe extends StatelessWidget {
  const _Courbe(this.releves);
  final List<Fiche> releves;

  @override
  Widget build(BuildContext context) {
    final courbe = hosCourbe(releves);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CustomPaint(
              key: const Key('m3:courbe'),
              size: Size(courbe.largeurTotale, courbe.hauteurTotale),
              painter: PeintreCourbe(courbe))),
      const SizedBox(height: 12),
      Wrap(spacing: 16, runSpacing: 4, children: [
        for (final e in hosEchelles)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 16,
                height: 8,
                decoration: BoxDecoration(color: _couleur(e.couleur), borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 6),
            Text('${e.label} (${e.unite}) — ${hosNum(e.graduations.first)} à ${hosNum(e.graduations.last)}',
                style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 16 / 12)),
          ]),
      ]),
      const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              'M = matin · Mi = midi · S = soir. Les cinq échelles partagent six lignes de grille, comme sur la feuille papier. L’échelle du pouls n’est pas linéaire : le dernier intervalle (140 → 180) vaut le double des précédents, et il est tracé comme tel.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 16 / 12))),
    ]);
  }
}

Color _couleur(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

/// Dessin de la maquette (`courbe()` de `m3-hospitalisation.js`) : mêmes coordonnées, mêmes traits, mêmes corps de texte.
class PeintreCourbe extends CustomPainter {
  PeintreCourbe(this.courbe);
  final HosCourbe courbe;

  void _texte(Canvas c, String t, double x, double y, double taille, Color couleur, {bool centre = false}) {
    final p = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontSize: taille, color: couleur)),
        textDirection: TextDirection.ltr)
      ..layout();
    // SVG : `y` est la ligne de base du texte.
    p.paint(c, Offset(centre ? x - p.width / 2 : x, y - p.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const h = HosCourbe.h, l = HosCourbe.l;
    final largeur = courbe.largeurTotale - l - 12;
    final n = courbe.colonnes.length;
    final pas = largeur / (n < 1 ? 1 : n);
    Paint trait(Color c, [double w = 1]) => Paint()
      ..color = c
      ..strokeWidth = w
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      final y = h - (i / 5) * h;
      canvas.drawLine(Offset(l, y), Offset(l + largeur, y), trait(const Color(0xFFE2E8F0)));
      _texte(canvas, courbe.graduations[i], 2, y + 3, 7, const Color(0xFF94A3B8));
    }
    for (var k = 0; k < n; k++) {
      final x = l + k * pas + pas / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, h),
          trait(k % 3 == 0 ? const Color(0xFFCBD5E1) : const Color(0xFFF1F5F9)));
      final moment = hosMoments.firstWhere((m) => m.$1 == courbe.colonnes[k].$2);
      _texte(canvas, moment.$2, x, h + 12, 7, const Color(0xFF64748B), centre: true);
      if (k % 3 == 1) {
        final d = dateTexte(courbe.colonnes[k].$1);
        _texte(canvas, d.length >= 5 ? d.substring(0, 5) : d, x, h + 24, 7, const Color(0xFF334155), centre: true);
      }
    }
    for (final e in hosEchelles) {
      final pts = courbe.polylignes[e.code] ?? const <HosPoint>[];
      final couleur = _couleur(e.couleur);
      if (pts.length > 1) {
        final chemin = Path()..moveTo(pts.first.x, pts.first.y);
        for (final p in pts.skip(1)) {
          chemin.lineTo(p.x, p.y);
        }
        canvas.drawPath(chemin, trait(couleur, 1.6));
      }
      for (final p in pts) {
        canvas.drawCircle(Offset(p.x, p.y), 2.4, Paint()..color = couleur);
      }
    }
  }

  @override
  bool shouldRepaint(PeintreCourbe o) => o.courbe != courbe;
}
