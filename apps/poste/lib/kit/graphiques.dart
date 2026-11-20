import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';

/// Palette de la maquette (`charts.js`, CDCT §10.3).
const List<Color> paletteGraphique = [
  JetonsShell.navy900,
  JetonsShell.navy600,
  JetonsShell.navy400,
  JetonsShell.success500,
  JetonsShell.warning500,
  JetonsShell.danger500,
  JetonsShell.navy300,
  JetonsShell.success700,
  JetonsShell.warning700,
  JetonsShell.danger900,
];

class SerieGraphique {
  const SerieGraphique(this.libelle, this.donnees, {this.couleur, this.aire = true});
  final String libelle;
  final List<num> donnees;
  final Color? couleur;

  /// `fill: false` de Chart.js : une courbe sans aire (deux courbes superposées se lisent mieux sans remplissage).
  final bool aire;
}

const double _hautLegende =
    41.2; // 13,2 de texte + 2 × 14 de marge (`legend.labels.padding`)
const double _hautAxeX =
    30.6; // étiquettes 11/13,2 + marge et filet : le total (légende + axe) vaut 71,8 comme Chart.js

TextStyle get _styleTick => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    height: 1.2,
    color: JetonsShell.slate400);

String _num(num v) => nombre(v);

/// Texte alternatif : un graphique n'est pas lisible par un lecteur d'écran, ses valeurs le sont.
String descriptionGraphique(
    String type, List<String> etiquettes, List<SerieGraphique> series) {
  final b = StringBuffer('Graphique $type. ');
  for (final s in series) {
    b.write('${s.libelle} : ');
    b.write([
      for (var i = 0; i < etiquettes.length && i < s.donnees.length; i++)
        '${etiquettes[i]} ${_num(s.donnees[i])}'
    ].join(', '));
    b.write('. ');
  }
  return b.toString().trim();
}

Color couleurDe(SerieGraphique s, int i) =>
    s.couleur ?? paletteGraphique[i % paletteGraphique.length];

/// Légende en bas (`position: bottom`) : pastille ronde de 10 px, texte 11 px slate-500, 14 px de marge.
class LegendeGraphique extends StatelessWidget {
  const LegendeGraphique(
      {super.key, required this.entrees, this.vertical = false});
  final List<(String, Color)> entrees;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    Widget e((String, Color) x) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: x.$2, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(x.$1,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  height: 1.2,
                  color: JetonsShell.slate500)),
        ]);
    return vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                for (final x in entrees)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: e(x))
              ])
        : Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 4,
            children: [for (final x in entrees) e(x)]);
  }
}

class _Cartesien extends StatelessWidget {
  const _Cartesien(
      {required this.type,
      required this.etiquettes,
      required this.series,
      required this.hauteur,
      required this.peintre,
      this.bornes,
      this.empile = false});
  final String type;
  final (double, double)? bornes;

  /// Barres empilées (`stack: true`) : l'échelle suit les TOTAUX par catégorie, non la plus haute série.
  final bool empile;
  final List<String> etiquettes;
  final List<SerieGraphique> series;
  final double hauteur;
  final CustomPainter Function(EchelleVerticale, double gauche) peintre;

  @override
  Widget build(BuildContext context) {
    final traceH = hauteur - _hautLegende - _hautAxeX + 0.0;
    final ech = bornes != null
        ? echelleVerticaleBornee(bornes!.$1, bornes!.$2, hauteurAxe: traceH)
        : echelleVerticale(
            empile
                ? [
                    for (var i = 0; i < etiquettes.length; i++)
                      series.fold<num>(
                          0, (a, s) => a + (i < s.donnees.length ? s.donnees[i] : 0))
                  ]
                : [for (final s in series) ...s.donnees],
            hauteurAxe: traceH - 0);
    final largeurEtiquette = [
      for (final g in ech.graduations)
        (TextPainter(
                text: TextSpan(text: _num(g), style: _styleTick),
                textDirection: TextDirection.ltr)
              ..layout())
            .width
    ].fold<double>(0, math.max);
    return Semantics(
      container: true,
      label: descriptionGraphique(type, etiquettes, series),
      excludeSemantics: true,
      child: SizedBox(
        height: hauteur,
        child: Column(children: [
          Expanded(
              child: CustomPaint(
                  key: Key('graphique:$type'),
                  size: Size.infinite,
                  painter: peintre(ech, largeurEtiquette + 10.5))),
          SizedBox(
              height: _hautLegende,
              child: Center(
                  child: LegendeGraphique(entrees: [
                for (var i = 0; i < series.length; i++)
                  (series[i].libelle, couleurDe(series[i], i))
              ]))),
        ]),
      ),
    );
  }
}

