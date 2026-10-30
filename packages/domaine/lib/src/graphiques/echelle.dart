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

/// `hauteurAxe` : hauteur du tracé en pixels (Chart.js limite le nombre de graduations à `⌈hauteur / (11 px × 1,2)⌉`, plafonné à 11).
EchelleVerticale echelleVerticale(Iterable<num> valeurs,
    {required double hauteurAxe, double taillePolice = 11}) {
  var rmax = 0.0;
  for (final v in valeurs) {
    if (v > rmax) rmax = v.toDouble();
  }
  const rmin = 0.0;
  if (rmax == rmin) {
    // Données toutes nulles : Chart.js ajoute une marge d'un pas (max = 1).
    rmax = 1;
  }
  final maxTicks = math.min(11, (hauteurAxe / (taillePolice * 1.2)).ceil());
  final maxEspaces = maxTicks - 1;
  var pas = _joli((rmax - rmin) / maxEspaces);
  var nb = (rmax / pas).ceil() - (rmin / pas).floor();
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
    final v = niceMin + j * pas;
    t.add(double.parse(v.toStringAsFixed(dec)));
  }
  // Saut automatique (`autoSkip`) : la taille d'une graduation est la hauteur d'une ligne (11 × 1,2) + 3 px de marge ; on en garde une sur `saut`.
  final limite = math.max(1, (hauteurAxe / (taillePolice * 1.2 + 3) + 1).floor());
  final saut = (t.length / limite).ceil();
  if (saut <= 1) return EchelleVerticale(t);
  return EchelleVerticale([for (var k = 0; k < t.length; k += saut) t[k]]);
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
