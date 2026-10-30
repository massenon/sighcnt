import 'mat_donnees.dart';

/// RÈGLES DE LA MATERNITÉ (M4) — portées de `prototype_html/assets/js/modules/m4-maternite.js` et rejouées sur les vecteurs de la maquette
/// (`test/vecteurs/mat_*.json`, engendrés par `prototype_html/build/vecteurs-maternite.js`). Les référentiels (`mat_donnees.dart`) sont ENGENDRÉS depuis
/// `data-maternite.js` : rapport officiel du 27/08/2026 — 10 fonctions SONU, 15 méthodes PF (codification A/N reprise TELLE QUELLE), 3 CPoN, bornes écrites
/// (PC 32–38, PT 30–36, alerte Apgar 5 min < 7, âges CPN 18–35), modèle de la PARTOGRAPHIE (alerte 4 cm + 1 cm/h, action décalée de 4 h).
/// Symboles préfixés `mat` / `Mat` (le barrel `sigh_domaine.dart` en réunit beaucoup d'autres).

typedef MatFiche = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Référentiels (typés)
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<MatFiche> matListe(String nom) => [
      for (final x in (matDonnees[nom] as List)) (x as Map).cast<String, Object?>()
    ];
MatFiche matCarte(String nom) => (matDonnees[nom] as Map).cast<String, Object?>();
List<String> matTextes(String nom) => [for (final x in (matDonnees[nom] as List)) '$x'];

/// Les 10 fonctions SONU (7 SONUB + 3 SONUC), Tableau A du rapport.
List<MatFiche> get matFonctionsSonu => [
      for (final x in (matCarte('SONU')['fonctions'] as List)) (x as Map).cast<String, Object?>()
    ];
MatFiche? matFonctionSonu(Object? numero) {
  final n = numero is num ? numero : int.tryParse('$numero');
  for (final f in matFonctionsSonu) {
    if (f['num'] == n) return f;
  }
  return null;
}

/// Les 15 méthodes contraceptives du rapport (Tableau B), choix exclusif.
List<MatFiche> get matMethodesPf => matListe('METHODES_PF');
MatFiche? matMethodePf(Object? code) {
  for (final m in matMethodesPf) {
    if (m['code'] == code) return m;
  }
  return null;
}

/// A = nouvelle acceptante, N = ancienne (renouvellement ou changement) : la codification des registres papier nationaux, reprise telle quelle.
List<MatFiche> get matStatutsAcceptante => matListe('STATUTS_ACCEPTANTE');
List<String> get matDosesSp => matTextes('DOSES_SP');
List<MatFiche> get matTypesCpon => matListe('TYPES_CPON');
MatFiche? matTypeCpon(Object? code) {
  for (final t in matTypesCpon) {
    if (t['code'] == code) return t;
  }
  return null;
}

List<MatFiche> get matUrgencesMaternite => matListe('URGENCES_MATERNITE');
MatFiche? matUrgenceMaternite(Object? code) {
  for (final u in matUrgencesMaternite) {
    if (u['code'] == code) return u;
  }
  return null;
}

List<String> get matTranchesAgeCuratif => matTextes('TRANCHES_AGE_CURATIF');
List<String> get matTypesAccouchement => matTextes('TYPES_ACCOUCHEMENT');
List<String> get matActesAccouchement => matTextes('ACTES_ACCOUCHEMENT');
List<String> get matGroupesSanguins => matTextes('GROUPES_SANGUINS');
MatFiche get matPtme => matCarte('PTME');
MatFiche get matPartogrammeModele => matCarte('PARTOGRAMME');
List<MatFiche> get matFacteursSurveillance => matListe('FACTEURS_SURVEILLANCE');
List<MatFiche> get matExamensDossier => matListe('EXAMENS_DOSSIER');
List<String> get matDroitsFondamentaux => matTextes('DROITS_FONDAMENTAUX');
List<String> get matPlanAccouchement => matTextes('PLAN_ACCOUCHEMENT');
List<MatFiche> get matComptesRendus => matListe('COMPTES_RENDUS_MATERNITE');

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Nombres et textes à la façon de la maquette
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un nombre lu d'une fiche (nombre, ou texte saisi) ; `null` si absent ou illisible.
num? matNum(Object? v) {
  if (v == null || v == '') return null;
  if (v is num) return v;
  return num.tryParse('$v'.trim().replaceAll(',', '.'));
}

