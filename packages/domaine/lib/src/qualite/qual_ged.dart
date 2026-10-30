import '../format/format_fr.dart';
import '../format/js.dart';
import 'qual_enquetes.dart' show QualFiche;

/// GED — GESTION DOCUMENTAIRE (bibliothèque de l'ÉTABLISSEMENT, workflow de validation, archivage & conservation). Règles portées de
/// `prototype_html/assets/js/modules/ged.js` et rejouées sur les vecteurs de la maquette (`test/vecteurs/qualite.json`).
///
/// La bibliothèque de l'établissement (`documents`) est DISTINCTE des documents du dossier patient (`documentsPatient`, module M1) : les confondre
/// ferait apparaître les unes dans l'écran des autres. RG-14 : retirer une pièce l'archive, elle reste restaurable.

/// `D.GED_CATEGORIES` : (identifiant, libellé, nature du rattachement, icône).
const qualGedCategories = [
  ('ordonnance', 'Ordonnances', 'Patient', 'file-text'),
  ('resultat', 'Résultats de laboratoire', 'Patient', 'flask-conical'),
  ('rapport', 'Rapports médicaux', 'Patient', 'stethoscope'),
  ('facture_patient', 'Factures patients', 'Patient', 'receipt'),
  ('bon_commande', 'Bons de commande', 'Fournisseur', 'truck'),
  ('bon_livraison', 'Bons de livraison', 'Fournisseur', 'package-check'),
  ('facture_fournisseur', 'Factures fournisseurs', 'Fournisseur', 'file-text'),
  ('contrat', 'Contrats RH', 'Employé', 'file-signature'),
  ('bulletin', 'Bulletins de paie', 'Employé', 'banknote'),
  ('courrier', 'Courriers administratifs', 'Administration', 'mail'),
  ('cloture_exercice', 'Clôtures d’exercice', 'Administration', 'lock'),
];

/// Les quatre natures de rattachement, dans l'ordre de l'explorateur.
const qualGedRattachements = ['Patient', 'Employé', 'Fournisseur', 'Administration'];

/// L'état de validation d'un document : (libellé, ton).
const qualGedValidations = {
  'valide': ('Validé', 'success'),
  'en_attente': ('En attente', 'warning'),
  'rejete': ('Rejeté', 'danger'),
};

/// Les six étapes du circuit : (identifiant, libellé, ton, icône).
const qualGedEtapes = [
  ('depot', 'Dépôt', 'neutral', 'upload'),
  ('indexation', 'Indexation', 'info', 'tags'),
  ('controle', 'Contrôle', 'info', 'search-check'),
  ('validation', 'Validation', 'warning', 'badge-check'),
  ('signature', 'Signature', 'navy', 'pen-tool'),
  ('classement', 'Classement', 'success', 'folder-check'),
];

String qualGedCategorieLabel(Object? id) {
  for (final c in qualGedCategories) {
    if (c.$1 == id) return c.$2;
  }
  return '$id';
}

String qualGedCategorieIcone(Object? id) {
  for (final c in qualGedCategories) {
    if (c.$1 == id) return c.$4;
  }
  return 'file';
}

bool _v(Object? x) => x != null && x != false && x != '' && x != 0;
double _num(Object? v) => nombreOuZero(v);

/// `(C.sum(rows, 'taille') / 1024).toFixed(1) + ' Mo'` : la taille est en Ko.
String qualGedVolume(Iterable<QualFiche> rows) =>
    '${toFixedJs(rows.fold<double>(0, (a, d) => a + _num(d['taille'])) / 1024, 1)} Mo';

/// Les huit indicateurs de la bibliothèque.
class QualGedBibliotheque {
  const QualGedBibliotheque(this.numerises, this.valides, this.enAttente, this.rejetes, this.signes, this.archives, this.volume, this.consultations);
  final int numerises, valides, enAttente, rejetes, signes, archives;
  final String volume;
  final int consultations;
}

QualGedBibliotheque qualGedBibliotheque(List<QualFiche> rows) => QualGedBibliotheque(
    rows.length,
    rows.where((d) => d['etatValidation'] == 'valide').length,
    rows.where((d) => d['etatValidation'] == 'en_attente').length,
    rows.where((d) => d['etatValidation'] == 'rejete').length,
    rows.where((d) => _v(d['signe'])).length,
    rows.where((d) => _v(d['archive'])).length,
    qualGedVolume(rows),
    rows.fold<double>(0, (a, d) => a + _num(d['consultations'])).round());

