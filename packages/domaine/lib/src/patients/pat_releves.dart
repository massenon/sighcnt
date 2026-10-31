/// M1 — CONSTANTES À L'ACCUEIL, FICHES DE RÉFÉRENCE ET DE CONTRE-RÉFÉRENCE : règles portées de `m1-patients.js`, rejouées sur les vecteurs
/// des écrans réels (`test/vecteurs/pat_constantes.json`, `pat_reference.json`).
library;

import '../format/format_fr.dart';
import '../labo/res_saisie.dart' show agePatient;
import 'pat_patients.dart';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------------------------------------------------------------------------

num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

/// `valeursCalculees(v)` : le patient (identifiant et nom), la tension « sys/dia » et l'IMC. L'IMC est CALCULÉ — le saisir autoriserait une valeur
/// qui ne correspond ni au poids ni à la taille de la même ligne ; il suit aussi la CORRECTION d'un relevé (écart E303).
FichePat patValeursReleve(FichePat saisie, Iterable<FichePat> patients) {
  final code = '${saisie['patientCode'] ?? ''}';
  final pt = patients.where((x) => x['code'] == code).firstOrNull;
  final poids = _num(saisie['poids']);
  final taille = _num(saisie['taille']);
  num? imc;
  if (patVrai(poids) && patVrai(taille)) {
    final brut = poids! / ((taille! / 100) * (taille / 100));
    imc = (brut * 10).roundToDouble() / 10;
  }
  final sys = _num(saisie['tensionSys']);
  final dia = _num(saisie['tensionDia']);
  String texte(num n) => n == n.truncate() ? '${n.truncate()}' : '$n';
  return {
    'patientId': pt?['id'],
    'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : code,
    'tension': (sys != null && dia != null) ? '${texte(sys)}/${texte(dia)}' : null,
    'imc': imc,
  };
}

/// `anormale(r)` : un seuil dépassé se voit. Bornes de la feuille de température de la clinique ; le logiciel signale, il ne diagnostique pas.
List<String> patAnormale(FichePat r) {
  final m = <String>[];
  final t = _num(r['temperature']);
  final p = _num(r['pouls']);
  final fr = _num(r['fr']);
  final s = _num(r['spo2']);
  if (r['temperature'] != null && t != null && (t < 36 || t > 38)) m.add('température');
  if (r['pouls'] != null && p != null && (p < 60 || p > 100)) m.add('pouls');
  if (r['fr'] != null && fr != null && (fr < 12 || fr > 20)) m.add('fréquence respiratoire');
  if (r['spo2'] != null && s != null && s < 94) m.add('SpO₂');
  return m;
}

class PatKpisConstantes {
  const PatKpisConstantes(this.releves, this.aujourdhui, this.patients, this.horsBornes);
  final int releves;
  final int aujourdhui;
  final int patients;
  final int horsBornes;
}

PatKpisConstantes patKpisConstantes(List<FichePat> rows, DateTime maintenant) {
  final jour = iso(maintenant);
  final suivis = <Object?>{};
  for (final r in rows) {
    if (patVrai(r['patientId'])) suivis.add(r['patientId']);
  }
  return PatKpisConstantes(
      rows.length,
      rows.where((r) => '${r['dateHeure'] ?? ''}'.padRight(10).substring(0, 10).trim() == jour).length,
      suivis.length,
      rows.where((r) => patAnormale(r).isNotEmpty).length);
}

const patMoments = {'matin': 'Matin', 'midi': 'Midi', 'soir': 'Soir'};

