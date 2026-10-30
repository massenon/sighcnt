/// PRISE EN CHARGE (RG-09) — port de `PR.repartir` (prototype_html/assets/js/parcours.js, vague 2 et vague 60).
///
/// Le moteur de la maquette lisait le magasin ; celui-ci reçoit les fiches EN ARGUMENT (couvertures, souscripteurs,
/// garanties) : même décision, aucun accès à une base — le poste, le mobile et la mère l'appellent avec ce qu'ils ont.
/// Les vecteurs (`test/vecteurs/prise_en_charge.json`) sont engendrés par la maquette, jamais écrits à la main.
///
/// Quatre questions, dans cet ordre, et chaque ligne repart avec son MOTIF (une part patient à 100 % doit toujours
/// pouvoir s'expliquer au guichet) :
///   1. la carte est-elle valide à la date de facturation ? (RG-09, la couverture se lit AUSSI à la date)
///   2. la ligne est-elle exclue par la convention ?
///   3. exige-t-elle un accord préalable, et l'a-t-on ?
///   4. quelle garantie couvre sa catégorie, à quel taux, sous quel plafond ?
library;

import '../format/format_fr.dart';
import '../format/js.dart';

const _unitesPlafond = {
  'acte': 'par acte',
  'jour': 'par jour',
  'an': 'par an',
  'personne_an': 'par personne et par an',
  'personne_2ans': 'par personne, tous les deux ans',
};

/// Résultat de la répartition d'une facture.
class Repartition {
  const Repartition({required this.lignes, required this.souscripteurId, required this.carteValide, required this.grilleSaisie, required this.total, required this.partAssureur, required this.partPatient});
  final List<Map<String, Object?>> lignes;
  final String? souscripteurId;
  final bool carteValide;
  final bool grilleSaisie;
  final double total;
  final double partAssureur;
  final double partPatient;
}

// --- dates : la sémantique de `new Date(texte)` de JavaScript ---------------------------------------------------------
final _dateSeule = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _avecFuseau = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

/// `YYYY-MM-DD` seul = minuit UTC ; avec heure sans fuseau = heure locale ; avec fuseau = cet instant (comme `Date`).
DateTime _dateJs(String texte) {
  if (_dateSeule.hasMatch(texte)) return DateTime.parse('${texte}T00:00:00Z');
  if (texte.contains('T') && !_avecFuseau.hasMatch(texte)) return DateTime.parse(texte);
  return DateTime.parse(texte);
}

/// `C.iso(date)` : le jour **local** de l'instant (getFullYear/getMonth/getDate).
String _jourLocal(String texte) => iso(_dateJs(texte).toLocal());

/// Une fiche archivée (RG-14) porte `statut: 'archive'` ; le magasin de la maquette ne lit que les autres (`active()`).
bool _actif(Map f) => f['statut'] != 'archive';

// --- couverture datée --------------------------------------------------------------------------------------------------
/// La couverture EN FORCE à une date. Sans historique, la fiche du dossier fait foi (dossiers antérieurs au mécanisme) ;
/// avec un historique dont aucune période ne contient la date : aucune couverture.
Map<String, Object?>? couvertureALaDate(Map<String, Object?>? patient, List<Map<String, Object?>> couvertures, String date) {
  if (patient == null) return null;
  final d = _jourLocal(date);
  final hist = couvertures.where((c) => _actif(c) && c['patientId'] == patient['id']).toList()
    ..sort((a, b) => '${b['debut'] ?? '0000-00-00'}'.compareTo('${a['debut'] ?? '0000-00-00'}'));
  for (final c in hist) {
    final debut = c['debut'] as String?;
    final fin = c['fin'] as String?;
    if (debut != null && debut.isNotEmpty && d.compareTo(debut) < 0) continue;
    if (fin != null && fin.isNotEmpty && d.compareTo(fin) > 0) continue;
    return c;
  }
  if (hist.isNotEmpty) return null;
  if (!_vrai(patient['assureur'])) return null;
  return {
    'origine': 'fiche', 'patientId': patient['id'], 'assureur': patient['assureur'], 'assureurNom': patient['assureurNom'],
    'numeroPolice': patient['numeroPolice'], 'categorieAssurance': patient['categorieAssurance'],
    'tauxPriseEnCharge': patient['tauxPriseEnCharge'], 'carteExpiration': patient['carteExpiration'],
    'souscripteurId': patient['souscripteurId'], 'debut': null, 'fin': null,
  };
}

/// RG-09 se lit À LA DATE : la carte est valide si elle existe, porte une expiration, et expire au plus tôt à la date.
bool carteValide(Map<String, Object?>? patient, List<Map<String, Object?>> couvertures, String date) {
  if (patient == null) return false;
  final c = couvertureALaDate(patient, couvertures, date);
  if (c == null || !_vrai(c['assureur']) || !_vrai(c['carteExpiration'])) return false;
  return !_dateJs('${c['carteExpiration']}').isBefore(_dateJs(date));
}

Map<String, Object?>? souscripteurDe(Map<String, Object?>? patient, List<Map<String, Object?>> couvertures, List<Map<String, Object?>> souscripteurs, String date) {
  if (patient == null) return null;
  final c = couvertureALaDate(patient, couvertures, date);
  if (c == null) return null;
  final id = c['souscripteurId'];
  if (!_vrai(id)) return null;
  for (final s in souscripteurs) {
    if (s['id'] == id) return s;
  }
  return null;
}

