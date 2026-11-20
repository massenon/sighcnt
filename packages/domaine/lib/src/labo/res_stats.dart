/// STATISTIQUES DU LABORATOIRE — port de l'écran `m5-stats` (m5-laboratoire.js, vague 23). Vecteurs : `test/vecteurs/resultats.json` (`stats`).
///
/// « Pouvoir ressortir les statistiques des examens réalisés en fonction des services, de l'âge, du sexe, période, interne ou externe. » —
/// les cinq axes sont demandés nommément. Chaque axe est un FILTRE : compteurs, graphiques et tableau se recalculent sur la population filtrée.
/// Le comptage porte sur les demandes ENREGISTRÉES, qu'elles soient rendues ou en cours. TOUT est calculé, rien n'est fourni.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../referentiels/regles.dart' show joursEntre;
import 'res_comparatif.dart';
import 'res_habilitations.dart';

class PeriodeLabo {
  const PeriodeLabo(this.id, this.label, this.jours);
  final String id;
  final String label;
  final int? jours;
}

const List<PeriodeLabo> periodesLabo = [
  PeriodeLabo('semaine', 'Semaine', 7),
  PeriodeLabo('mois', 'Mois', 30),
  PeriodeLabo('trimestre', 'Trimestre', 91),
  PeriodeLabo('semestre', 'Semestre', 182),
  PeriodeLabo('annee', 'Année', 365),
  PeriodeLabo('libre', 'Plage libre', null),
];

class TrancheAge {
  const TrancheAge(this.id, this.label, this.min, this.max);
  final String id;
  final String label;
  final int min;
  final int max;
}

const List<TrancheAge> tranchesAge = [
  TrancheAge('0-5', '0 – 5 ans', 0, 5),
  TrancheAge('6-15', '6 – 15 ans', 6, 15),
  TrancheAge('16-25', '16 – 25 ans', 16, 25),
  TrancheAge('26-45', '26 – 45 ans', 26, 45),
  TrancheAge('46-65', '46 – 65 ans', 46, 65),
  TrancheAge('66+', '66 ans et plus', 66, 200),
];

/// `L.SECTIONS` — les six sections du bulletin (identifiant, libellé).
const List<(String, String)> sectionsLabo = [
  ('hematologie', 'Hématologie'),
  ('serologie', 'Sérologie'),
  ('parasitologie', 'Parasitologie'),
  ('biochimie', 'Biochimie'),
  ('bacteriologie', 'Bactériologie'),
  ('hormonologie', 'Hormonologie'),
];

/// `L.SERVICES_DEMANDEURS` — (identifiant, libellé).
const List<(String, String)> servicesDemandeursLabo = [
  ('maternite', 'Maternité'),
  ('medecine', 'Médecine'),
  ('specialite', 'Médecine et spécialité'),
];

/// `L.ORIGINES_PATIENT` — (identifiant, libellé).
const List<(String, String)> originesPatient = [
  ('interne', 'Patient interne'),
  ('externe', 'Patient externe'),
];

/// `L.section(id)` : le libellé d'une section (l'identifiant lui-même s'il est inconnu).
String libelleSection(String id) {
  for (final s in sectionsLabo) {
    if (s.$1 == id) return s.$2;
  }
  return id;
}

/// `C.age(naissance)` : années révolues (`floor(jours/365,25)`), jamais négatives ; `null` si la date manque ou est illisible.
int? ageAnnees(Object? naissance, DateTime maintenant) {
  if (naissance == null || naissance == '') return null;
  final d = DateTime.tryParse('$naissance');
  if (d == null) return null;
  final nais = d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  final jours = joursEntre(nais, maintenant.toUtc());
  final a = (jours / 365.25).floor();
  return a < 0 ? 0 : a;
}

/// `trancheAge(patient)` → le libellé de la tranche, ou « Non renseigné ».
String trancheAgeLabel(FicheLabo? patient, DateTime maintenant) {
  if (patient == null || patient['dateNaissance'] == null || patient['dateNaissance'] == '') {
    return 'Non renseigné';
  }
  final a = ageAnnees(patient['dateNaissance'], maintenant);
  if (a == null) return 'Non renseigné';
  for (final t in tranchesAge) {
    if (a >= t.min && a <= t.max) return t.label;
  }
  return 'Non renseigné';
}

