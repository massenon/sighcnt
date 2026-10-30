/// Sémantique JavaScript reprise À L'IDENTIQUE : la maquette fait foi, y compris dans ses arrondis.
library;

import 'dart:typed_data';

/// `Number(v) || 0` : tout ce qui n'est pas un nombre fini vaut 0.
double nombreOuZero(Object? v) {
  double n;
  if (v is num) {
    n = v.toDouble();
  } else if (v is String) {
    final t = v.trim();
    n = t.isEmpty ? 0 : (double.tryParse(t) ?? double.nan);
  } else if (v is bool) {
    n = v ? 1 : 0;
  } else {
    n = double.nan; // null et undefined
  }
  return n.isFinite ? n : 0;
}

/// `Math.round` : la moitié s'arrondit vers +∞ (−2,5 → −2 ; 2,5 → 3).
double arrondiJs(double x) => (x + 0.5).floorToDouble();

/// `Number.prototype.toFixed` : écriture décimale EXACTE du double, moitié arrondie vers le haut en valeur
/// absolue, signe ajouté après. Calcul en entiers (BigInt) : aucune erreur de représentation.
String toFixedJs(double x, int decimales) {
  if (x.abs() >= 1e21) return x.toString();
  final a = x.abs();
  final bd = ByteData(8)..setFloat64(0, a);
  final haut = bd.getUint32(0);
  final bas = bd.getUint32(4);
  final exp = (haut >> 20) & 0x7ff;
  var mantisse = (BigInt.from(haut & 0xfffff) << 32) | BigInt.from(bas);
  int e;
  if (exp == 0) {
    e = -1074;
  } else {
    mantisse |= BigInt.one << 52;
    e = exp - 1075;
  }
  final echelle = BigInt.from(10).pow(decimales);
  BigInt n;
  if (e >= 0) {
    n = mantisse * BigInt.two.pow(e) * echelle;
  } else {
    final den = BigInt.two.pow(-e);
    final num = mantisse * echelle;
    n = num ~/ den;
    final reste = num - n * den;
    if (reste * BigInt.two >= den) n += BigInt.one;
  }
  var s = n.toString();
  if (decimales > 0) {
    s = s.padLeft(decimales + 1, '0');
    s = '${s.substring(0, s.length - decimales)}.${s.substring(s.length - decimales)}';
  }
  return (x < 0 && n != BigInt.zero ? '-' : '') + s;
}

/// Insertion d'une espace fine insécable tous les trois chiffres : la regex de la maquette, caractère pour
/// caractère — y compris son effet sur la partie décimale (« 1 234.5 678 »), que l'on reproduit sans l'excuser.
final RegExp _groupes = RegExp(r'\B(?=(\d{3})+(?!\d))');
String grouperMilliers(String s) => s.replaceAll(_groupes, ' ');