/// `SIGH.charts.barres` : barres arrondies (rayon 4, épaisseur max 38), grille horizontale #f1f5f9, filet d'axe X slate-200.
class GraphiqueBarres extends StatelessWidget {
  const GraphiqueBarres(
      {super.key,
      required this.etiquettes,
      required this.series,
      this.hauteur = 260,
      this.horizontal = false,
      this.empile = false});

  /// `stack: true` (barres verticales) : les séries s'empilent dans une seule barre par catégorie, de la première (en bas) à la dernière.
  final bool empile;

  /// `horizontal: true` (`indexAxis: 'y'`) : une barre par catégorie, épaisseur max 22. Échelle calculée comme l'axe vertical — non rejouée
  /// contre Chart.js pour ce sens (les vecteurs ne couvrent que les barres verticales).
  final bool horizontal;
  final List<String> etiquettes;
  final List<SerieGraphique> series;
  final double hauteur;

  @override
  Widget build(BuildContext context) => horizontal
      ? _BarresH(etiquettes: etiquettes, series: series, hauteur: hauteur)
      : _Cartesien(
          type: 'en barres',
          etiquettes: etiquettes,
          series: series,
          hauteur: hauteur,
          empile: empile,
          peintre: (e, g) => _PeintreBarres(etiquettes, series, e, g, empile));
}

/// `SIGH.charts.ligne` : trait de 2 px, tension 0,35, aire remplie à 13 % (`couleur + '22'`), sans point.
class GraphiqueLigne extends StatelessWidget {
  const GraphiqueLigne(
      {super.key,
      required this.etiquettes,
      required this.series,
      this.hauteur = 260,
      this.min,
      this.max});
  final List<String> etiquettes;
  final List<SerieGraphique> series;
  final double hauteur;

  /// `scales.y: { beginAtZero: false, min, max }` : axe borné (courbe de température 35–41 °C). Absents : l'axe part de zéro.
  final double? min;
  final double? max;

  @override
  Widget build(BuildContext context) => _Cartesien(
      type: 'en courbes',
      bornes: min != null && max != null ? (min!, max!) : null,
      etiquettes: etiquettes,
      series: series,
      hauteur: hauteur,
      peintre: (e, g) => _PeintreLigne(etiquettes, series, e, g));
}

abstract class _Base extends CustomPainter {
  _Base(this.etiquettes, this.series, this.echelle, this.gauche);
  final List<String> etiquettes;
  final List<SerieGraphique> series;
  final EchelleVerticale echelle;
  final double gauche;
  static const double haut = 9.6;

  Rect zone(Size s) =>
      Rect.fromLTRB(gauche, haut, s.width, s.height - _hautAxeX + 0.0 - 0);

  double yDe(Rect z, double v) =>
      z.bottom - (v - echelle.min) / (echelle.max - echelle.min) * z.height;

  void grille(Canvas c, Size s) {
    final z = zone(s);
    final trait = Paint()
      ..color = JetonsShell.slate100
      ..strokeWidth = 1;
    for (final g in echelle.graduations) {
      final y = yDe(z, g);
      c.drawLine(Offset(z.left, y), Offset(z.right, y), trait);
      final tp = TextPainter(
          text: TextSpan(text: _num(g), style: _styleTick),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(z.left - 7.5 - tp.width, y - tp.height / 2));
    }
    c.drawLine(
        Offset(z.left, z.bottom),
        Offset(z.right, z.bottom),
        Paint()
          ..color = JetonsShell.slate200
          ..strokeWidth = 1);
  }

