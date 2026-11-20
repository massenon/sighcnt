/// COMPARATIF DES RÉSULTATS — le bi-panneau des antériorités (la colonne « Antériorités » de la fiche de résultats), port de l'écran
/// `m5-resultats-comparatif` (m5-laboratoire.js, phase 6) et de `codeExamenDeStatique`. Vecteurs : `test/vecteurs/resultats.json` (`comparatif`).
///
/// Seuls les résultats RENDUS se comparent (comparer une saisie non validée reviendrait à lire par-dessus l'épaule du laboratoire), dans le
/// périmètre du RBAC métier. Chaque colonne se compare aux bornes de SON époque : le lot de réactif en service à sa date.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import 'res_etats.dart';
import 'res_habilitations.dart';
import 'res_plages.dart';

/// `norm` : majuscules, accents ramenés à la lettre de base, tout ce qui n'est pas A-Z ou 0-9 retiré. (Le ç n'est PAS ramené : il est retiré,
/// comme dans la maquette.)
String normExamen(Object? x) {
  var s = (x == null ? '' : '$x').toUpperCase();
  s = s
      .replaceAll(RegExp('[ÉÈÊË]'), 'E')
      .replaceAll(RegExp('[ÀÂÄ]'), 'A')
      .replaceAll(RegExp('[ÎÏ]'), 'I')
      .replaceAll(RegExp('[ÔÖ]'), 'O')
      .replaceAll(RegExp('[ÛÜÙ]'), 'U');
  return s.replaceAll(RegExp('[^A-Z0-9]'), '');
}

/// `codeExamenDeStatique(r)` : le code d'examen d'une demande — par son code, par sa désignation, ou par le début de sa désignation. Les
/// demandes d'avant le modèle structuré nomment l'analyse en clair : sans ce repli elles resteraient inexploitables.
String? codeExamenDe(FicheLabo r, Iterable<FicheLabo> examens) {
  final cible = normExamen(r['analyse']);
  for (final x in examens) {
    final d = normExamen(x['designation']);
    if (x['code'] == r['examenCode'] || d == cible || d.startsWith(cible)) {
      return '${x['code']}';
    }
  }
  return null;
}

FicheLabo? examenParCode(String? code, Iterable<FicheLabo> examens) {
  for (final x in examens) {
    if (x['code'] == code) return x;
  }
  return null;
}

/// `D.toDate` + `C.dateFR` : une date ISO avec fuseau se lit dans l'heure locale du poste.
DateTime? dateLocale(Object? v) {
  if (v == null || '$v'.isEmpty) return null;
  final d = DateTime.tryParse('$v');
  if (d == null) return null;
  return d.isUtc ? d.toLocal() : d;
}

/// `C.dateFR(d)` y compris sur une date illisible (« NaN/NaN/NaN », comme `new Date('')`).
String dateFrJs(Object? v) {
  final d = dateLocale(v);
  return d == null ? 'NaN/NaN/NaN' : dateFR(d);
}

/// Les résultats COMPARABLES : rendus, avec des valeurs, et visibles de cet agent.
List<FicheLabo> comparables(Iterable<FicheLabo> demandesActives, [SessionLabo? session]) =>
    filtrerResultats([
      for (final r in demandesActives)
        if (resultatRendu(r['etatAnalyse']) &&
            r['valeurs'] is Map &&
            (r['valeurs'] as Map).isNotEmpty)
          r
    ], session);

class PatientComparable {
  PatientComparable(this.id, this.patient, this.code, this.mesures);
  final String id;
  final String patient;
  final String code;
  final List<FicheLabo> mesures;

  /// « TEST Alpha (CNT/901/26) — 3 résultat(s) ».
  String get libelle => '$patient ($code) — ${nombre(mesures.length)} résultat(s)';
}

/// Les patients ayant au moins un résultat comparable, dans l'ordre où le registre les présente.
List<PatientComparable> parPatient(Iterable<FicheLabo> rows) {
  final m = <String, List<FicheLabo>>{};
  for (final r in rows) {
    (m['${r['patientId']}'] ??= []).add(r);
  }
  return [
    for (final e in m.entries)
      PatientComparable(e.key, '${e.value.first['patient']}', '${e.value.first['patientCode']}', e.value)
  ];
}

/// Les mesures d'un patient, de la plus ancienne à la plus récente (tri stable sur la date-heure).
List<FicheLabo> mesuresTriees(Iterable<FicheLabo> mesures) {
  final l = [for (var i = 0; i < mesures.length; i++) (i, mesures.elementAt(i))];
  l.sort((a, b) {
    final c = '${a.$2['dateHeure'] ?? ''}'.compareTo('${b.$2['dateHeure'] ?? ''}');
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final x in l) x.$2];
}

class ExamenComparable {
  const ExamenComparable(this.code, this.libelle, this.mesures);
  final String code;
  final String libelle;
  final List<FicheLabo> mesures;
}