/// `C.referenceSuivante(prefixe, largeur, fiches)` : le plus grand rang déjà écrit pour ce préfixe, plus un — lu sur les fiches EXISTANTES
/// (archivées comprises), jamais sur un compteur de page (écart E8, retrouvé ici en E306).
String patReferenceSuivante(String prefixe, int largeur, Iterable<String> references) {
  var max = 0;
  for (final r in references) {
    if (r.startsWith(prefixe)) {
      final n = int.tryParse(RegExp(r'^\s*[-+]?\d+').stringMatch(r.substring(prefixe.length)) ?? '') ?? 0;
      if (n > max) max = n;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Fiches de référence
// ---------------------------------------------------------------------------------------------------------------------------------------------

const patSensReference = [
  ('sortante', 'Sortante — la clinique réfère un patient ailleurs'),
  ('entrante', 'Entrante — un patient est adressé à la clinique'),
];
const patMotifsReference = [
  'Absence de médicaments',
  'Absence de moyens de diagnostic',
  'Absence de personnel qualifié',
  'Pas de réponse au traitement',
  'Autre (à préciser)',
];
const patMoyensTransport = [
  'Ambulance',
  'Véhicule administratif',
  'Taxi',
  'Barque motorisée',
  'Moto',
  'Moyen personnel',
  'Autre',
];
const patEvolutions = [
  'Guéri(e)',
  'Évadé(e)',
  'Décédé(e)',
  'Sortie contre avis médical',
  'Référé vers un autre centre',
];

/// Les champs que « Nouvelle fiche de référence » DÉDUIT du patient choisi : numéro, identité, âge (par `C.ageDe`, écart E307), sexe, adresse.
FichePat patDeduitReference(FichePat saisie, Iterable<FichePat> patients, Iterable<FichePat> fiches, DateTime maintenant) {
  final pt = patients.where((x) => x['code'] == saisie['patientCode']).firstOrNull;
  return {
    ...saisie,
    'numero': patReferenceSuivante('REF-', 5, [for (final f in fiches) '${f['numero'] ?? ''}']),
    'patientId': pt?['id'],
    'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : saisie['patientCode'],
    'age': pt != null ? agePatient(pt, maintenant) : null,
    'sexe': pt?['sexe'],
    'adresse': pt?['quartier'],
  };
}

FichePat? patContreReferenceDe(FichePat fiche, Iterable<FichePat> contreReferences) => contreReferences
    .where((c) => c['statut'] != 'archive' && c['numeroReference'] == fiche['numero'])
    .firstOrNull;

class PatKpisReference {
  const PatKpisReference(this.fiches, this.sortantes, this.entrantes, this.sansRetour);
  final int fiches;
  final int sortantes;
  final int entrantes;
  final int sansRetour;
}

/// Les sortantes dont la contre-référence n'est pas revenue (son absence est un indicateur, pas un oubli).
List<FichePat> patSansContreReference(List<FichePat> rows, Iterable<FichePat> contreReferences) {
  final refs = {
    for (final c in contreReferences)
      if (c['statut'] != 'archive') c['numeroReference']
  };
  return [
    for (final r in rows)
      if (r['sens'] == 'sortante' && !refs.contains(r['numero'])) r
  ];
}

PatKpisReference patKpisReference(List<FichePat> rows, Iterable<FichePat> contreReferences) =>
    PatKpisReference(
        rows.length,
        rows.where((r) => r['sens'] == 'sortante').length,
        rows.where((r) => r['sens'] == 'entrante').length,
        patSansContreReference(rows, contreReferences).length);

/// Contre-référence : le patient et la référence viennent de la fiche de référence (le numéro est le seul lien que les deux établissements partagent).
FichePat patDeduitContreReference(FichePat saisie, Iterable<FichePat> fiches, Iterable<FichePat> contreReferences) {
  final ref = fiches
      .where((r) => r['statut'] != 'archive' && r['numero'] == saisie['numeroReference'])
      .firstOrNull;
  return {
    ...saisie,
    'reference': patReferenceSuivante('CRF-', 5, [for (final c in contreReferences) '${c['reference'] ?? ''}']),
    'patientId': ref?['patientId'],
    'patient': ref != null ? ref['patient'] : '—',
    'patientCode': ref?['patientCode'],
  };
}

class PatKpisContreReference {
  const PatKpisContreReference(this.recues, this.concordantes, this.justifiees, this.deces, this.partConcordance, this.partJustifiees);
  final int recues;
  final int concordantes;
  final int justifiees;
  final int deces;

  /// « 50 % des retours » (le pourcentage, écart E306 : la maquette passait une fraction).
  final String? partConcordance;
  final String? partJustifiees;
}

PatKpisContreReference patKpisContreReference(List<FichePat> rows) {
  final c = rows.where((r) => patVrai(r['concordance'])).length;
  final j = rows.where((r) => patVrai(r['justifiee'])).length;
  return PatKpisContreReference(
      rows.length,
      c,
      j,
      rows.where((r) => RegExp('Décédé').hasMatch('${r['evolution'] ?? ''}')).length,
      rows.isNotEmpty ? '${pourcent(c / rows.length * 100)} des retours' : null,
      rows.isNotEmpty ? '${pourcent(j / rows.length * 100)} des retours' : null);
}