  void etiquettesX(Canvas c, Size s, double Function(int) xDe) {
    final z = zone(s);
    for (var i = 0; i < etiquettes.length; i++) {
      final tp = TextPainter(
          text: TextSpan(text: etiquettes[i], style: _styleTick),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(xDe(i) - tp.width / 2, z.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _Base o) =>
      o.series != series || o.echelle != echelle;
}

class _PeintreBarres extends _Base {
  _PeintreBarres(super.e, super.s, super.ech, super.g, [this.empile = false]);
  final bool empile;

  @override
  void paint(Canvas c, Size s) {
    grille(c, s);
    final z = zone(s);
    final n = etiquettes.length;
    final pas = z.width / n;
    if (empile) {
      // Une barre par catégorie (80 % de sa part, 90 % de cela, 38 px au plus), les séries superposées.
      final epaisseur = math.min(pas * 0.8 * 0.9, 38.0);
      for (var i = 0; i < n; i++) {
        final x = z.left + pas * (i + 0.5) - epaisseur / 2;
        var cumul = 0.0;
        for (var k = 0; k < series.length; k++) {
          final v = i < series[k].donnees.length ? series[k].donnees[i].toDouble() : 0.0;
          if (v <= 0) continue;
          final yHaut = yDe(z, cumul + v), yBas = yDe(z, cumul);
          c.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(x, yHaut, x + epaisseur, yBas),
                  const Radius.circular(4)),
              Paint()..color = couleurDe(series[k], k));
          cumul += v;
        }
      }
      etiquettesX(c, s, (i) => z.left + pas * (i + 0.5));
      return;
    }
    // Chart.js : catégorie à 80 %, barre à 90 % de sa part, épaisseur plafonnée à 38 px.
    final part = pas * 0.8 / series.length;
    final epaisseur = math.min(part * 0.9, 38.0);
    for (var i = 0; i < n; i++) {
      final debut = z.left + pas * i + pas * 0.1;
      for (var k = 0; k < series.length; k++) {
        final v = i < series[k].donnees.length
            ? series[k].donnees[i].toDouble()
            : 0.0;
        final y = yDe(z, v);
        // Chaque barre est centrée dans SA part de la catégorie ; `borderSkipped: false` : les quatre coins sont arrondis.
        final x = debut + part * (k + 0.5) - epaisseur / 2;
        c.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(x, y, x + epaisseur, z.bottom),
                const Radius.circular(4)),
            Paint()..color = couleurDe(series[k], k));
      }
    }
    etiquettesX(c, s, (i) => z.left + pas * (i + 0.5));
  }
}

class _PeintreLigne extends _Base {
  _PeintreLigne(super.e, super.s, super.ech, super.g);

  @override
  void paint(Canvas c, Size s) {
    grille(c, s);
    final z = zone(s);
    final n = etiquettes.length;
    double xDe(int i) => n == 1 ? z.center.dx : z.left + z.width * i / (n - 1);
    // Chart.js place les points d'une ligne sur les bords de la zone (pas au centre des catégories) : étiquettes alignées dessus.
    for (var k = 0; k < series.length; k++) {
      final pts = [
        for (var i = 0; i < n && i < series[k].donnees.length; i++)
          Offset(xDe(i), yDe(z, series[k].donnees[i].toDouble()))
      ];
      if (pts.length < 2) continue;
      final trait = _lisse(pts, 0.35);
      final col = couleurDe(series[k], k);
      if (series[k].aire) {
        final aire = Path.from(trait)
          ..lineTo(pts.last.dx, z.bottom)
          ..lineTo(pts.first.dx, z.bottom)
          ..close();
        c.drawPath(aire, Paint()..color = col.withValues(alpha: 0x22 / 255));
      }
      c.drawPath(
          trait,
          Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round);
    }
    etiquettesX(c, s, xDe);
  }

  /// Courbe de Bézier à tension `t` (interpolation de Chart.js : points de contrôle bornés par les voisins).
  Path _lisse(List<Offset> p, double t) {
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    for (var i = 0; i < p.length - 1; i++) {
      final a = p[i], b = p[i + 1];
      final prev = i > 0 ? p[i - 1] : a, next = i + 2 < p.length ? p[i + 2] : b;
      Offset ctrl(Offset p0, Offset p1, Offset p2, bool apres) {
        final d01 = (p1 - p0).distance, d12 = (p2 - p1).distance;
        final s01 = d01 / (d01 + d12 == 0 ? 1 : d01 + d12), s12 = 1 - s01;
        final fa = t * s01, fb = t * s12;
        final dx = p2.dx - p0.dx, dy = p2.dy - p0.dy;
        return apres
            ? Offset(p1.dx + fb * dx, p1.dy + fb * dy)
            : Offset(p1.dx - fa * dx, p1.dy - fa * dy);
      }

      final c1 = i == 0 ? a : ctrl(prev, a, b, true);
      final c2 = i + 2 >= p.length ? b : ctrl(a, b, next, false);
      // Un point extrême d'un segment ne dépasse jamais ses voisins verticalement : pas de sur-oscillation.
      final y1 =
          c1.dy.clamp(math.min(a.dy, b.dy), math.max(a.dy, b.dy)).toDouble();
      final y2 =
          c2.dy.clamp(math.min(a.dy, b.dy), math.max(a.dy, b.dy)).toDouble();
      path.cubicTo(c1.dx, y1, c2.dx, y2, b.dx, b.dy);
    }
    return path;
  }
}