/// `String(3)` → « 3 », `String(3.1)` → « 3.1 » : JavaScript n'écrit pas « 3.0 ».
String matTexteNombre(Object? v) {
  final n = matNum(v);
  if (n == null) return '';
  if (n is int) return '$n';
  return n == n.truncateToDouble() ? '${n.toInt()}' : '$n';
}

/// Un nombre saisi : entier s'il est entier (`Number('3')`), décimal sinon ; `null` si vide.
num? matNombreSaisi(Object? v) {
  final n = matNum(v);
  if (n == null) return null;
  return n == n.truncateToDouble() && n.abs() < 1e15 ? n.toInt() : n;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Références : le registre fait foi, jamais un compteur de page (écart E400)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `C.referenceSuivante(prefixe, 4, fiches)` : le plus grand rang déjà écrit pour ce préfixe — archivées comprises —, plus un.
String matReferenceSuivante(String prefixe, Iterable<MatFiche> fiches, {int largeur = 4}) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final m = RegExp(r'^\s*[+-]?\d+').firstMatch(r.substring(prefixe.length));
      final k = m == null ? 0 : (int.tryParse(m.group(0)!.trim()) ?? 0);
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Nouveau-né — Module C du rapport
// ---------------------------------------------------------------------------------------------------------------------------------------------

class MatBornesNouveauNe {
  const MatBornesNouveauNe(this.pcMin, this.pcMax, this.ptMin, this.ptMax, this.apgarSeuil5min);
  final num pcMin, pcMax, ptMin, ptMax, apgarSeuil5min;
}

MatBornesNouveauNe get matBornesNouveauNe {
  final b = matCarte('BORNES_NOUVEAU_NE');
  final pc = (b['pc'] as Map).cast<String, Object?>(), pt = (b['pt'] as Map).cast<String, Object?>();
  return MatBornesNouveauNe(pc['min'] as num, pc['max'] as num, pt['min'] as num, pt['max'] as num, b['apgarSeuil5min'] as num);
}

/// `v.pc != null && (v.pc < min || v.pc > max)` : une mesure ABSENTE n'est pas hors bornes (jamais un zéro).
bool matPcHorsBornes(MatFiche f) {
  final v = matNum(f['pc']);
  final b = matBornesNouveauNe;
  return v != null && (v < b.pcMin || v > b.pcMax);
}

bool matPtHorsBornes(MatFiche f) {
  final v = matNum(f['pt']);
  final b = matBornesNouveauNe;
  return v != null && (v < b.ptMin || v > b.ptMax);
}

/// Alerte Apgar : `apgar5 < 7` (strict) — un 7 ne déclenche rien.
bool matApgarAlerte(MatFiche f) {
  final v = matNum(f['apgar5']);
  return v != null && v < matBornesNouveauNe.apgarSeuil5min;
}

/// `alertesNouveauNe(v)` : les motifs, dans l'ordre PC, PT, Apgar. Le message d'alerte reste GÉNÉRIQUE (aucune donnée médicale).
List<String> matAlertesNouveauNe(MatFiche f) => [
      if (matPcHorsBornes(f)) 'PC',
      if (matPtHorsBornes(f)) 'PT',
      if (matApgarAlerte(f)) 'Apgar',
    ];

const String matMessageAlerteNouveauNe = 'Une mesure néonatale sort des bornes de surveillance — ouvrir le dossier du nouveau-né.';

/// `apgarTexte(r)` : « 1 / 5 / 10 », un tiret pour un temps non relevé ; l'ancien score unique s'écrit « n/10 ».
String matApgarTexte(MatFiche r) {
  if (r['apgar1'] == null && r['apgar5'] == null && r['apgar'] != null) return '${matTexteNombre(r['apgar'])}/10';
  String t(Object? v) => v == null ? '—' : matTexteNombre(v);
  return '${t(r['apgar1'])} / ${t(r['apgar5'])} / ${t(r['apgar10'])}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// CPN
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Facteur de risque CPN : âge < 18 ou > 35 ans, ET la sage-femme n'a pas coché GAR. On SIGNALE, on ne coche pas à sa place.
/// L'âge est `floor(jours depuis la naissance / 365,25)`.
bool matAgeHorsFenetreCpn(Object? dateNaissance, bool gar, DateTime auj) {
  final n = DateTime.tryParse('${dateNaissance ?? ''}');
  if (n == null) return false;
  final age = (DateTime.utc(auj.year, auj.month, auj.day).difference(DateTime.utc(n.year, n.month, n.day)).inDays / 365.25).floor();
  final b = matCarte('AGES_RISQUE_CPN');
  return (age < (b['min'] as num) || age > (b['max'] as num)) && !gar;
}

String matMessageAgeCpn() {
  final b = matCarte('AGES_RISQUE_CPN');
  return 'Âge maternel hors de la fenêtre ${b['min']}–${b['max']} ans : facteur de risque CPN à évaluer (rapport du 27/08/2026).';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Suivi de grossesse : verrou d'admission (Module A) — il refuse en nommant OÙ corriger
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `beforeSave` de `m4-maternite` : l'âge est une donnée VITALE, il vient du dossier patient ; le poids est obligatoire à l'admission.
String? matRefusAdmission({required String patientCode, required bool dateNaissanceConnue, required Object? poids}) {
  if (!dateNaissanceConnue) {
    return 'La date de naissance manque au dossier $patientCode : l’admission maternité exige l’âge (rapport du 27/08/2026). Compléter le dossier patient avant d’admettre.';
  }
  if (poids == null || poids == '') return 'Le poids est obligatoire à l’admission (rapport du 27/08/2026).';
  return null;
}

/// `C.daysBetween(AUJ, dpa)` : jours calendaires entre deux dates (heures ignorées).
int matJoursEntre(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// CPoN, Case 27
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Hémorragie ANTE-partum : sans étiologie, elle est refusée — c'est ce que le rapport demande de corréler.
String? matRefusCpon({required bool hemorragieAntePartum, required Object? etiologie}) =>
    hemorragieAntePartum && (etiologie == null || etiologie == '')
        ? 'Une hémorragie ante-partum se précise : l’étiologie est ce que le rapport demande de corréler.'
        : null;

/// Case 27 : le nombre de jours n'a de sens que si l'hospitalisation est cochée — exigé si oui, refusé si non.
String? matRefusCase27({required bool hospitalisee, required Object? jours}) {
  final vide = jours == null || jours == '' || jours == 0;
  if (hospitalisee && (jours == null || jours == '')) return 'La Case 27 exige le nombre de jours quand la femme est hospitalisée.';
  if (!hospitalisee && !vide) return 'Un nombre de jours sans hospitalisation cochée n’a pas de sens (Case 27).';
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// PARTOGRAMME — la PARTOGRAPHIE nationale
// ---------------------------------------------------------------------------------------------------------------------------------------------

class MatModelePartogramme {
  const MatModelePartogramme(this.alerteDepart, this.alerteParHeure, this.actionDecalageHeures);
  final num alerteDepart, alerteParHeure, actionDecalageHeures;
}

MatModelePartogramme get matModelePartogramme {
  final p = matPartogrammeModele;
  return MatModelePartogramme(p['alerteDepart'] as num, p['alerteParHeure'] as num, p['actionDecalageHeures'] as num);
}

/// `franchitAction(r)` : une mesure à l'heure h ≥ 4 dont la dilatation est INFÉRIEURE à la ligne d'action (`4 + (h − 4) × 1`). L'égalité ne franchit pas.
bool matFranchitAction(MatFiche partogramme) {
  final p = matModelePartogramme;
  return ((partogramme['mesures'] as List?) ?? const []).any((m) {
    final mm = (m as Map).cast<String, Object?>();
    final h = matNum(mm['heure']) ?? 0, d = matNum(mm['dilatation']);
    if (d == null) return false;
    final attendu = p.alerteDepart + (h - p.actionDecalageHeures > 0 ? h - p.actionDecalageHeures : 0) * p.alerteParHeure;
    return h >= p.actionDecalageHeures && d < attendu;
  });
}

/// Les séries du graphique : étiquettes « n h », ligne d'alerte (4 cm, +1 cm/h, plafonnée à 10), ligne d'action (vide avant l'heure 4, puis parallèle
/// à l'alerte, décalée de 4 h), dilatation relevée (vide sans mesure à cette heure).
({List<String> etiquettes, List<num> alerte, List<num?> action, List<num?> dilatation}) matSeriesPartogramme(MatFiche p) {
  final m = matModelePartogramme;
  final mesures = [for (final x in ((p['mesures'] as List?) ?? const [])) (x as Map).cast<String, Object?>()];
  var maxH = 12;
  for (final x in mesures) {
    final h = (matNum(x['heure']) ?? 0).toInt();
    if (h > maxH) maxH = h;
  }
  num plafond(num v) => v < 10 ? v : 10;
  final etiq = <String>[], alerte = <num>[], action = <num?>[], dil = <num?>[];
  for (var h = 0; h <= maxH; h++) {
    etiq.add('$h h');
    alerte.add(plafond(m.alerteDepart + h * m.alerteParHeure));
    action.add(h < m.actionDecalageHeures ? null : plafond(m.alerteDepart + (h - m.actionDecalageHeures) * m.alerteParHeure));
    num? d;
    for (final x in mesures) {
      if ((matNum(x['heure']) ?? -1) == h) {
        d = matNum(x['dilatation']);
        break;
      }
    }
    dil.add(d);
  }
  return (etiquettes: etiq, alerte: alerte, action: action, dilatation: dil);
}

/// Ajout d'une mesure : tri par heure (stable), clôture à 10 cm (« Dilatation complète — expulsion »).
({List<MatFiche> mesures, bool clos, String? resume}) matAjouterMesure(MatFiche p, MatFiche mesure) {
  final mesures = <MatFiche>[for (final x in ((p['mesures'] as List?) ?? const [])) (x as Map).cast<String, Object?>(), mesure];
  final indexees = [for (var i = 0; i < mesures.length; i++) (i, mesures[i])];
  indexees.sort((a, b) {
    final c = (matNum(a.$2['heure']) ?? 0).compareTo(matNum(b.$2['heure']) ?? 0);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  final complete = (matNum(mesure['dilatation']) ?? 0) >= 10;
  return (
    mesures: [for (final e in indexees) e.$2],
    clos: complete,
    resume: complete ? 'Dilatation complète — expulsion' : p['resume'] as String?
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// DOSSIER OBSTÉTRICAL
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `numeroDossierObstetrical(date)` : série ANNUELLE, cinq chiffres comme le registre papier (« 00007/26 », écart E404). Le plus grand rang de l'année,
/// archivés compris, plus un ; un numéro illisible ou d'une autre année ne compte pas.
String matNumeroDossier(Iterable<MatFiche> existants, DateTime date) {
  final an = '${date.year}'.substring(2);
  var max = 0;
  for (final x in existants) {
    final m = RegExp(r'^(\d+)/(\d{2})$').firstMatch('${x['numeroDossier'] ?? ''}');
    if (m != null && m.group(2) == an) {
      final k = int.parse(m.group(1)!);
      if (k > max) max = k;
    }
  }
  return '${(max + 1).toString().padLeft(5, '0')}/$an';
}

/// Les facteurs de surveillance COCHÉS, dans l'ordre du formulaire : le risque se déduit de leur CUMUL, jamais d'un champ « risque ».
List<MatFiche> matFacteursCoches(MatFiche d) {
  final f = (d['facteurs'] as Map?)?.cast<String, Object?>() ?? const {};
  return [
    for (final x in matFacteursSurveillance)
      if (f[x['code']] == true) x
  ];
}

bool matEstGar(MatFiche d) => matFacteursCoches(d).isNotEmpty;

/// La date probable de l'accouchement se DÉDUIT de la DDR (280 jours) — la saisir à part ouvrirait deux dates qui ne se recoupent pas.
String? matDpaDepuisDdr(Object? ddr) {
  final d = DateTime.tryParse('${ddr ?? ''}');
  if (d == null) return null;
  final r = DateTime.utc(d.year, d.month, d.day).add(const Duration(days: 280));
  String p(int n) => n.toString().padLeft(2, '0');
  return '${r.year}-${p(r.month)}-${p(r.day)}';
}

/// `C.age(naissance)` : années révolues (`floor(jours / 365,25)`), jamais négatif ; `null` sans date.
int? matAge(Object? naissance, DateTime auj) {
  final n = DateTime.tryParse('${naissance ?? ''}');
  if (n == null) return null;
  final j = matJoursEntre(n, auj);
  final a = (j / 365.25).floor();
  return a < 0 ? 0 : a;
}

/// La fiche d'un dossier ouvert depuis la saisie : les cases `facteur_<code>` se rangent dans UNE carte `facteurs`, la DPA vient de la DDR.
MatFiche matRanger(MatFiche valeurs) {
  final v = {...valeurs};
  final facteurs = <String, Object?>{};
  for (final f in matFacteursSurveillance) {
    final k = 'facteur_${f['code']}';
    if (valeurs[k] == true) facteurs['${f['code']}'] = true;
  }
  v['facteurs'] = facteurs;
  final dpa = matDpaDepuisDdr(v['ddr']);
  if (dpa != null) v['dpa'] = dpa;
  return v;
}
