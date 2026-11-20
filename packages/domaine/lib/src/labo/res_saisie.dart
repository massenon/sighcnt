/// Briques de la SAISIE d'un résultat (m5-resultats) : le code d'examen d'une demande, l'âge du patient tel qu'il s'écrit sur une pièce,
/// le résumé textuel d'un résultat structuré et les variables à renseigner.
library;

import '../referentiels/regles.dart' show joursEntre;
import 'res_comparatif.dart';
import 'res_habilitations.dart';
import 'res_plages.dart';
import 'res_stats.dart';

/// `codeExamenDe(r)` de l'écran de SAISIE — distinct de `codeExamenDe` du comparatif : le code d'abord (`examenCode` OU `analyseCode`, sur TOUT
/// le catalogue), puis la désignation, puis un code d'examen contenu en tête de la désignation de la demande.
String? codeExamenSaisie(FicheLabo r, Iterable<FicheLabo> examens) {
  for (final e in examens) {
    if (e['code'] == r['examenCode'] || e['code'] == r['analyseCode']) return '${e['code']}';
  }
  final cible = normExamen(r['analyse']);
  for (final e in examens) {
    final d = normExamen(e['designation']);
    if (d == cible || d.startsWith(cible) || cible.startsWith(normExamen(e['code']))) {
      return '${e['code']}';
    }
  }
  return null;
}

/// `L.MOTIFS_COMMENTAIRE_GENERAL` : le commentaire GÉNÉRAL porte sur l'échantillon et le compte rendu (« hémolysé, reprendre le prélèvement »),
/// non sur l'interprétation d'un examen.
const List<String> motifsCommentaireGeneral = [
  'Échantillon hémolysé — reprendre le prélèvement.',
  'Échantillon coagulé — reprendre le prélèvement.',
  'Quantité insuffisante pour la totalité des examens demandés.',
  'Échantillon parvenu hors délai de conservation.',
  'Examen non réalisé — réactif indisponible.',
  'Examen à confirmer sur un second prélèvement.',
  'Résultat rendu par téléphone au prescripteur.',
];

/// Les issues imposées par le TYPE de la variable (`L.TYPES_VARIABLE[].valeurs`) ; une variable de type `liste` porte les siennes.
const Map<String, List<String>> valeursTypeVariable = {
  'binaire': ['Positif', 'Négatif'],
  'ternaire': ['Positif', 'Négatif', 'Indéterminé'],
  'titre': ['Négatif', '1/40', '1/80', '1/160', '1/320', '1/640', '1/1280'],
};

/// `L.type(id)` : le libellé d'un type de variable (affiché sous l'accompagnement).
const Map<String, String> libellesTypeVariable = {
  'numerique': 'Valeur numérique',
  'binaire': 'Positif / Négatif',
  'ternaire': 'Positif / Négatif / Indéterminé',
  'titre': 'Titre (dilution)',
  'liste': 'Choix dans une liste',
  'texte': 'Texte libre',
  'reactif': 'Réactif employé',
  'lot': 'Lot de réactif',
  'expiration': 'Expiration du réactif',
  'commentaire': 'Commentaire de l’examen',
};

bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

/// `C.ageDe(rec)` : l'âge en années — la date de naissance fait TOUJOURS foi ; à défaut l'âge DÉCLARÉ, vieilli des années écoulées depuis
/// sa déclaration (un âge se date, sinon « 45 ans » saisi en 2026 se lirait encore « 45 ans » en 2030).
int? agePatient(FicheLabo? rec, DateTime maintenant) {
  if (rec == null) return null;
  if (_vrai(rec['dateNaissance'])) return ageAnnees(rec['dateNaissance'], maintenant);
  final declare = rec['age'];
  if (declare == null || declare == '') return null;
  final m = RegExp(r'^\s*[-+]?\d+').stringMatch('$declare');
  final n = m == null ? null : int.tryParse(m.trim());
  if (n == null || n < 0) return null;
  if (!_vrai(rec['ageReferenceLe'])) return n;
  final ref = DateTime.tryParse('${rec['ageReferenceLe']}');
  if (ref == null) return n;
  final debut = ref.isUtc ? ref : DateTime.utc(ref.year, ref.month, ref.day);
  final ecoule = (joursEntre(debut, maintenant.toUtc()) / 365.25).floor();
  final plus = ecoule < 0 ? 0 : ecoule;
  return n + plus;
}

/// `C.ageTexte(rec)` : « 45 ans », ou « 45 ans (âge déclaré) » quand aucune date de naissance ne l'établit ; « — » sans âge.
String ageTexte(FicheLabo? rec, DateTime maintenant) {
  final a = agePatient(rec, maintenant);
  if (a == null) return '—';
  final declare = rec != null && !_vrai(rec['dateNaissance']) && rec['age'] != null && rec['age'] != '';
  return '$a an${a > 1 ? 's' : ''}${declare ? ' (âge déclaré)' : ''}';
}

/// Les variables d'un examen telles que paramétrées, dans l'ordre de rendu (`variablesDe`).
List<FicheLabo> variablesExamen(String? code, Iterable<FicheLabo> variablesActives) {
  final l = [for (final v in variablesActives) if (v['examen'] == code) v];
  final idx = [for (var i = 0; i < l.length; i++) (i, l[i])]..sort((a, b) {
      final c = ((a.$2['ordre'] ?? 0) as num).compareTo((b.$2['ordre'] ?? 0) as num);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final x in idx) x.$2];
}

/// Le résumé textuel d'un résultat structuré (« GB 5.5 G/l · GR 4.2 T/l ») : les écrans et états antérieurs au modèle structuré le lisent encore.
String resumeResultat(Iterable<FicheLabo> variables, Map<String, Object?> saisies, String Function(Object?) symbole) {
  final bouts = <String>[];
  for (final v in variables) {
    final accompagnement = _vrai(v['accompagnement']);
    final val = saisies[v['code']];
    if (accompagnement || !_vrai(val)) continue;
    final u = symbole(v['unite']);
    bouts.add('${v['libelle']} ${chaineJs(val)}${u == '—' ? '' : ' $u'}');
  }
  return bouts.join(' · ');
}