/// `SIGH.charts.anneau` / `camembert` : cutout 62 % (0 pour le camembert), liseré blanc de 2 px, légende à droite.
class GraphiqueAnneau extends StatelessWidget {
  const GraphiqueAnneau(
      {super.key,
      required this.etiquettes,
      required this.valeurs,
      this.hauteur = 260,
      this.trou = 0.62,
      this.couleurs});
  final List<String> etiquettes;
  final List<num> valeurs;
  final double hauteur;
  final double trou;
  final List<Color>? couleurs;

  List<Color> get _c => couleurs ?? paletteGraphique;

  @override
  Widget build(BuildContext context) {
    final total = valeurs.fold<num>(0, (a, b) => a + b);
    return Semantics(
      container: true,
      label: 'Graphique en ${trou == 0 ? 'camembert' : 'anneau'}. ${[
        for (var i = 0; i < etiquettes.length; i++)
          '${etiquettes[i]} : ${_num(valeurs[i])} (${pourcent(total == 0 ? 0 : valeurs[i] / total * 100)})'
      ].join(', ')}.',
      excludeSemantics: true,
      child: SizedBox(
        height: hauteur,
        child: Row(children: [
          Expanded(
              child: CustomPaint(
                  key: const Key('graphique:anneau'),
                  size: Size.infinite,
                  painter: _PeintreAnneau(valeurs, _c, trou))),
          Padding(
              padding: const EdgeInsets.only(left: 14),
              child: LegendeGraphique(vertical: true, entrees: [
                for (var i = 0; i < etiquettes.length; i++)
                  (etiquettes[i], _c[i % _c.length])
              ])),
        ]),
      ),
    );
  }
}

class _PeintreAnneau extends CustomPainter {
  _PeintreAnneau(this.valeurs, this.couleurs, this.trou);
  final List<num> valeurs;
  final List<Color> couleurs;
  final double trou;

