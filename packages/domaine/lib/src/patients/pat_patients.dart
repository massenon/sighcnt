/// M1 — RÉPERTOIRE DES PATIENTS ET ANTÉCÉDENTS : règles portées de `m1-patients.js`, rejouées sur les vecteurs tirés des écrans RÉELS
/// (`test/vecteurs/pat_patients.json`, `pat_antecedents.json`, `pat_profil.json`).
///
/// RG-01 : le code patient `CNT/n/AA` est généré par la fabrique UNIQUE [codePatient] ; il ne se modifie plus. RG-09 : la validité de la carte
/// se lit à la date (moteur `carteValide` de la caisse), jamais sur une copie locale. RG-14 : on archive, on ne supprime pas.
library;

import '../caisse/prise_en_charge.dart' show carteValide;
import '../format/format_fr.dart';
import '../referentiels/regles.dart' show codePatient;
import '../labo/res_saisie.dart' show agePatient;

typedef FichePat = Map<String, Object?>;

bool patVrai(Object? v) => v != null && v != '' && v != 0 && v != false;

/// Les huit groupes sanguins (`D.GROUPES_SANGUINS`).
const patGroupesSanguins = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

/// `D.ANTECEDENTS` : la dernière entrée est l'absence d'antécédent — elle ne se coche pas, elle se déduit d'une liste vide.
const patAntecedents = [
  'Hypertension artérielle',
  'Diabète de type 2',
  'Asthme',
  'Drépanocytose',
  'Ulcère gastrique',
  'Épilepsie',
  'Césarienne antérieure',
  'Tuberculose traitée',
  'Insuffisance rénale',
  'Hépatite B',
  'Aucun antécédent notable',
];
const patAntecedentsRisque = [
  'Drépanocytose',
  'Insuffisance rénale',
  'Épilepsie',
  'Tuberculose traitée',
  'Hépatite B',
];
const patAllergies = [
  'Pénicilline',
  'Sulfamides',
  'Aspirine',
  'Arachide',
  'Iode',
  'Anti-inflammatoires non stéroïdiens',
  'Aucune allergie connue',
];

/// `D.ASSUREURS` (code, nom) — les treize compagnies du document « Liste et contact des assurances partenaires ».
const patAssureurs = <(String, String)>[
  ('AFR', 'AFRICAINE DES ASSURANCES'),
  ('NSIA', 'NSIA ASSURANCE'),
  ('OLEA', 'OLEA ASSURANCE'),
  ('SANLAM', 'SANLAM ASSURANCE'),
  ('TRANSVIE', 'TRANSVIE ASSURANCE'),
  ('SUNU', 'SUNU ASSURANCE'),
  ('DAYO', 'DAYO ASSURANCE'),
  ('SOS', 'SOS ASSURANCE'),
  ('GAB', 'GAB ASSURANCE'),
  ('BECOTRA', 'BECOTRA ASSURANCE'),
  ('NOBILA', 'NOBILA ASSURANCE'),
  ('ASCOMA', 'ASCOMA ASSURANCE'),
  ('ASK', 'ASK ASSURANCE BENIN'),
];

/// `liste(v)` : antécédents et allergies acceptent une liste OU l'ancienne chaîne unique ; « Aucun… » n'est pas une valeur.
List<String> patListe(Object? v) {
  if (v == null || v == '') return const [];
  final t = v is List ? v : [v];
  return [
    for (final x in t)
      if (patVrai(x) &&
          x != 'Aucun antécédent notable' &&
          x != 'Aucune allergie connue')
        '$x'
  ];
}

String patTexteListe(Object? v, [String vide = '—']) {
  final t = patListe(v);
  return t.isEmpty ? vide : t.join(', ');
}

/// `age(p)` : par `C.ageDe` — la fabrique unique, qui connaît l'âge DÉCLARÉ (écart E301).
int? patAge(FichePat p, DateTime maintenant) => agePatient(p, maintenant);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// RG-01 — le prochain code
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `prochainCode()` : le plus grand rang de l'année lu sur les DEUX formes (`CNT/n/AA` et l'ancien `CNTn/AA`), archivés compris — un code attribué
/// ne se réutilise pas (RG-01) — puis la fabrique unique. Écart E300 : l'ancienne expression ne reconnaissait que l'ancien format.
String patProchainCode(Iterable<FichePat> patients, DateTime maintenant) {
  final suffixe = '${maintenant.year}'.substring('${maintenant.year}'.length - 2);
  final re = RegExp(r'^CNT/?(\d+)/(\d{2})$');
  var max = 0;
  for (final p in patients) {
    final m = re.firstMatch('${p['code'] ?? ''}');
    if (m != null && m.group(2) == suffixe) {
      final n = int.parse(m.group(1)!);
      if (n > max) max = n;
    }
  }
  return codePatient(max + 1, maintenant.year);
}

/// `beforeSave` : le code réservé à l'ouverture de l'écran a pu être pris entre-temps (deux guichets).
String? patRefusCode(Iterable<FichePat> patients, String code) =>
    patients.any((p) => p['code'] == code)
        ? 'Ce code dossier est déjà attribué. Recharger la page pour obtenir le suivant.'
        : null;

