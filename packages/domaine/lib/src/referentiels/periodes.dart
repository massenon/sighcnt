/// Périodicités de la clinique (`core.js`) : journalière, hebdomadaire, mensuelle, trimestrielle, semestrielle,
/// annuelle — plus une plage libre. Les bornes sont des jours CALENDAIRES de l'heure locale.
library;

import '../format/format_fr.dart';
import 'regles.dart';

class Periode {
  const Periode(this.id, this.label, this.jours);
  final String id;
  final String label;
  final int jours;
}

const periodes = [
  Periode('jour', 'Journalière', 1),
  Periode('semaine', 'Hebdomadaire', 7),
  Periode('mois', 'Mensuelle', 30),
  Periode('trimestre', 'Trimestrielle', 91),
  Periode('semestre', 'Semestrielle', 182),
  Periode('annee', 'Annuelle', 365),
];

class Bornes {
  const Bornes(this.debut, this.fin, this.label, this.jours);
  final DateTime debut;
  final DateTime fin;
  final String label;
  final int jours;
}

/// `C.addDays` : décale en jours CALENDAIRES en gardant l'heure locale (pas en tranches de 24 h).
DateTime ajouterJours(DateTime d, int n) => DateTime(
    d.year, d.month, d.day + n, d.hour, d.minute, d.second, d.millisecond);

/// `C.bornes(periodeId, fin)` — une période inconnue retombe sur la journée.
Bornes bornes(String periodeId, DateTime fin) {
  final p = periodes.firstWhere((x) => x.id == periodeId,
      orElse: () => periodes.first);
  return Bornes(ajouterJours(fin, -(p.jours - 1)), fin, p.label, p.jours);
}

/// `C.bornesLibres(du, au)` — remises dans l'ordre si l'agent les a inversées.
Bornes bornesLibres(DateTime du, DateTime au) {
  var a = du;
  var b = au;
  if (a.millisecondsSinceEpoch > b.millisecondsSinceEpoch) {
    final t = a;
    a = b;
    b = t;
  }
  return Bornes(a, b, 'Plage libre', joursEntre(a, b) + 1);
}

/// `C.dansBornes(date, b)` — les deux extrémités sont incluses.
bool dansBornes(DateTime date, Bornes b) =>
    date.millisecondsSinceEpoch >= b.debut.millisecondsSinceEpoch &&
    date.millisecondsSinceEpoch <= b.fin.millisecondsSinceEpoch;

/// `C.libellePeriode(b)` — c'est lui qui coiffe les états imprimés.
String libellePeriode(Bornes b) => b.jours == 1
    ? 'Journée du ${dateFR(b.debut)}'
    : 'Du ${dateFR(b.debut)} au ${dateFR(b.fin)}';