/// `appliquerPeriode()` : les bornes d'une périodicité qui se termine [aujourdhui] ; `null` pour la plage libre (les bornes restent celles saisies).
({String du, String au})? bornesPeriodeLabo(String id, DateTime aujourdhui) {
  final p = periodesLabo.firstWhere((x) => x.id == id, orElse: () => periodesLabo.last);
  if (p.jours == null) return null;
  final fin = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  final debut = DateTime(fin.year, fin.month, fin.day - p.jours! + 1);
  return (du: iso(debut), au: iso(fin));
}

class FiltresStatsLabo {
  const FiltresStatsLabo(
      {this.du = '', this.au = '', this.section = '', this.service = '', this.origine = '', this.sexe = ''});
  final String du;
  final String au;
  final String section;
  final String service;
  final String origine;
  final String sexe;

  FiltresStatsLabo avec({String? du, String? au, String? section, String? service, String? origine, String? sexe}) =>
      FiltresStatsLabo(
          du: du ?? this.du,
          au: au ?? this.au,
          section: section ?? this.section,
          service: service ?? this.service,
          origine: origine ?? this.origine,
          sexe: sexe ?? this.sexe);
}

bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

String _jour(FicheLabo r) {
  final brut = _vrai(r['dateHeure']) ? '${r['dateHeure']}' : (_vrai(r['date']) ? '${r['date']}' : '');
  return brut.length > 10 ? brut.substring(0, 10) : brut;
}

class LigneExamenStats {
  const LigneExamenStats(this.examen, this.section, this.total, this.rendus, this.urgents, this.externes);
  final String examen;
  final String section;
  final int total;
  final int rendus;
  final int urgents;
  final int externes;
}

class StatsLabo {
  const StatsLabo({
    required this.lignes,
    required this.demandes,
    required this.rendus,
    required this.urgents,
    required this.patientsDistincts,
    required this.topExamens,
    required this.parSection,
    required this.parService,
    required this.parOrigine,
    required this.parSexe,
    required this.parAge,
    required this.parJour,
    required this.detail,
  });
  final List<FicheLabo> lignes;
  final int demandes;

  /// Seul `valide` compte ici — un résultat RECTIFIÉ n'est pas dénombré (porté fidèlement : écart E161).
  final int rendus;
  final int urgents;
  final int patientsDistincts;

  /// Les 12 examens les plus demandés (libellé, nombre).
  final List<(String, int)> topExamens;
  final List<(String, int)> parSection;
  final List<(String, int)> parService;
  final List<(String, int)> parOrigine;
  final List<(String, int)> parSexe;

  /// Une valeur par tranche d'âge, dans l'ordre des tranches.
  final List<int> parAge;

  /// Les jours (ISO) triés, avec leur nombre d'examens.
  final List<(String, int)> parJour;
  final List<LigneExamenStats> detail;

  /// « 67 % du volume » ; `null` quand rien n'est demandé.
  String? get indiceRendus =>
      demandes == 0 ? null : '${arrondiJs(rendus / demandes * 100).toInt()} % du volume';
}

/// Les lignes retenues par les filtres (`lignes()` de l'écran). Les bornes de dates comparent les 10 premiers caractères ; une demande SANS
/// date n'est écartée par aucune borne.
List<FicheLabo> lignesStats(Iterable<FicheLabo> demandesActives, Iterable<FicheLabo> patientsActifs,
    FiltresStatsLabo f, Iterable<FicheLabo> examens) {
  final pats = {for (final p in patientsActifs.toList().reversed) '${p['id']}': p};
  FicheLabo? patientDe(FicheLabo r) => pats['${r['patientId']}'];
  return [
    for (final r in demandesActives)
      if (_garde(r, f, examens, patientDe)) r
  ];
}

bool _garde(FicheLabo r, FiltresStatsLabo f, Iterable<FicheLabo> examens, FicheLabo? Function(FicheLabo) patientDe) {
  final d = _jour(r);
  if (f.du.isNotEmpty && d.isNotEmpty && d.compareTo(f.du) < 0) return false;
  if (f.au.isNotEmpty && d.isNotEmpty && d.compareTo(f.au) > 0) return false;
  if (f.section.isNotEmpty) {
    final code = codeExamenDe(r, examens);
    final ex = code == null ? null : examenParCode(code, examens);
    if (ex == null || ex['section'] != f.section) return false;
  }
  if (f.service.isNotEmpty && (_vrai(r['serviceDemandeur']) ? '${r['serviceDemandeur']}' : '') != f.service) {
    return false;
  }
  if (f.origine.isNotEmpty && (_vrai(r['origineDemande']) ? '${r['origineDemande']}' : 'interne') != f.origine) {
    return false;
  }
  if (f.sexe.isNotEmpty) {
    final p = patientDe(r);
    if (p == null || p['sexe'] != f.sexe) return false;
  }
  return true;
}