/// Les examens d'un patient : « NFS complète (hémogramme) (3 mesures) ».
List<ExamenComparable> examensDuPatient(Iterable<FicheLabo> mesuresDuPatient, Iterable<FicheLabo> examens) {
  final m = <String, List<FicheLabo>>{};
  for (final r in mesuresTriees(mesuresDuPatient)) {
    final code = codeExamenDe(r, examens);
    if (code != null && code.isNotEmpty) (m[code] ??= []).add(r);
  }
  return [
    for (final e in m.entries)
      ExamenComparable(
          e.key,
          '${examenParCode(e.key, examens)?['designation'] ?? e.key} (${e.value.length} mesure${e.value.length > 1 ? 's' : ''})',
          e.value)
  ];
}

/// « 10/06/2026 — 00034-2026 (rectifié v2) ».
String libelleMesure(FicheLabo r) {
  final code = r['codeAnalyse'];
  final ref = (code == null || code == '') ? r['reference'] : code;
  final v = r['version'];
  return '${dateFrJs(r['dateHeure'])} — $ref${r['etatAnalyse'] == 'rectifie' ? ' (rectifié v${(v == null || v == 0) ? 2 : v})' : ''}';
}

/// `symbole(id)` : le symbole d'une unité, lu dans le magasin (`—` si elle est inconnue).
String symboleUnite(Object? id, Iterable<FicheLabo> unites) {
  for (final u in unites) {
    if (u['id'] == id || u['symbole'] == id) return '${u['symbole']}';
  }
  return '—';
}

class LigneComparatif {
  const LigneComparatif(
      {required this.libelle,
      required this.enfant,
      required this.valeurA,
      required this.valeurB,
      required this.horsA,
      required this.horsB,
      required this.evolution,
      required this.sens,
      required this.reference});
  final String libelle;
  final bool enfant;
  final String valeurA;
  final String valeurB;
  final bool horsA;
  final bool horsB;

  /// « ↑ +2.5 G/l » ; `null` quand la variable n'est pas numérique ou qu'une des deux mesures manque.
  final String? evolution;

  /// `hausse` | `baisse` | `egal` | `null`.
  final String? sens;
  final String reference;
}

bool _vide(Object? v) => v == null || v == '';

/// Le tableau de comparaison de deux mesures `a` (antériorité) et `b`, variable par variable. [variablesExamen] : les variables ACTIVES de
/// l'examen, dans l'ordre de rendu ; l'accompagnement (réactif, lot…) n'est jamais comparé.
List<LigneComparatif> comparer(
    FicheLabo a, FicheLabo b, Iterable<FicheLabo> variablesExamen, Iterable<FicheLabo> plagesActives, Iterable<FicheLabo> unites,
    {required DateTime aujourdhui}) {
  final va0 = (a['valeurs'] as Map?)?.cast<String, Object?>() ?? const {};
  final vb0 = (b['valeurs'] as Map?)?.cast<String, Object?>() ?? const {};
  final sortie = <LigneComparatif>[];
  for (final v in variablesExamen) {
    if (v['actif'] == false || (v['accompagnement'] != null && v['accompagnement'] != false)) continue;
    final va = va0[v['code']], vb = vb0[v['code']];
    if (_vide(va) && _vide(vb)) continue;
    final eA = ecart(variableALaDate(v, plagesActives, a['dateHeure'], aujourdhui: aujourdhui), va);
    final eB = ecart(variableALaDate(v, plagesActives, b['dateHeure'], aujourdhui: aujourdhui), vb);
    final u = symboleUnite(v['unite'], unites);
    final suffixe = u == '—' ? '' : ' $u';
    String? evolution;
    String? sens;
    if (v['type'] == 'numerique' && !_vide(va) && !_vide(vb)) {
      final na = double.tryParse('$va'), nb = double.tryParse('$vb');
      if (na != null && nb != null) {
        final delta = nb - na;
        final arrondi = arrondiJs(delta * 100) / 100;
        sens = delta > 0 ? 'hausse' : (delta < 0 ? 'baisse' : 'egal');
        evolution = '${delta > 0 ? '↑ +' : (delta < 0 ? '↓ ' : '= ')}${chaineJs(arrondi)}$suffixe';
      }
    }
    final ref = referenceALaDate(v, plagesActives, b['dateHeure'], aujourdhui: aujourdhui);
    sortie.add(LigneComparatif(
        libelle: '${_vide(v['parent']) ? '' : '↳ '}${v['libelle']}',
        enfant: !_vide(v['parent']),
        valeurA: _vide(va) ? '—' : '${chaineJs(va)}$suffixe',
        valeurB: _vide(vb) ? '—' : '${chaineJs(vb)}$suffixe',
        horsA: eA != null,
        horsB: eB != null,
        evolution: evolution,
        sens: sens,
        reference: ref.isEmpty ? '—' : ref));
  }
  return sortie;
}