  @override
  void paint(Canvas c, Size s) {
    final total = valeurs.fold<num>(0, (a, b) => a + b).toDouble();
    if (total <= 0) return;
    final rayon = math.min(s.width, s.height) / 2;
    final centre = Offset(s.width / 2, s.height / 2);
    var a = -math.pi / 2;
    for (var i = 0; i < valeurs.length; i++) {
      final bal = valeurs[i] / total * math.pi * 2;
      final chemin = Path()
        ..moveTo(centre.dx + rayon * trou * math.cos(a),
            centre.dy + rayon * trou * math.sin(a));
      chemin.lineTo(
          centre.dx + rayon * math.cos(a), centre.dy + rayon * math.sin(a));
      chemin.arcTo(
          Rect.fromCircle(center: centre, radius: rayon), a, bal, false);
      chemin.arcTo(Rect.fromCircle(center: centre, radius: rayon * trou),
          a + bal, -bal, false);
      chemin.close();
      c.drawPath(chemin, Paint()..color = couleurs[i % couleurs.length]);
      c.drawPath(
          chemin,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      a += bal;
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreAnneau o) => o.valeurs != valeurs;
}

/// `SIGH.charts.sparkline` : 40 px de haut, trait de 2 px, tension 0,4, aire à 9 % (`+ '18'`), sans axe ni légende.
class Sparkline extends StatelessWidget {
  const Sparkline(this.donnees,
      {super.key, this.couleur = JetonsShell.navy900});
  final List<num> donnees;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Tendance : ${donnees.map(_num).join(', ')}',
        excludeSemantics: true,
        child: SizedBox(
            height: 40,
            child: CustomPaint(
                key: const Key('graphique:sparkline'),
                size: Size.infinite,
                painter: _PeintreSparkline(donnees, couleur))),
      );
}

class _PeintreSparkline extends CustomPainter {
  _PeintreSparkline(this.d, this.col);
  final List<num> d;
  final Color col;
  @override
  void paint(Canvas c, Size s) {
    if (d.length < 2) return;
    // Chart.js garde l'échelle d'un sparkline à zéro et l'arrondit comme un axe (0–10 pour des données 3–9) : mesuré sur la maquette.
    final e = echelleVerticale(d, hauteurAxe: s.height);
    final mn = e.min, mx = e.max;
    final plage = mx == mn ? 1 : mx - mn;
    final pts = [
      for (var i = 0; i < d.length; i++)
        Offset(s.width * i / (d.length - 1),
            s.height - (d[i] - mn) / plage * s.height)
    ];
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final dx = (b.dx - a.dx) * 0.4 / 2;
      p.cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
    }
    c.drawPath(
        Path.from(p)
          ..lineTo(pts.last.dx, s.height)
          ..lineTo(pts.first.dx, s.height)
          ..close(),
        Paint()..color = col.withValues(alpha: 0x18 / 255));
    c.drawPath(
        p,
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _PeintreSparkline o) => o.d != d;
}

/// Barres horizontales (`indexAxis: 'y'`) : étiquettes de catégorie à gauche, graduations en bas, barres de 22 px au plus.
class _BarresH extends StatelessWidget {
  const _BarresH(
      {required this.etiquettes, required this.series, required this.hauteur});
  final List<String> etiquettes;
  final List<SerieGraphique> series;
  final double hauteur;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label:
            descriptionGraphique('en barres horizontales', etiquettes, series),
        excludeSemantics: true,
        child: SizedBox(
          height: hauteur,
          child: Column(children: [
            Expanded(child: LayoutBuilder(builder: (context, c) {
              final larg = [
                for (final e in etiquettes)
                  (TextPainter(
                          text: TextSpan(text: e, style: _styleTick),
                          textDirection: TextDirection.ltr)
                        ..layout())
                      .width
              ].fold<double>(0, math.max);
              final gauche = larg + 10.5;
              final valeurs = [for (final s in series) ...s.donnees];
              final largeurAxe = c.maxWidth - gauche - 4;
              // Chart.js mesure TOUTES les graduations générées avant de décider du saut : on génère d'abord sans saut, on mesure, puis on décide.
              final candidates = echelleHorizontale(valeurs,
                      largeurAxe: largeurAxe, largeurEtiquetteMax: 0)
                  .graduations;
              final etiqMax = [
                for (final g in candidates)
                  (TextPainter(
                          text: TextSpan(text: _num(g), style: _styleTick),
                          textDirection: TextDirection.ltr)
                        ..layout())
                      .width
              ].fold<double>(0, math.max);
              final ech = echelleHorizontale(valeurs,
                  largeurAxe: largeurAxe, largeurEtiquetteMax: etiqMax);
              return CustomPaint(
                  key: const Key('graphique:barres-h'),
                  size: Size.infinite,
                  painter: _PeintreBarresH(etiquettes, series, ech, gauche));
            })),
            SizedBox(
                height: _hautLegende,
                child: Center(
                    child: LegendeGraphique(entrees: [
                  for (var i = 0; i < series.length; i++)
                    (series[i].libelle, couleurDe(series[i], i))
                ]))),
          ]),
        ),
      );
}

class _PeintreBarresH extends CustomPainter {
  _PeintreBarresH(this.etiquettes, this.series, this.echelle, this.gauche);
  final List<String> etiquettes;
  final List<SerieGraphique> series;
  final EchelleVerticale echelle;
  final double gauche;

  @override
  void paint(Canvas c, Size s) {
    final z = Rect.fromLTRB(gauche, 0, s.width - 4, s.height - 22);
    double x(double v) =>
        z.left + (v - echelle.min) / (echelle.max - echelle.min) * z.width;
    final trait = Paint()
      ..color = JetonsShell.slate100
      ..strokeWidth = 1;
    for (final g in echelle.graduations) {
      c.drawLine(Offset(x(g), z.top), Offset(x(g), z.bottom), trait);
      final tp = TextPainter(
          text: TextSpan(text: _num(g), style: _styleTick),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(x(g) - tp.width / 2, z.bottom + 6));
    }
    c.drawLine(
        Offset(z.left, z.top),
        Offset(z.left, z.bottom),
        Paint()
          ..color = JetonsShell.slate200
          ..strokeWidth = 1);
    final n = etiquettes.length;
    final pas = z.height / n;
    final part = pas * 0.8 / series.length;
    final ep = math.min(part * 0.9, 22.0);
    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
          text: TextSpan(text: etiquettes[i], style: _styleTick),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(
          c,
          Offset(z.left - 7.5 - tp.width,
              z.top + pas * (i + 0.5) - tp.height / 2));
      for (var k = 0; k < series.length; k++) {
        final v = i < series[k].donnees.length
            ? series[k].donnees[i].toDouble()
            : 0.0;
        final cy = z.top + pas * i + pas * 0.1 + part * (k + 0.5);
        c.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(z.left, cy - ep / 2, x(v), cy + ep / 2),
                const Radius.circular(4)),
            Paint()..color = couleurDe(series[k], k));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreBarresH o) => o.series != series;
}