/// Regroupement qui garde l'ordre de PREMIÈRE rencontre (`C.groupBy`).
Map<String, List<FicheLabo>> _grouper(Iterable<FicheLabo> rows, String Function(FicheLabo) cle) {
  final m = <String, List<FicheLabo>>{};
  for (final r in rows) {
    (m[cle(r)] ??= []).add(r);
  }
  return m;
}

List<(String, int)> _compter(Map<String, List<FicheLabo>> m) => [for (final e in m.entries) (e.key, e.value.length)];

/// Tri décroissant STABLE sur le nombre.
List<T> _trierDesc<T>(List<T> l, int Function(T) n) {
  final idx = [for (var i = 0; i < l.length; i++) (i, l[i])];
  idx.sort((a, b) {
    final c = n(b.$2).compareTo(n(a.$2));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final x in idx) x.$2];
}

/// Le tableau de bord statistique de la population filtrée.
StatsLabo calculerStatsLabo(List<FicheLabo> rows, Iterable<FicheLabo> patientsActifs, Iterable<FicheLabo> examens,
    {required DateTime maintenant}) {
  final pats = {for (final p in patientsActifs.toList().reversed) '${p['id']}': p};
  FicheLabo? patientDe(FicheLabo r) => pats['${r['patientId']}'];

  final rendus = rows.where((r) => r['etatAnalyse'] == 'valide').length;
  final urgents = rows.where((r) => _vrai(r['urgent'])).length;
  final distincts = {for (final r in rows) '${r['patientId']}'}.length;

  final parExamen = _grouper(rows, (r) => '${r['analyse']}');
  final top = _trierDesc([for (final e in parExamen.entries) (e.key, e.value.length)], (x) => x.$2).take(12).toList();

  String sectionDe(FicheLabo r) {
    final code = codeExamenDe(r, examens);
    final ex = code == null ? null : examenParCode(code, examens);
    return ex != null ? libelleSection('${ex['section']}') : 'Non classé';
  }

  final parSection = _grouper(rows, sectionDe);
  final parService = _grouper(rows, (r) => _vrai(r['serviceDemandeur']) ? '${r['serviceDemandeur']}' : 'Non renseigné');
  final parOrigine = _grouper(rows, (r) => (_vrai(r['origineDemande']) ? '${r['origineDemande']}' : 'interne') == 'externe' ? 'Patient externe' : 'Patient interne');
  final parSexe = _grouper(rows, (r) {
    final p = patientDe(r);
    return p != null ? (p['sexe'] == 'F' ? 'Féminin' : 'Masculin') : 'Non renseigné';
  });
  final parAge = _grouper(rows, (r) => trancheAgeLabel(patientDe(r), maintenant));
  final parJour = _grouper(rows, _jour);
  final jours = parJour.keys.where((j) => j.isNotEmpty).toList()..sort();

  final detail = _trierDesc([
    for (final e in parExamen.entries)
      () {
        final v = e.value;
        final code = codeExamenDe(v.first, examens);
        final ex = code == null ? null : examenParCode(code, examens);
        return LigneExamenStats(
            e.key,
            ex != null ? libelleSection('${ex['section']}') : 'Non classé',
            v.length,
            v.where((x) => x['etatAnalyse'] == 'valide').length,
            v.where((x) => _vrai(x['urgent'])).length,
            v.where((x) => x['origineDemande'] == 'externe').length);
      }()
  ], (x) => x.total);

  return StatsLabo(
      lignes: rows,
      demandes: rows.length,
      rendus: rendus,
      urgents: urgents,
      patientsDistincts: distincts,
      topExamens: top,
      parSection: _compter(parSection),
      parService: _compter(parService),
      parOrigine: _compter(parOrigine),
      parSexe: _compter(parSexe),
      parAge: [for (final t in tranchesAge) (parAge[t.label] ?? const []).length],
      parJour: [for (final j in jours) (j, parJour[j]!.length)],
      detail: detail);
}