/// L'explorateur : pour une nature de rattachement, le nombre de documents et, par catégorie de cette nature, le nombre rattaché.
({int total, List<(String, int)> parCategorie}) qualGedExplorateur(List<QualFiche> rows, String rattachement) {
  final sel = rows.where((d) => d['rattachement'] == rattachement).toList();
  return (
    total: sel.length,
    parCategorie: [
      for (final c in qualGedCategories)
        if (c.$3 == rattachement) (c.$2, sel.where((d) => d['categorie'] == c.$1).length)
    ]
  );
}

DateTime? _date(Object? v) => DateTime.tryParse('$v');

/// `echeance(d)` : la date du document + la durée de conservation × 365 jours.
DateTime? qualGedEcheance(QualFiche d) {
  final x = _date(d['date']);
  if (x == null) return null;
  return DateTime(x.year, x.month, x.day + (_num(d['conservation']) * 365).round());
}

/// `expire(d)` : la conservation légale est échue à [aujourdhui].
bool qualGedExpire(QualFiche d, DateTime aujourdhui) {
  final e = qualGedEcheance(d);
  return e != null && e.isBefore(aujourdhui);
}

/// Les quatre indicateurs de l'archivage.
class QualGedArchives {
  const QualGedArchives(this.actives, this.definitives, this.echues, this.volume);
  final int actives, definitives, echues;
  final String volume;
}

QualGedArchives qualGedArchives(List<QualFiche> rows, DateTime aujourdhui) => QualGedArchives(
    rows.where((d) => !_v(d['archive'])).length,
    rows.where((d) => _v(d['archive'])).length,
    rows.where((d) => qualGedExpire(d, aujourdhui)).length,
    qualGedVolume(rows));

/// Répartition par durée de conservation, clés numériques triées : (« 5 ans », nombre).
List<(String, int)> qualGedParConservation(List<QualFiche> rows) {
  final g = <num, int>{};
  for (final d in rows) {
    final k = _num(d['conservation']);
    g[k] = (g[k] ?? 0) + 1;
  }
  final cles = g.keys.toList()..sort();
  return [for (final k in cles) ('${k == k.truncate() ? k.truncate() : k} ans', g[k]!)];
}

/// Volume documentaire par catégorie, dans l'ordre de première apparition : (libellé, nombre).
List<(String, int)> qualGedParCategorie(List<QualFiche> rows) {
  final g = <String, int>{};
  for (final d in rows) {
    final k = '${d['categorie']}';
    g[k] = (g[k] ?? 0) + 1;
  }
  return [for (final e in g.entries) (qualGedCategorieLabel(e.key), e.value)];
}

/// Le texte de la mention « conservation échue » sous l'archivage.
String qualGedNoteEchus(int n) =>
    '$n document(s) ont atteint leur durée légale de conservation. Leur destruction doit faire l’objet d’une procédure encadrée et d’un procès-verbal signé.';

/// « En attente depuis N j » : jours entre le dépôt et aujourd'hui.
int qualGedAnciennete(QualFiche d, DateTime aujourdhui) {
  final x = _date(d['date']);
  if (x == null) return 0;
  return arrondiJs(aujourdhui.difference(x).inMilliseconds / 86400000).toInt();
}

/// Les événements de traçabilité du tiroir d'un document : (titre, détail, date, ton).
List<(String, String, String, String)> qualGedTrace(QualFiche d) {
  String fr(DateTime? x) => x == null ? '' : dateFR(x);
  DateTime? plus(int n) {
    final x = _date(d['date']);
    return x == null ? null : DateTime(x.year, x.month, x.day + n);
  }

  final date = fr(_date(d['date']));
  return [
    ('Document déposé', 'Par ${d['deposePar']}', date, 'success'),
    ('Indexation automatique', 'Rattaché au dossier ${d['codeRattachement']}', date, 'info'),
    if (d['etatValidation'] == 'valide') ('Document validé', 'Workflow de validation clôturé', fr(plus(2)), 'success'),
    if (d['etatValidation'] == 'rejete') ('Document rejeté', 'À corriger et redéposer', fr(plus(2)), 'danger'),
    if (_v(d['archive'])) ('Archivage', 'Conservation ${d['conservation']} ans', fr(plus(30)), 'neutral'),
  ];
}

/// Valider un document seul : la validation APPOSE la signature électronique et verrouille le document.
const qualGedValidationSignee = {'etatValidation': 'valide', 'signe': true};

/// Valider une SÉLECTION : l'état seul change (la maquette ne signe pas en masse — écart consigné).
const qualGedValidationSelection = {'etatValidation': 'valide'};

/// Rejeter : l'état et le motif, renvoyés au déposant.
Map<String, Object?> qualGedRejet(String motif) => {'etatValidation': 'rejete', 'motifRejet': motif};