/// Garanties applicables : celles du souscripteur de la date, sinon celles de la compagnie (sans souscripteur).
List<Map<String, Object?>> garantiesDe(Map<String, Object?>? sous, List<Map<String, Object?>> garanties) {
  if (sous == null) return const [];
  final toutes = garanties.where(_actif).toList();
  final propres = toutes.where((g) => g['souscripteurId'] == sous['id']).toList();
  if (propres.isNotEmpty) return propres;
  return toutes.where((g) => !_vrai(g['souscripteurId']) && g['assureur'] == sous['assureur']).toList();
}

// --- proximité de libellés ---------------------------------------------------------------------------------------------
const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
};

List<String> _mots(Object? t) {
  final s = ('${t ?? ''}').toLowerCase().split('').map((c) => _accents[c] ?? c).join();
  return s.split(RegExp(r'[^a-z0-9]+'));
}

int _proximite(Object? a, Object? b) {
  final ma = _mots(a).where((m) => m.length > 3);
  final mb = _mots(b).where((m) => m.length > 3).toList();
  var n = 0;
  for (final m in ma) {
    if (mb.contains(m)) n++;
  }
  return n;
}

String? _contient(Object? liste, Object? texte) {
  if (liste is! List || liste.isEmpty || !_vrai(texte)) return null;
  final t = '$texte'.toLowerCase();
  for (final e in liste) {
    final s = '$e'.toLowerCase();
    if (t.contains(s) || s.contains(t)) return '$e';
  }
  return null;
}

/// « Vrai » au sens de JavaScript pour les valeurs de fiche : null, '', 0 et false ne comptent pas.
bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

String _texteJs(Object? v) => v is double && v == v.truncateToDouble() ? v.toInt().toString() : '$v';

double _montant(Object? v) => nombreOuZero(v);

/// `PR.repartir(patient, lignes, {date})`. `lignes` : `{libelle, categorie, montant, accordObtenu}`.
Repartition repartir({
  required Map<String, Object?>? patient,
  required List<Map<String, Object?>> lignes,
  required String date,
  List<Map<String, Object?>> couvertures = const [],
  List<Map<String, Object?>> souscripteurs = const [],
  List<Map<String, Object?>> garanties = const [],
}) {
  final sous = souscripteurDe(patient, couvertures, souscripteurs, date);
  final grille = garantiesDe(sous, garanties);
  final valide = carteValide(patient, couvertures, date);

  final detail = lignes.map((l) {
    final montant = _montant(l['montant']);
    final categorie = _vrai(l['categorie']) ? '${l['categorie']}' : 'autre';
    final base = <String, Object?>{
      'libelle': l['libelle'], 'categorie': categorie, 'montant': montant,
      'partAssureur': 0, 'partPatient': montant, 'taux': 0, 'plafond': null, 'garantie': null,
    };
    Map<String, Object?> avec(Map<String, Object?> extra) => {...base, ...extra};

    if (patient == null || !_vrai(patient['assureur'])) return avec({'motif': 'Patient non assuré'});
    if (!valide) return avec({'motif': 'Carte non valide à la date de facturation (RG-09)'});
    if (sous == null) return avec({'motif': 'Assuré non rattaché à un souscripteur'});
    if (grille.isEmpty) return avec({'motif': 'Convention non saisie pour ${sous['nom']}'});

    final exclu = _contient(sous['actesExclus'], l['libelle']) ?? _contient(sous['produitsExclus'], l['libelle']);
    if (exclu != null) return avec({'motif': 'Exclu de la convention : $exclu', 'exclu': true});

    final accord = _contient(sous['accordPrealable'], l['libelle']);
    if (accord != null && !_vrai(l['accordObtenu'])) {
      return avec({'motif': 'Accord préalable requis et non obtenu : $accord', 'accordRequis': accord});
    }

    // Une catégorie porte souvent plusieurs garanties (généraliste plafonnée à 5 000, spécialiste à 10 000) :
    // la première venue appliquerait le mauvais plafond, on retient celle dont le libellé colle le mieux à la ligne.
    final candidates = grille.where((x) => x['categorie'] == categorie).toList();
    if (candidates.isEmpty) return avec({'motif': 'Aucune garantie pour la catégorie « $categorie »'});
    var g = candidates.first;
    var meilleur = -1;
    for (final x in candidates) {
      final s = _proximite(x['libelle'], l['libelle']);
      if (s > meilleur) {
        meilleur = s;
        g = x;
      }
    }

    final taux = _vrai(g['taux']) ? (g['taux'] as num).toDouble() : 0.0;
    var couvert = arrondiJs(montant * taux / 100);
    var motif = 'Garantie ${g['libelle']} — ${_texteJs(g['taux'] is num ? (g['taux'] as num).toDouble() : g['taux'])} %';
    final plafond = g['plafond'] as num?;
    if (plafond != null && couvert > plafond) {
      couvert = plafond.toDouble();
      final unite = g['unitePlafond'];
      motif += ', plafonnée à ${money(plafond, avecDevise: false)}${_vrai(unite) ? ' ${_unitesPlafond[unite] ?? unite}' : ''}';
    }
    return avec({'partAssureur': couvert, 'partPatient': montant - couvert, 'taux': g['taux'], 'plafond': g['plafond'], 'garantie': g['libelle'], 'motif': motif});
  }).toList();

  double somme(String cle) => detail.fold(0.0, (a, x) => a + nombreOuZero(x[cle]));
  return Repartition(
    lignes: detail,
    souscripteurId: sous == null ? null : '${sous['id']}',
    carteValide: valide,
    grilleSaisie: grille.isNotEmpty,
    total: somme('montant'),
    partAssureur: somme('partAssureur'),
    partPatient: somme('partPatient'),
  );
}
