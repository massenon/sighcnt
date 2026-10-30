import 'dart:math' as math;

/// Échelle verticale d'un graphique à barres/lignes, `beginAtZero`, comme Chart.js 4 (`LinearScale` + `generateTicks`, bornes « ticks »).
/// Vérifiée contre les graduations RELEVÉES sur les vrais graphiques de la maquette (`test/vecteurs/echelle.json`).
class EchelleVerticale {
  const EchelleVerticale(this.graduations);
  final List<double> graduations;
  double get min => graduations.first;
  double get max => graduations.last;
}

bool _presque(num a, num b, num eps) => (a - b).abs() <= eps;

double _log10(num x) => math.log(x) / math.ln10;

/// `niceNum` de Chart.js.
double _joli(double plage) {
  final arrondi = plage.roundToDouble();
  final p = _presque(plage, arrondi, plage / 1000) ? arrondi : plage;
  final ordre = math.pow(10, _log10(p).floor()).toDouble();
  final f = p / ordre;
  final fj = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
  return fj * ordre;
}

/// Cœur commun : `longueur` = taille de l'axe, `maxGraduations` = limite de génération de Chart.js, `tailleGraduation` = encombrement d'UNE
/// étiquette le long de l'axe (hauteur de ligne pour l'axe vertical, largeur du plus large libellé pour l'axe horizontal), marge de 3 px comprise.
EchelleVerticale _echelle(Iterable<num> valeurs,
    {required double longueur,
    required int maxGraduations,
    required double Function(int graduations) tailleGraduation}) {
  var rmax = 0.0;
  for (final v in valeurs) {
    if (v > rmax) rmax = v.toDouble();
  }
  const rmin = 0.0;
  // Données toutes nulles : Chart.js ajoute une marge d'un pas (max = 1).
  if (rmax == rmin) rmax = 1;
  final maxTicks = math.min(11, maxGraduations);
  final maxEspaces = maxTicks - 1;
  var pas = _joli((rmax - rmin) / maxEspaces);
  final nb = (rmax / pas).ceil() - (rmin / pas).floor();
  if (nb > maxEspaces) pas = _joli(nb * pas / maxEspaces);
  final niceMin = (rmin / pas).floor() * pas;
  final niceMax = (rmax / pas).ceil() * pas;
  var espaces = (niceMax - niceMin) / pas;
  espaces = _presque(espaces, espaces.roundToDouble(), pas / 1000)
      ? espaces.roundToDouble()
      : espaces.ceilToDouble();
  final t = <double>[];
  final dec = _decimales(pas);
  for (var j = 0; j <= espaces; j++) {
    t.add(double.parse((niceMin + j * pas).toStringAsFixed(dec)));
  }
  // Saut automatique (`autoSkip`) : on garde une graduation sur `saut` pour que les étiquettes ne se chevauchent pas.
  final limite =
      math.max(1, (longueur / tailleGraduation(t.length) + 1).floor());
  final saut = (t.length / limite).ceil();
  if (saut <= 1) return EchelleVerticale(t);
  return EchelleVerticale([for (var k = 0; k < t.length; k += saut) t[k]]);
}

/// Axe VERTICAL : `hauteurAxe` = hauteur du tracé ; Chart.js limite la génération à `⌈hauteur / (11 px × 1,2)⌉`.
EchelleVerticale echelleVerticale(Iterable<num> valeurs,
        {required double hauteurAxe, double taillePolice = 11}) =>
    _echelle(valeurs,
        longueur: hauteurAxe,
        maxGraduations: (hauteurAxe / (taillePolice * 1.2)).ceil(),
        tailleGraduation: (_) => taillePolice * 1.2 + 3);

/// Axe HORIZONTAL (barres horizontales) : la génération est limitée à `⌈largeur / 40⌉`. Chart.js PIVOTE les étiquettes (jusqu'à 50°) avant de
/// les sauter : l'encombrement d'une étiquette est celui de sa boîte pivotée, et c'est lui qui décide du saut automatique.
EchelleVerticale echelleHorizontale(Iterable<num> valeurs,
    {required double largeurAxe,
    required double largeurEtiquetteMax,
    double taillePolice = 11}) {
  final hauteurLigne = taillePolice * 1.2;
  return _echelle(valeurs,
      longueur: largeurAxe,
      maxGraduations: (largeurAxe / 40).ceil(), tailleGraduation: (n) {
    final ww = largeurEtiquetteMax + 3, hh = hauteurLigne + 3;
    final largeurCase = (n > 1 ? largeurAxe / (n - 1) : largeurAxe) - 6;
    var rot = 0.0;
    if (largeurEtiquetteMax + 6 > largeurCase && largeurCase > 0) {
      final r = math.min(
          math.asin(math.min((hauteurLigne + 6) / largeurCase, 1)),
          math.acos(math.min(largeurCase / largeurEtiquetteMax, 1)));
      rot = math.max(0, math.min(50, r * 180 / math.pi));
    }
    final a = rot * math.pi / 180;
    final c = math.cos(a), sn = math.sin(a);
    return hh * c > ww * sn ? ww / c : hh / sn;
  });
}

int _decimales(double pas) {
  var d = 0;
  var x = pas;
  while (d < 10 && (x - x.roundToDouble()).abs() > 1e-9) {
    x *= 10;
    d++;
  }
  return d;
}