/// `transformerPatient(v, record)` : ce que l'enregistrement DÉDUIT de la saisie — le nom de la compagnie et l'âge. L'âge est une DÉCLARATION datée
/// quand la date de naissance est inconnue ; l'âge déjà déclaré ne se re-date pas (le re-dater le rajeunirait à chaque ouverture).
FichePat patTransformerPatient(FichePat saisie, FichePat? record, DateTime maintenant) {
  final v = {...saisie};
  final a = patAssureurs.where((x) => x.$1 == v['assureur']).firstOrNull;
  v['assureurNom'] = a?.$2;
  if ('${v['naissanceConnue'] ?? 'date'}' == 'age') {
    v['dateNaissance'] = '';
    final age = v['age'];
    final inchange = record != null &&
        patVrai(record['ageReferenceLe']) &&
        '${record['age']}' == '$age';
    v['ageReferenceLe'] = inchange ? record['ageReferenceLe'] : iso(maintenant);
  } else {
    v['age'] = '';
    v['ageReferenceLe'] = '';
  }
  v.remove('naissanceConnue');
  return v;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Répertoire : indicateurs et filtres
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// RG-09 à la MÊME date que la caisse.
bool patCarteValide(FichePat p, Iterable<FichePat> couvertures, DateTime maintenant) =>
    carteValide(p, [for (final c in couvertures) c], iso(maintenant));

class PatKpisRepertoire {
  const PatKpisRepertoire(this.actifs, this.crees2026, this.assures, this.expirees, this.partAssures);
  final int actifs;
  final int crees2026;
  final int assures;
  final int expirees;

  /// « 57.1 % du répertoire ».
  final String partAssures;
}

PatKpisRepertoire patKpisRepertoire(List<FichePat> rows, Iterable<FichePat> couvertures, DateTime maintenant) {
  final assures = rows.where((p) => patVrai(p['assureur'])).toList();
  final expirees = assures.where((p) => !patCarteValide(p, couvertures, maintenant)).length;
  // « Créés en 2026 » : l'intitulé est statique dans la maquette (l'année du jeu), pas l'année courante.
  final annee = rows.where((p) {
    final d = DateTime.tryParse('${p['dateCreation'] ?? ''}');
    return d != null && d.year == 2026;
  }).length;
  return PatKpisRepertoire(rows.length, annee, assures.length, expirees,
      pourcent(rows.isNotEmpty ? assures.length / rows.length * 100 : 0));
}

/// Filtre « Couverture » : assurés · non assurés · carte expirée.
bool patFiltreCouverture(FichePat p, String v, Iterable<FichePat> couvertures, DateTime maintenant) {
  if (v == 'assure') return patVrai(p['assureur']);
  if (v == 'non') return !patVrai(p['assureur']);
  if (v == 'expiree') {
    return patVrai(p['assureur']) && !patCarteValide(p, couvertures, maintenant);
  }
  return true;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Antécédents & allergies
// ---------------------------------------------------------------------------------------------------------------------------------------------

bool patRisque(FichePat p) =>
    patListe(p['antecedents']).any(patAntecedentsRisque.contains);
bool patAllergique(FichePat p) => patListe(p['allergies']).isNotEmpty;

class PatKpisAntecedents {
  const PatKpisAntecedents(this.renseignes, this.allergies, this.risque, this.sansAntecedent);
  final int renseignes;
  final int allergies;
  final int risque;
  final int sansAntecedent;
}

PatKpisAntecedents patKpisAntecedents(List<FichePat> rows) => PatKpisAntecedents(
    rows.where((p) => patListe(p['antecedents']).isNotEmpty).length,
    rows.where(patAllergique).length,
    rows.where(patRisque).length,
    rows.where((p) => patListe(p['antecedents']).isEmpty).length);

/// Filtres « Allergie » / « Antécédent » : la valeur se cherche DANS la liste (écart E305) ; « Aucun… » = liste vide.
bool patFiltreAllergie(FichePat p, String v) => v == 'Aucune allergie connue'
    ? patListe(p['allergies']).isEmpty
    : patListe(p['allergies']).contains(v);
bool patFiltreAntecedent(FichePat p, String v) => v == 'Aucun antécédent notable'
    ? patListe(p['antecedents']).isEmpty
    : patListe(p['antecedents']).contains(v);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Documents numérisés
// ---------------------------------------------------------------------------------------------------------------------------------------------

const patTypesDocument = [
  'Ordonnance',
  'Résultat de laboratoire',
  'Compte rendu médical',
  'Consentement éclairé',
  'Imagerie / Échographie',
  'Bulletin d’hospitalisation',
  'Facture',
  'Pièce d’identité',
  'Carte d’assurance',
  'Certificat médical',
];

/// `poidsDoc(o)` : « — », « 2 Ko », « 3.0 Mo » (JS : `toFixed(1)` et `Math.round`).
String patPoidsDoc(Object? o) {
  final n = o is num ? o : num.tryParse('${o ?? ''}');
  if (n == null || n == 0) return '—';
  if (n > 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(1)} Mo';
  return '${(n / 1024).round()} Ko';
}

class PatKpisDocuments {
  const PatKpisDocuments(this.total, this.valides, this.enAttente, this.dossiers);
  final int total;
  final int valides;
  final int enAttente;
  final int dossiers;
}

PatKpisDocuments patKpisDocuments(List<FichePat> rows) => PatKpisDocuments(
    rows.length,
    rows.where((r) => r['etat'] == 'valide').length,
    rows.where((r) => r['etat'] == 'en_attente').length,
    {for (final r in rows) '${r['code']}'}.length);

/// « GED-00005 » : le rang suit le NOMBRE de fiches du registre (archivées comprises), comme la maquette.
String patReferenceDocument(int nbFiches) =>
    'GED-${(nbFiches + 1).toString().padLeft(5, '0')}';

/// Fichier d'un document : « PDF · 2 Ko » et la mention déposé / référencé.
String patFormatDocument(String? nomFichier) {
  final f = (nomFichier ?? '').toLowerCase();
  if (f.endsWith('pdf')) return 'PDF';
  if (f.endsWith('png')) return 'PNG';
  if (f.endsWith('webp')) return 'WEBP';
  return 'JPEG';
}
